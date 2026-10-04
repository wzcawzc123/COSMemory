#!/system/bin/sh
# engine/listmigrate.sh — 名单对齐 (备份/恢复)
# 防覆盖安装/卸载重装把用户新增的 WHITE/KILL/FREEZE 条目冲成出厂名单。
#
# 备份源: 模块 data/list.bak — 随 customize.sh 迁移到新模块目录, 不受模块整目录替换影响。
# 对齐规则 (A=用户名单, B=备份, F=出厂名单):
#   A在 B在: A==F 且 B 条目更多 → A=B   (安装期被出厂覆盖的事故恢复)
#            否则              → B=A   (用户态为准, 刷新备份)
#   A缺 B在: A=B                (名单文件被删, 从备份恢复)
#   A缺 B缺: A=F, B=A            (全新安装, 用出厂并建备份)
# 判据用 "A 是否等于出厂 F" 区分事故与用户主动删除, 避免把用户主动删的条目加回来。
#
# 环境变量 (全部可注入, 测试用):
#   LIST_PATH   用户名单   默认 /sdcard/Android/COSMemory/名单列表.conf
#   LIST_BAK    名单备份   默认 <模块>/data/list.bak
#   LIST_FRESH  出厂名单   默认 <模块>/config/名单列表.conf
# 输出: RESYNC=<recovered|deleted_restored|bak_updated|bak_created|fresh|noop>
# 退出: 0=已对齐  1=无可用来源

A="${LIST_PATH:-/sdcard/Android/COSMemory/名单列表.conf}"
MODDIR="${MODDIR:-/data/adb/modules/COSMemory}"
B="${LIST_BAK:-$MODDIR/data/list.bak}"
F="${LIST_FRESH:-$MODDIR/config/名单列表.conf}"

count() { grep -cE '^[[:space:]]*(WHITE|KILL|FREEZE)[[:space:]]+' "$1" 2>/dev/null; }

mkdir -p "$(dirname "$B")" 2>/dev/null
mkdir -p "$(dirname "$A")" 2>/dev/null

if [ -f "$A" ]; then
  if [ -f "$B" ]; then
    if cmp -s "$A" "$F" 2>/dev/null; then
      # 名单 = 出厂 (疑似被安装期覆盖), 备份有用户条目则恢复
      ca=$(count "$A"); cb=$(count "$B")
      if [ "${cb:-0}" -gt "${ca:-0}" ]; then
        cp "$B" "$A" && { echo "RESYNC=recovered"; exit 0; }
        echo "ERR:copy"; exit 1
      fi
      cp "$A" "$B" 2>/dev/null; echo "RESYNC=noop"; exit 0
    fi
    # 用户态名单 (非出厂) → 刷新备份
    cp "$A" "$B" 2>/dev/null && { echo "RESYNC=bak_updated"; exit 0; }
    echo "ERR:copy"; exit 1
  fi
  # 无备份 → 首次建立
  cp "$A" "$B" 2>/dev/null && { echo "RESYNC=bak_created"; exit 0; }
  echo "ERR:copy"; exit 1
fi

# A 缺失
if [ -f "$B" ]; then
  cp "$B" "$A" && { echo "RESYNC=deleted_restored"; exit 0; }
  echo "ERR:copy"; exit 1
fi
if [ -f "$F" ]; then
  cp "$F" "$A" || { echo "ERR:copy"; exit 1; }
  cp "$A" "$B" 2>/dev/null
  echo "RESYNC=fresh"; exit 0
fi
echo "ERR:no_source"; exit 1
