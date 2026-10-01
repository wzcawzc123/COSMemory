#!/system/bin/sh
# test_listedit.sh — engine/listedit.sh (spec list-editor §4.2/§6)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MOD="$HERE/.."
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf "ok %d %s\n" "$PASS" "$1"; }
no(){ FAIL=$((FAIL+1)); printf "FAIL %s\n" "$1"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (want=[$3] got=[$2])"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/名单列表.conf"; MODDIR="$MOD"
BRIDGE_DIR="$TMP/bridge"; BRIDGE="$BRIDGE_DIR/guard.conf"
export LIST_PATH="$CONF" MODDIR BRIDGE_DIR BRIDGE
cat > "$CONF" <<'FIX'
# 出厂名单
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
FREEZE com.bad.app
}
FIX
le(){ sh "$MOD/engine/listedit.sh" "$@" 2>&1; }

eq "add-white-ok"        "$(le add WHITE com.new.app)" "OK"
awk '/^WHITE com.tencent.mobileqq$/{a=NR} /^WHITE com.new.app$/{b=NR} END{exit !(a&&b&&b==a+1)}' "$CONF" \
  && ok add-position || no add-position
cp "$CONF" "$TMP/bak"
eq "add-dup"             "$(le add WHITE com.new.app)" "ERR:dup"
cmp -s "$CONF" "$TMP/bak" && ok dup-unchanged || no dup-unchanged
eq "kill-no-suffix"      "$(le add KILL com.foo.app)" "ERR:badfmt"
eq "kill-with-suffix"    "$(le add KILL com.foo.app:push)" "OK"
grep -q "^KILL com.foo.app:push$" "$CONF" && ok kill-line || no kill-line
eq "freeze-with-group"   "$(le add FREEZE com.game:group-black)" "OK"
eq "d4-white-side"       "$(le add WHITE com.bad.app)" "ERR:conflict"
eq "d4-freeze-side"      "$(le add FREEZE com.tencent.mm)" "ERR:conflict"
eq "badfmt-space"        "$(le add WHITE 'bad pkg')" "ERR:badfmt"
eq "del-ok"              "$(le del WHITE com.new.app)" "OK"
grep -q "^WHITE com.new.app$" "$CONF" && no del-left || ok del-left
eq "del-miss"            "$(le del WHITE com.not.there)" "ERR:nomatch"
cp "$CONF" "$TMP/bak2"
le del WHITE com.other.miss >/dev/null
cmp -s "$CONF" "$TMP/bak2" && ok miss-unchanged || no miss-unchanged
head -1 "$CONF" | grep -q "^# 出厂名单$" && ok keep-comment || no keep-comment
grep -q "^{$" "$CONF" && ok keep-brace || no keep-brace
# parsefail: 绕过 validate 注入 awk 判 bad 的行 → 回滚
cp "$CONF" "$TMP/bak3"
out=$(LISTEDIT_SOURCED=1 sh -c '. "'"$MOD"'/engine/listedit.sh"; validate(){ :; }; do_add WHITE "1bad!"')
eq "parsefail"          "$out" "ERR:parsefail"
cmp -s "$CONF" "$TMP/bak3" && ok parsefail-rollback || no parsefail-rollback
# 存量坏行不连坐: bad 已存在, add 合法行仍 OK 且坏行保留
printf 'GARBAGE 123\n' >> "$CONF"
eq "keep-bad-ok"        "$(le add WHITE com.keep.app)" "OK"
grep -q "^GARBAGE 123$" "$CONF" && ok bad-kept || no bad-kept
# bridge 即时再生成: guard.conf 含新增行
grep -q "^WHITE com.keep.app$" "$BRIDGE" && ok bridge-regen || no bridge-regen
# guard_bridge 失败 → OK + WARN:bridge (conf 已落盘)
out=$(BRIDGE_DIR=/proc/self/eta_no BRIDGE=/proc/self/eta_no/g.conf \
      sh "$MOD/engine/listedit.sh" add WHITE com.warn.app 2>&1)
first=$(echo "$out" | head -1)
eq "bridge-fail-ok"     "$first" "OK"
echo "$out" | grep -q "WARN:bridge" && ok bridge-fail-warn || no bridge-fail-warn
grep -q "^WHITE com.warn.app$" "$CONF" && ok bridge-fail-committed || no bridge-fail-committed
# 行数上限 500
i=0; while [ $i -lt 600 ]; do echo "# x$i"; i=$((i+1)); done >> "$CONF"
eq "toomany"            "$(le add WHITE com.overflow.app)" "ERR:toomany"
grep -q "^WHITE com.overflow.app$" "$CONF" && no toomany-leak || ok toomany-leak

printf "# pass=%d fail=%d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
