#!/system/bin/sh
# service.sh — KSU/Magisk/Apatch 兼容入口 + 看门狗
MODDIR=$(dirname "$0")
BB=""
for c in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
  [ -x "$c" ] && { BB=$c; break; }
done
export STATS_LOG="$MODDIR/data/stats.log"; mkdir -p "$MODDIR/data"
[ -n "$BB" ] && export ASH_STANDALONE=1
run() { [ -n "$BB" ] && "$BB" ash "$@" || sh "$@"; }

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 3
while :; do
  if ! pgrep -f 'engine/memory.sh' >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] WATCHDOG restart" >> "$STATS_LOG"
    WORKDIR="$MODDIR/data" STATS_LOG="$STATS_LOG" run "$MODDIR/engine/memory.sh" >/dev/null 2>&1 &
  fi
  sleep 30
done
