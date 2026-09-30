#!/system/bin/sh
# engine/memory.sh — SLEEP→SNAPSHOT→SENTINEL→POLICY→EXEC→SLEEP
MODDIR=$(dirname "$0")/..
. "$MODDIR/engine/snapshot.sh"; . "$MODDIR/engine/lists.sh"
. "$MODDIR/engine/policy.sh";   . "$MODDIR/engine/exec.sh"
. "$MODDIR/engine/probe.sh"
. "$MODDIR/engine/attrib.sh"

WORKDIR="${WORKDIR:-$MODDIR/data}"
STATS_LOG="${STATS_LOG:-$WORKDIR/stats.log}"; export STATS_LOG
KEEPADJ_TARGET="${KEEPADJ_TARGET:-200}"; MAX_KILL="${MAX_KILL:-5}"
BRIDGE_PATH="${BRIDGE_PATH:-/data/system/cosmem/guard.conf}"
TELEM_PATH="${TELEM_PATH:-/data/system/cosmem/guard.telemetry}"
mkdir -p "$WORKDIR/cool"; date +%s > "$WORKDIR/engine.started"; cap_probe; . "$WORKDIR/caps.conf"
echo "[$(date '+%F %T')] START caps: $(tr '\n' ' ' < "$WORKDIR/caps.conf")" >> "$STATS_LOG"
[ "$CAP_LRU" = 1 ] || { echo "halt: no lru source" >> "$STATS_LOG"; exit 9; }

# FREEZE 存量杀+巡检 (spec §5, D1/D5): 桥行=执行门(桥即状态)
freeze_active() { # $1=桥路径 -> 1/0
  [ -f "$1" ] || { echo 0; return 0; }
  grep -q '^FREEZE_ENABLED=1' "$1" 2>/dev/null || { echo 0; return 0; }
  grep -q '^FREEZE ' "$1" 2>/dev/null && echo 1 || echo 0
}
freeze_reap() { # $1=桥路径; 其余=包名; 杀成功输出6字段行到 stdout
  br="$1"; shift
  [ "$(freeze_active "$br")" = "1" ] || return 0
  pkgs=$(grep '^FREEZE ' "$br" 2>/dev/null | awk '{print $2}')
  for p in "$@"; do
    echo "$pkgs" | grep -qx "$p" || continue
    for pid in $(pgrep -f "$p" 2>/dev/null); do
      am kill "$p" >/dev/null 2>&1
      echo "$(date +%s)|$pid|$p||FREEZE|engine reap"
      return 0
    done
  done
  return 0
}

last_full=0
while :; do
  rotate_stats
  now=$(date +%s)
  if [ $((now - last_full)) -ge 60 ]; then full=1; last_full=$now; else full=0; fi
  snapshot_collect
  eval "$(lru_stats "$WORKDIR/snapshot.txt")"
  if [ "$LRU_TOTAL" -gt 0 ]; then rate=$((LRU_PARSED*100/LRU_TOTAL)); else rate=0; fi
  if [ "$rate" -lt 50 ]; then   # 哨兵: 宁停不错
    echo "[$(date '+%F %T')] SENTINEL HALT rate=$rate" >> "$STATS_LOG"
    sleep 30; continue
  fi
  lru_parse "$WORKDIR/snapshot.txt" > "$WORKDIR/parsed.txt"   # 原始→解析流
  eval "$(parse_lists "${LIST_PATH:-/sdcard/Android/COSMemory/名单列表.conf}")"
  [ "${LIST_BAD:-0}" -gt 0 ] && echo "LIST_BAD=$LIST_BAD detail=$LIST_BAD_DETAIL" >> "$STATS_LOG"
  detect_death "$WORKDIR/parsed.txt" "$WHITE_LIST"
  plan_keepalive "$WORKDIR/parsed.txt" "$WHITE_LIST" "$KEEPADJ_TARGET" > "$WORKDIR/acts"
  plan_reclaim   "$WORKDIR/parsed.txt" "$KILL_LIST" "$WORKDIR/cool" "$MAX_KILL" "$WHITE_LIST" >> "$WORKDIR/acts"
  grep '^KILL ' "$WORKDIR/acts" | while read -r _ pid _; do date +%s > "$WORKDIR/cool/$pid"; done
  apply_actions "$WORKDIR/acts" "$WORKDIR/state" >> "$STATS_LOG"
  FRZ=$(freeze_reap "$BRIDGE_PATH" $FREEZE_LIST 2>/dev/null)
  [ -n "$FRZ" ] && echo "$FRZ" >> "$TELEM_PATH" 2>/dev/null
  [ "$full" = 1 ] && capture_kills "$WHITE_LIST"
  [ "$full" = 1 ] && sleep 8 || sleep 2
done
