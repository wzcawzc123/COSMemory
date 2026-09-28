#!/system/bin/sh
# engine/exec.sh — 执行层(安全验证 + 回滚记录 + stats)
# KILL/KEEPADJ 前必须校验 /proc/<pid> cmdline 含目标包名(防 PID 复用)

apply_actions() {
  # $1=动作行文件 $2=state目录; 输出 APPLIED/KILLED/FAILED
  ap=0; ki=0; fa=0
  while read -r op a b c; do
    case "$op" in
    KEEPADJ)
      pid=$a; pkg=$b; tgt=$c
      [ -d "/proc/$pid" ] || { fa=$((fa+1)); continue; }
      cur=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
      case "$cur" in (*"$pkg"*) ;; (*) fa=$((fa+1)); continue;; esac
      before=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
      [ "$before" = "$tgt" ] && continue
      [ -f "$2/adj_$pid" ] || echo "orig=$before pkg=$pkg" > "$2/adj_$pid"
      echo "$tgt" > /proc/$pid/oom_score_adj 2>/dev/null || { fa=$((fa+1)); continue; }
      after=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
      if [ "$after" = "$tgt" ]; then ap=$((ap+1)); log_stat "KEEPADJ $pkg $before->$tgt"
      else fa=$((fa+1)); fi
      ;;
    KILL)
      pid=$a; pkg=$b
      [ -d "/proc/$pid" ] || { fa=$((fa+1)); continue; }
      cur=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
      case "$cur" in (*"$pkg"*) ;; (*) fa=$((fa+1)); continue;; esac
      if kill -9 "$pid" 2>/dev/null; then ki=$((ki+1)); log_stat "KILL $pkg"
      else fa=$((fa+1)); fi
      ;;
    SKIP|'#'*|'') : ;;
    *) fa=$((fa+1)) ;;
    esac
  done < "$1"
  echo "APPLIED=$ap KILLED=$ki FAILED=$fa"
}

restore_state() {
  for f in "$1"/adj_*; do
    [ -f "$f" ] || continue
    orig=$(sed -n "s/^orig=//p" "$f" | cut -d" " -f1); pid=${f##*adj_}
    [ -n "$orig" ] && [ -d "/proc/$pid" ] && echo "$orig" > /proc/$pid/oom_score_adj 2>/dev/null
  done
}

log_stat() { echo "[$(date '+%F %T')] $*" >> "${STATS_LOG:-/data/local/tmp/cosmem/stats.log}"; }
