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
mkdir -p "$WORKDIR/cool"; date +%s > "$WORKDIR/engine.started"; cap_probe; . "$WORKDIR/caps.conf"
echo "[$(date '+%F %T')] START caps: $(tr '\n' ' ' < "$WORKDIR/caps.conf")" >> "$STATS_LOG"
[ "$CAP_LRU" = 1 ] || { echo "halt: no lru source" >> "$STATS_LOG"; exit 9; }

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
  [ "$full" = 1 ] && capture_kills "$WHITE_LIST"
  [ "$full" = 1 ] && sleep 8 || sleep 2
done
