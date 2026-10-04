/** 诊断包生成: 单条桥命令把引擎/防线/设备信息导出为一个文本文件 (社区反馈用).
 *  隐私边界: 只含模块自身日志 + 系统型号属性 + 名单包名; logcat 仅 grep cosguard|cosmem.
 *  结构: OUT=...; { 语句; ...; } > "$OUT" 2>&1; echo "$OUT" — 语句用 "; " 连接,
 *  否则前一条 echo 会把下一段标题吞成参数 (v1.1.2 修复). */
export function buildDiagCmd(mod: string, list: string): string {
  const ts = "$(date +%Y%m%d-%H%M%S)"
  const out = `/sdcard/Download/COSMemory_diag_${ts}.txt`
  const body: string[] = [
    `echo "# COSMemory 诊断包"`,
    `echo "date: $(date '+%F %T')"`,
    `echo "==version=="`,
    `cat ${mod}/module.prop 2>/dev/null`,
    `echo "==device=="`,
    `getprop ro.product.model; getprop ro.product.brand; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.display.id; getprop ro.build.fingerprint; uname -a`,
    `echo "==memory=="`,
    `head -15 /proc/meminfo; cat /proc/pressure/memory 2>/dev/null`,
    `echo "==caps=="`,
    `cat ${mod}/data/caps.conf 2>/dev/null`,
    `echo "==engine=="`,
    `if pgrep -f engine/memory.sh >/dev/null; then echo state=running; else echo state=STOPPED; fi`,
    `echo "==stats_tail80=="`,
    `tail -80 ${mod}/data/stats.log 2>/dev/null`,
    `echo "==guard_3d=="`,
    `for f in $(ls ${mod}/data/guard/*.log 2>/dev/null | tail -3); do echo "--$f"; cat "$f"; done`,
    `echo "==kill_capture_tail60=="`,
    `tail -60 ${mod}/data/kill_capture.log 2>/dev/null`,
    `echo "==snapshot=="`,
    `cat ${mod}/data/parsed.txt 2>/dev/null`,
    `echo "==config=="`,
    `cat ${mod}/config/memory.json 2>/dev/null`,
    `echo "==list=="`,
    `cat "${list}" 2>/dev/null`,
    `echo "==bridge=="`,
    `ls -la /data/system/cosmem/ 2>/dev/null; cat /data/system/cosmem/guard.conf 2>/dev/null`,
    `echo "==cosguard_logcat=="`,
    `logcat -d 2>/dev/null | grep -iE "cosguard|cosmem" | tail -60`,
    `echo "==lsposed_guard_log=="`,
    `for f in $(ls -t /data/adb/lspd/log/modules_*.log 2>/dev/null | head -2); do echo "--$f"; grep -ihE "cosguard|killLocked|FREEZE|cosmem" "$f" 2>/dev/null | tail -40; done`,
  ]
  return `OUT="${out}"; { ${body.join('; ')}; } > "$OUT" 2>&1; echo "$OUT"`
}
