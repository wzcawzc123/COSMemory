#!/system/bin/sh
# 死因验证 v2: 时间戳对齐的杀-等-看
M=/data/adb/modules/COSMemory
# 找引擎(链式: 6938→6950→9956, 取含 memory.sh 的最深 pid)
EP=""
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in */COSMemory/engine/memory.sh*) EP=${d#/proc/};; esac
done
[ -z "$EP" ] && { echo "引擎不在!"; exit 1; }
STARTED=$(cat "$M/data/engine.started")
echo "[$(date '+%F %T')] 杀引擎 pid=$EP (started=$STARTED, 已活=$(( $(date +%s) - STARTED ))s)"
kill -9 "$EP"
# 每5秒记录: 时间戳 + 是否有新WATCHDOG + 引擎pid
for i in 1 2 3 4 5 6 7 8; do
  sleep 5
  WD=$(grep -c 'WATCHDOG restart prev_alive' "$M/data/stats.log")
  NE=""
  for d in /proc/[0-9]*; do
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    case "$c" in */COSMemory/engine/memory.sh*) NE=${d#/proc/};; esac
  done
  echo "[$(date '+%F %T')] t+$((i*5))s watchdog条数=$WD 引擎=${NE:-无}"
  [ "$WD" -ge 4 ] && break
done
echo "=== 最终死因记录 ==="
grep 'WATCHDOG restart prev_alive' "$M/data/stats.log" | tail -2
