#!/system/bin/sh
# 安装期: 名单目录初始化 / 旧配置迁移 / 权限
OUTDIR="/sdcard/Android/COSMemory"
mkdir -p "$OUTDIR"
[ -f "$OUTDIR/名单列表.conf" ] || cp "$MODPATH/config/名单列表.conf" "$OUTDIR/"
[ -f "$MODPATH/config/memory.json" ] && [ ! -f "$OUTDIR/memory.json" ] \
  && cp "$MODPATH/config/memory.json" "$OUTDIR/"
[ "$ARCH" != "arm64" ] && abort "Not compatible with this platform: $ARCH"
set_perm_recursive "$MODPATH" 0 0 0755 0755
# COSGuard 自动安装 (LSPosed 启用仍需用户手动勾选+重启)
APK=$(ls "$MODPATH"/assets/COSGuard*.apk 2>/dev/null | head -1)
if [ -n "$APK" ]; then
  if pm install -r "$APK" >/dev/null 2>&1; then
    ui_print "- COSGuard 已装入. 请到 LSPosed 启用并重启生效"
  else
    ui_print "! COSGuard 自动安装失败, 请手动装: assets/ 下 APK"
  fi
fi
ui_print "- COSMemory 已安装. 名单: $OUTDIR/名单列表.conf"
