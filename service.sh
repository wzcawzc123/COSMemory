#!/system/bin/sh
# service.sh — KSU/Magisk/Apatch 兼容入口 + 看门狗 v0.3(死因记录)
MODDIR=$(dirname "$0")
BB=""
for c in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
  [ -x "$c" ] && { BB=$c; break; }
done
export STATS_LOG="$MODDIR/data/stats.log"; mkdir -p "$MODDIR/data"
[ -n "$BB" ] && export ASH_STANDALONE=1
run() { [ -n "$BB" ] && "$BB" ash "$@" || sh "$@"; }

# --- COSGuard bridge (stage2): 配置桥入 + 遥测桥出 ---
. "$MODDIR/engine/lists.sh" 2>/dev/null || true
BRIDGE_DIR=/data/system/cosmem
BRIDGE=$BRIDGE_DIR/guard.conf
TELEM=$BRIDGE_DIR/guard.telemetry

. "$MODDIR/engine/bridge.sh" 2>/dev/null || true

guard_harvest() {
  [ -f "$TELEM" ] || return 0
  mkdir -p "$MODDIR/data/guard" 2>/dev/null || return 0
  cat "$TELEM" >> "$MODDIR/data/guard/$(date +%F).log" 2>/dev/null && : > "$TELEM"
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 3

# 名单开机对齐 (兜底): 安装期未救回的丢失在此恢复; 正常态为 noop/bak_updated
LIST_PATH="${LIST_PATH:-/sdcard/Android/COSMemory/名单列表.conf}" \
LIST_BAK="$MODDIR/data/list.bak" \
LIST_FRESH="$MODDIR/config/名单列表.conf" \
MODDIR="$MODDIR" \
  sh "$MODDIR/engine/listmigrate.sh" > "$MODDIR/data/.listresync" 2>&1 || \
  echo "[$(date '+%F %T')] LISTRESYNC fail $(cat "$MODDIR/data/.listresync" 2>/dev/null)" >> "$STATS_LOG"
grep -q . "$MODDIR/data/.listresync" 2>/dev/null && \
  echo "[$(date '+%F %T')] LISTRESYNC $(cat "$MODDIR/data/.listresync")" >> "$STATS_LOG"

while :; do
  if ! pgrep -f 'engine/memory.sh' >/dev/null 2>&1; then
    PA=unknown
    if [ -f "$MODDIR/data/engine.started" ]; then
      ST=$(cat "$MODDIR/data/engine.started" 2>/dev/null)
      [ -n "$ST" ] && PA="$(( $(date +%s) - ST ))s"
      rm -f "$MODDIR/data/engine.started"
    fi
    echo "[$(date '+%F %T')] WATCHDOG restart prev_alive=$PA" >> "$STATS_LOG"
    WORKDIR="$MODDIR/data" STATS_LOG="$STATS_LOG" run "$MODDIR/engine/memory.sh" >/dev/null 2>&1 &
  fi
  guard_bridge
  guard_harvest
  sleep 30
done
