#!/system/bin/sh
# 卸载: adj 全部还原 + 配置清理
MODDIR=$(dirname "$0")
. "$MODDIR/engine/exec.sh"
restore_state "$MODDIR/data/state" 2>/dev/null
rm -rf /sdcard/Android/COSMemory
rm -rf /data/system/cosmem 2>/dev/null
# 同步卸载防线组件 (无模块桥已无意义; LSPosed 记录随包卸载自动清理)
pm uninstall com.xune.cosguard >/dev/null 2>&1 && echo "- COSGuard 已同步卸载"
