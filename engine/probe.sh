#!/system/bin/sh
# engine/probe.sh — 启动时能力探测(不猜版本); 缺失→功能降级且可见
cap_probe() {
  mkdir -p "$WORKDIR"; C="$WORKDIR/caps.conf"; : > "$C"
  dumpsys activity lru 2>/dev/null | grep -q '^ *#[0-9]*:' \
    && echo "CAP_LRU=1" >> "$C" || echo "CAP_LRU=0" >> "$C"
  dumpsys activity processes 2>/dev/null | grep -qE 'ProcessRecord|APP ' \
    && echo "CAP_LRU_FALLBACK=1" >> "$C" || echo "CAP_LRU_FALLBACK=0" >> "$C"
  [ -r /proc/pressure/memory ] && echo "CAP_PSI=1" >> "$C" || echo "CAP_PSI=0" >> "$C"
  my=$$; b=$(cat /proc/$my/oom_score_adj); echo "$b" > /proc/$my/oom_score_adj 2>/dev/null
  [ "$(cat /proc/$my/oom_score_adj 2>/dev/null)" = "$b" ] \
    && echo "CAP_ADJ=1" >> "$C" || echo "CAP_ADJ=0" >> "$C"
  cmd device_config get lmkd_native thrashing_limit_critical >/dev/null 2>&1 \
    && echo "CAP_LMKD_CFG=1" >> "$C" || echo "CAP_LMKD_CFG=0" >> "$C"
  getprop persist.sys.lmk.oplus.kill_memleak_process | grep -q . \
    && echo "CAP_OPLUS=1" >> "$C" || echo "CAP_OPLUS=0" >> "$C"
}
