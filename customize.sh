#!/system/bin/sh
# 安装期: 名单目录初始化 / 旧配置迁移 / 权限
OUTDIR="/sdcard/Android/COSMemory"
mkdir -p "$OUTDIR"
[ -f "$OUTDIR/名单列表.conf" ] || cp "$MODPATH/config/名单列表.conf" "$OUTDIR/"
[ -f "$MODPATH/config/memory.json" ] && [ ! -f "$OUTDIR/memory.json" ] \
  && cp "$MODPATH/config/memory.json" "$OUTDIR/"
[ "$ARCH" != "arm64" ] && abort "Not compatible with this platform: $ARCH"
set_perm_recursive "$MODPATH" 0 0 0755 0755
ui_print "- COSMemory 已安装. 名单: $OUTDIR/名单列表.conf"
