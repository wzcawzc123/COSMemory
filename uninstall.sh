#!/system/bin/sh
# 卸载: adj 全部还原 + 配置清理
MODDIR=$(dirname "$0")
. "$MODDIR/engine/exec.sh"
restore_state "$MODDIR/data/state" 2>/dev/null
rm -rf /sdcard/Android/COSMemory
rm -rf /data/system/cosmem 2>/dev/null
