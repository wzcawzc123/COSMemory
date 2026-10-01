#!/system/bin/sh
# 安装期: data 迁移(覆盖更新保历史) / 名单初始化 / 旧配置迁移 / COSGuard 自动安装 / 权限
OUTDIR="/sdcard/Android/COSMemory"

# 1) 运行时数据迁移 — KSU 更新是整目录替换, 旧模块目录在安装期仍可访问,
#    抢救 state(adj还原记录)/stats(统计历史)/guard(防线日志), 防止覆盖安装清零
OLDDATA="/data/adb/modules/COSMemory/data"
if [ -d "$OLDDATA" ] && [ ! -d "$MODPATH/data" ]; then
  cp -a "$OLDDATA" "$MODPATH/data" 2>/dev/null \
    && ui_print "- 已迁移运行时数据 (state/统计历史保留)"
fi

# 2) 名单目录初始化 / 旧配置迁移
mkdir -p "$OUTDIR"
[ -f "$OUTDIR/名单列表.conf" ] || cp "$MODPATH/config/名单列表.conf" "$OUTDIR/"
[ -f "$MODPATH/config/memory.json" ] && [ ! -f "$OUTDIR/memory.json" ] \
  && cp "$MODPATH/config/memory.json" "$OUTDIR/"

[ "$ARCH" != "arm64" ] && abort "Not compatible with this platform: $ARCH"
set_perm_recursive "$MODPATH" 0 0 0755 0755

# 3) COSGuard APK 自动安装 (防线组件) — 失败不阻断, 提示手动安装
APK=$(ls "$MODPATH"/assets/COSGuard-*.apk 2>/dev/null | head -1)
if [ -n "$APK" ]; then
  if pm install -r "$APK" >/dev/null 2>&1; then
    ui_print "- COSGuard 已自动安装. 请到 LSPosed 启用并勾选作用域「系统框架」"
  else
    ui_print "! COSGuard 自动安装失败, 请手动安装: 解压 assets/ 内 APK"
  fi
fi

ui_print "- COSMemory 已安装. 名单: $OUTDIR/名单列表.conf"
