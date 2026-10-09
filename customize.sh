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

# 1.5) 用户配置迁移 — 覆盖更新保留拦截模式/激进回收/阈值偏好 (出厂默认仅全新安装生效)
OLDCFG="/data/adb/modules/COSMemory/config/memory.json"
if [ -f "$OLDCFG" ] && [ -f "$MODPATH/config/memory.json" ]; then
  cp "$OLDCFG" "$MODPATH/config/memory.json" 2>/dev/null \
    && ui_print "- 已保留用户配置 (拦截模式/激进回收/阈值)"
fi

# 2) 名单对齐 (listmigrate) — 取代旧 "[ -f ] || cp": 该判断在安装期 /sdcard 可见性异常时
#    会误判名单不存在 → cp 出厂名单覆盖用户条目 (真机丢名单事故根因)。
#    现改为: 用户名单在 → 与 data/list.bak 双向对齐; 名单缺 → 从备份恢复; 全新装 → 出厂。
mkdir -p "$OUTDIR"
LIST_PATH="$OUTDIR/名单列表.conf" \
LIST_BAK="$MODPATH/data/list.bak" \
LIST_FRESH="$MODPATH/config/名单列表.conf" \
MODDIR="$MODPATH" \
  sh "$MODPATH/engine/listmigrate.sh" > "$MODPATH/data/.listresync" 2>&1
ui_print "- 名单对齐: $(sed -n 's/^RESYNC=//p' "$MODPATH/data/.listresync" 2>/dev/null || echo noop)"
[ -f "$MODPATH/config/memory.json" ] && [ ! -f "$OUTDIR/memory.json" ] \
  && cp "$MODPATH/config/memory.json" "$OUTDIR/"

[ "$ARCH" != "arm64" ] && abort "Not compatible with this platform: $ARCH"
set_perm_recursive "$MODPATH" 0 0 0755 0755

# 3) COSGuard APK 自动安装 (防线组件) — 失败不阻断, 提示手动安装
#    v1.2.1: 路径优先规范位 lsp/<模块名>-<版本>.apk, 兼容历史 assets/ 布局; 遍历全部
APK_FOUND=""
for APK in $(ls "$MODPATH"/lsp/COSGuard*.apk "$MODPATH"/assets/COSGuard-*.apk 2>/dev/null); do
  if pm install -r "$APK" > /dev/null 2>&1; then
    APK_FOUND=1
    ui_print "- COSGuard 已自动安装: $(basename "$APK")"
  else
    ui_print "! COSGuard 自动安装失败(可能已装同/高版本): $(basename "$APK")"
  fi
done
[ -n "$APK_FOUND" ] \
  && ui_print "- 请到 LSPosed 启用本模块并按 README 勾选作用域" \
  || ui_print "! 未找到 COSGuard APK, 防线拦截不生效, 请手动安装 zip 内 lsp/ 的 APK"

ui_print "- COSMemory 已安装. 名单: $OUTDIR/名单列表.conf"
