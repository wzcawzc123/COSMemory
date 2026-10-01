#!/system/bin/sh
# 卸载: adj 全部还原 + 配置清理 + 防线组件联动
# 执行期=boot早期(post-fs-data): /sdcard(FUSE)未挂载、pm服务未起 — 见 v0.8.1 修复
MODDIR=$(dirname "$0")
. "$MODDIR/engine/exec.sh"
restore_state "$MODDIR/data/state" 2>/dev/null
# /sdcard 早期不可达 → 双路径删底层存储 (/data/media/0 即 sdcard 实体)
rm -rf /sdcard/Android/COSMemory /data/media/0/Android/COSMemory
rm -rf /data/system/cosmem 2>/dev/null
# pm 服务未起时后台脱离会话重试 (10s×12=2min 窗口, 覆盖 boot_completed)
/system/bin/setsid /system/bin/sh -c '
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    /system/bin/pm uninstall --user 0 com.xune.cosguard >/dev/null 2>&1 && exit 0
    /system/bin/sleep 10
  done
' </dev/null >/dev/null 2>&1 &
