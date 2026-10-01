#!/system/bin/sh
# 卸载: adj 全部还原 + 配置清理 + 防线组件联动
# 执行期=boot极早期: /sdcard(FUSE)与 /data/media/0(CE存储待解锁)不可达, pm服务未起 (v0.8.1实测)
# → 全部清理挪入后台脱离会话的就绪窗口, 自行探测存储/解锁/pm, 全清即退 (10min上限)
MODDIR=$(dirname "$0")
. "$MODDIR/engine/exec.sh"
restore_state "$MODDIR/data/state" 2>/dev/null
rm -rf /data/system/cosmem 2>/dev/null          # 桥: 此刻/data可达, 先删
/system/bin/setsid /system/bin/sh -c '
  storage_ok=0; pm_ok=0; i=0
  while [ "$i" -lt 60 ]; do
    i=$((i+1))
    if [ "$storage_ok" = 0 ] && [ -d /data/media/0 ]; then
      rm -rf /sdcard/Android/COSMemory /data/media/0/Android/COSMemory 2>/dev/null
      [ ! -d /data/media/0/Android/COSMemory ] && storage_ok=1
    fi
    if [ "$pm_ok" = 0 ] && /system/bin/pm uninstall --user 0 com.xune.cosguard >/dev/null 2>&1; then
      pm_ok=1
      rm -rf /data/system/cosmem 2>/dev/null     # COSGuard已死, 补删其重建遗产
    fi
    [ "$storage_ok" = 1 ] && [ "$pm_ok" = 1 ] && exit 0
    /system/bin/sleep 10
  done
' </dev/null >/dev/null 2>&1 &
