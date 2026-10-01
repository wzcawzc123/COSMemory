#!\/system\/bin\/sh
# T1 工程级: 桥生成的输入→输出契约 (不依赖 /data/system, 用临时目录)
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/lists.sh"
TMP=$(mktemp -d)
MOD="$TMP/mod"; mkdir -p "$MOD/config"
cp "$D/../config/名单列表.conf" "$MOD/config/" 2>/dev/null || {
  printf '{\nWHITE com.tencent.mm\nWHITE com.tencent.mobileqq\nWHITE com.ss.android.ugc.aweme\n}\n' \
    > "$MOD/config/名单列表.conf"; }
printf '{\n  "guard": { "mode": "observe", "block_rules": "o-stop,frozen,cached,empty,cpu" }\n}\n' \
  > "$MOD/config/memory.json"

# 提取逻辑与 service.sh guard_bridge 内联版逐字一致
jc="$MOD/config/memory.json"
mode=$(sed -n 's/.*"mode" *: *"\([^"]*\)".*/\1/p' "$jc" | head -1)   # guard 是 memory.json 唯一 mode 键
block=$(sed -n 's/.*"block_rules" *: *"\([^"]*\)".*/\1/p' "$jc" | head -1)
[ "$mode" = guard ] || mode=observe
[ -n "$block" ] || block=o-stop,frozen,cached,empty,cpu
eval "$(parse_lists "$MOD/config/名单列表.conf")"
B="$TMP/guard.conf"
{ echo "VERSION=1"; echo "MODE=$mode"; echo "BLOCK=$block"
  for p in $WHITE_LIST; do echo "WHITE $p"; done; } > "$B"

t_assert "MODE 提取" "observe" "$mode"
t_assert "BLOCK 提取(含逗号完整)" "o-stop,frozen,cached,empty,cpu" "$block"
t_match  "含微信" "com.tencent.mm" "$(cat $B)"
t_match  "含抖音" "com.ss.android.ugc.aweme" "$(cat $B)"
t_assert "WHITE 行数=3" "3" "$(grep -c '^WHITE ' $B)"
t_assert "VERSION 行" "VERSION=1" "$(head -1 $B)"

# guard 模式切换
printf '{\n  "guard": { "mode": "guard", "block_rules": "o-stop" }\n}\n' > "$jc"
mode=$(sed -n 's/.*"mode" *: *"\([^"]*\)".*/\1/p' "$jc" | head -1)   # guard 是 memory.json 唯一 mode 键
t_assert "改 guard 后提取" "guard" "$mode"

# 缺 guard 节 → 回落 observe 默认
printf '{\n  "keepAlive": { "adj": 200 }\n}\n' > "$jc"
mode=$(sed -n 's/.*"mode" *: *"\([^"]*\)".*/\1/p' "$jc" | head -1)   # guard 是 memory.json 唯一 mode 键
[ "$mode" = guard ] || mode=observe
t_assert "缺节回落 observe" "observe" "$mode"

# FREEZE 桥行 (spec §4.2 桥即状态) — 片段 source 真调 service.sh guard_bridge
mkdir -p "$TMP/gb"; sed -n '/^guard_bridge()/,/^}/p' "$D/../service.sh" > "$TMP/gb/g.sh"
MODDIR="$MOD"; BRIDGE_DIR="$TMP/gb"; BRIDGE="$TMP/gb/guard.conf"
. "$TMP/gb/g.sh"
LIST_PATH="$MOD/config/名单列表.conf"   # 桥读sdcard权威路径(2f9eb0d), 测试经LIST_PATH注入fixture
printf '{\n  "freeze": { "enabled": true }\n}\n' > "$jc"
printf '{\nWHITE com.tencent.mm\nFREEZE com.example.fz\n}\n' > "$MOD/config/名单列表.conf"
guard_bridge
t_assert "开: FREEZE_ENABLED=1" "1" "$(grep -c '^FREEZE_ENABLED=1$' $BRIDGE)"
t_assert "开: FREEZE行" "FREEZE com.example.fz" "$(grep '^FREEZE ' $BRIDGE)"
printf '{\n  "freeze": { "enabled": false }\n}\n' > "$jc"
guard_bridge
t_assert "关: 零FREEZE行" "0" "$(grep -c '^FREEZE' $BRIDGE)"
t_assert "关: 无ENABLED键" "0" "$(grep -c FREEZE_ENABLED $BRIDGE)"
printf '{\n  "guard": { "mode": "observe" }\n}\n' > "$jc"
guard_bridge
t_assert "缺freeze节=零行" "0" "$(grep -c '^FREEZE' $BRIDGE)"

rm -rf "$TMP"; t_done
