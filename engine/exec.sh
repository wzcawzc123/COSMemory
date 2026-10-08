#!/system/bin/sh
# engine/exec.sh — 执行层(安全验证 + 回滚记录 + stats) v0.3
# v0.3: KEEPADJ带pid(区分进程换代) / FAILED分类(missing/mismatch/write) / SKIPPED计数(拦截可见化)

apply_actions() {
  # $1=动作行文件 $2=state目录
  # 输出: APPLIED=.. KILLED=.. FAILED=.. missing=.. mismatch=.. write=.. SKIPPED=..
  mkdir -p "$2" 2>/dev/null
  ap=0; ki=0; fa=0; fm=0; fx=0; fw=0; sk=0
  while read -r op a b c; do
    case "$op" in
    KEEPADJ)
      pid=$a; pkg=$b; tgt=$c
      [ -d "/proc/$pid" ] || { fa=$((fa+1)); fm=$((fm+1)); continue; }
      cur=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
      case "$cur" in (*"$pkg"*) ;; (*) fa=$((fa+1)); fx=$((fx+1)); continue;; esac
      before=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
      [ "$before" = "$tgt" ] && continue
      # v1.2.0 只降不抬: 当前 adj 已不高于目标(已更受保护) → 跳过,
      # 防止 prev/svc/svcb 扩覆盖后把绑定前台的低 adj 进程反向抬高成可杀水位
      case "$before" in
        ''|*[!0-9-]*) : ;;
        *) [ "$before" -le "$tgt" ] 2>/dev/null && continue ;;
      esac
      [ -f "$2/adj_$pid" ] || echo "orig=$before pkg=$pkg" > "$2/adj_$pid"
      if ! echo "$tgt" > /proc/$pid/oom_score_adj 2>/dev/null; then
        fa=$((fa+1)); fw=$((fw+1)); continue
      fi
      after=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
      if [ "$after" = "$tgt" ]; then
        ap=$((ap+1)); log_stat "KEEPADJ $pid $pkg $before->$tgt"
      else
        fa=$((fa+1)); fw=$((fw+1))
      fi
      ;;
    KILL|RECLAIM)
      pid=$a; pkg=$b
      [ -d "/proc/$pid" ] || { fa=$((fa+1)); fm=$((fm+1)); continue; }
      cur=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
      case "$cur" in (*"$pkg"*) ;; (*) fa=$((fa+1)); fx=$((fx+1)); continue;; esac
      if kill -9 "$pid" 2>/dev/null; then ki=$((ki+1)); log_stat "$op $pid $pkg"
      else fa=$((fa+1)); fw=$((fw+1)); fi
      ;;
    SKIP)
      sk=$((sk+1)) ;;
    '#'*|'') : ;;
    *) fa=$((fa+1)); fw=$((fw+1)) ;;
    esac
  done < "$1"
  echo "APPLIED=$ap KILLED=$ki FAILED=$fa missing=$fm mismatch=$fx write=$fw SKIPPED=$sk"
}

restore_state() {
  for f in "$1"/adj_*; do
    [ -f "$f" ] || continue
    orig=$(sed -n "s/^orig=//p" "$f" | cut -d" " -f1); pid=${f##*adj_}
    [ -n "$orig" ] && [ -d "/proc/$pid" ] && echo "$orig" > /proc/$pid/oom_score_adj 2>/dev/null
  done
}

log_stat() { echo "[$(date '+%F %T')] $*" >> "${STATS_LOG:-/data/local/tmp/cosmem/stats.log}"; }
