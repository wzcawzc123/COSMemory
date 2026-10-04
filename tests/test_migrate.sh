#!/system/bin/sh
# test_migrate.sh — engine/listmigrate.sh 名单对齐 (覆盖安装丢名单回归)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MOD="$HERE/.."
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf "ok %d %s\n" "$PASS" "$1"; }
no(){ FAIL=$((FAIL+1)); printf "FAIL %s\n" "$1"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (want=[$3] got=[$2])"; }
nline(){ grep -cE '^[[:space:]]*(WHITE|KILL|FREEZE)[[:space:]]+' "$1" 2>/dev/null; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

FACTORY="$TMP/factory.conf"
cat > "$FACTORY" <<'FIX'
# 出厂名单
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
WHITE com.ss.android.ugc.aweme
}
FIX

# 环境注入
run(){ # $1=A $2=B ; 剩余为期望RESYNC
  A="$1"; B="$2"
  LIST_PATH="$A" LIST_BAK="$B" LIST_FRESH="$FACTORY" MODDIR="$TMP" \
    sh "$MOD/engine/listmigrate.sh"
}

# --- 场景1: 安装期被出厂覆盖 → 从备份恢复用户条目 (本案核心) ---
rm -rf "$TMP/s1"; mkdir -p "$TMP/s1"
cp "$FACTORY" "$TMP/s1/A"                          # 被覆盖成出厂(丢用户条目)
cat > "$TMP/s1/B" <<'BAK'                          # 备份仍有用户4条
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
WHITE com.ss.android.ugc.aweme
WHITE com.user.added
KILL com.adware:svc
FREEZE com.bloat.app
}
BAK
eq "s1-resync"    "$(run "$TMP/s1/A" "$TMP/s1/B")" "RESYNC=recovered"
eq "s1-restored"  "$(nline "$TMP/s1/A")" "6"
grep -q "^WHITE com.user.added$" "$TMP/s1/A" && ok s1-user-entry || no s1-user-entry
grep -q "^FREEZE com.bloat.app$" "$TMP/s1/A" && ok s1-freeze-entry || no s1-freeze-entry

# --- 场景2: 用户态名单(非出厂) → 刷新备份, 不改动用户名单 ---
rm -rf "$TMP/s2"; mkdir -p "$TMP/s2"
cat > "$TMP/s2/A" <<'A2'
{
WHITE com.tencent.mm
WHITE com.user.kept
}
A2
printf 'stale\n' > "$TMP/s2/B"
eq "s2-resync"   "$(run "$TMP/s2/A" "$TMP/s2/B")" "RESYNC=bak_updated"
grep -q "^WHITE com.user.kept$" "$TMP/s2/A" && ok s2-a-unchanged || no s2-a-unchanged
grep -q "^WHITE com.user.kept$" "$TMP/s2/B" && ok s2-b-synced || no s2-b-synced

# --- 场景3: 名单文件被删 → 从备份恢复 ---
rm -rf "$TMP/s3"; mkdir -p "$TMP/s3"
cp "$TMP/s1/B" "$TMP/s3/B"
eq "s3-resync"  "$(run "$TMP/s3/A" "$TMP/s3/B")" "RESYNC=deleted_restored"
eq "s3-count"   "$(nline "$TMP/s3/A")" "6"

# --- 场景4: 全新安装(无名单无备份) → 出厂并建备份 ---
rm -rf "$TMP/s4"; mkdir -p "$TMP/s4"
eq "s4-resync"  "$(run "$TMP/s4/A" "$TMP/s4/B")" "RESYNC=fresh"
cmp -s "$TMP/s4/A" "$FACTORY" && ok s4-factory || no s4-factory
cmp -s "$TMP/s4/B" "$FACTORY" && ok s4-bak-created || no s4-bak-created

# --- 场景5: 无备份且名单=出厂 → noop (不误判) ---
rm -rf "$TMP/s5"; mkdir -p "$TMP/s5"
cp "$FACTORY" "$TMP/s5/A"; cp "$FACTORY" "$TMP/s5/B"
eq "s5-resync"  "$(run "$TMP/s5/A" "$TMP/s5/B")" "RESYNC=noop"
eq "s5-count"   "$(nline "$TMP/s5/A")" "3"

# --- 场景6: 首次升级(用户态名单但无备份) → 建备份 ---
rm -rf "$TMP/s6"; mkdir -p "$TMP/s6"
cat > "$TMP/s6/A" <<'A6'
{
WHITE com.tencent.mm
WHITE com.user.only
}
A6
eq "s6-resync"  "$(run "$TMP/s6/A" "$TMP/s6/B")" "RESYNC=bak_created"
grep -q "^WHITE com.user.only$" "$TMP/s6/B" && ok s6-bak-has-user || no s6-bak-has-user

# --- 场景7: 三源全缺 → ERR:no_source (注入不存在的出厂名单) ---
rm -rf "$TMP/s7"; mkdir -p "$TMP/s7"
eq "s7-resync"  "$(LIST_PATH="$TMP/s7/A" LIST_BAK="$TMP/s7/B" LIST_FRESH="$TMP/s7/nope.conf" MODDIR="$TMP" sh "$MOD/engine/listmigrate.sh")" "ERR:no_source"

# --- 场景8: listedit 编辑后自动刷新备份 (写入层联动) ---
rm -rf "$TMP/s8"; mkdir -p "$TMP/s8"
cp "$FACTORY" "$TMP/s8/A"
export LIST_PATH="$TMP/s8/A" MODDIR="$MOD" BRIDGE_DIR="$TMP/s8/br" BRIDGE="$TMP/s8/br/guard.conf"
export LIST_BAK="$TMP/s8/B"
r=$(sh "$MOD/engine/listedit.sh" add WHITE com.panel.added 2>&1)
eq "s8-edit" "$r" "OK"
grep -q "^WHITE com.panel.added$" "$TMP/s8/B" && ok s8-bak-synced || no s8-bak-synced
# 模拟覆盖事故: 名单被打回出厂, 跑对齐应恢复
cp "$FACTORY" "$TMP/s8/A"
unset LIST_BAK
LIST_PATH="$TMP/s8/A" LIST_BAK="$TMP/s8/B" LIST_FRESH="$FACTORY" MODDIR="$TMP" \
  sh "$MOD/engine/listmigrate.sh" > /dev/null
grep -q "^WHITE com.panel.added$" "$TMP/s8/A" && ok s8-accident-recovered || no s8-accident-recovered
unset LIST_PATH MODDIR BRIDGE_DIR BRIDGE

echo "--- pass=$PASS fail=$FAIL ---"
exit $FAIL
