#!\/system\/bin\/sh
# FREEZE 冲突校验 + 解析边界 (spec D4)
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/lists.sh"
mkdir -p /tmp/tf
cat > /tmp/tf/list.conf << 'CONF'
{
WHITE com.tencent.mm
WHITE com.example.shared
FREEZE com.example.shared
FREEZE com.example.only
KILL com.tencent.mm:push
}
CONF
eval "$(parse_lists /tmp/tf/list.conf)"
t_assert "白名单保留不冲突项" "com.tencent.mm" "$WHITE_LIST"
case " $WHITE_LIST " in *" com.example.shared "*) t_assert "冲突包移出白名单" "absent" "present";; *) t_assert "冲突包移出白名单" "absent" "absent";; esac
case " $FREEZE_LIST " in *" com.example.shared "*) t_assert "冲突包移出FREEZE" "absent" "present";; *) t_assert "冲突包移出FREEZE" "absent" "absent";; esac
t_assert "非冲突FREEZE保留" "com.example.only" "$FREEZE_LIST"
t_assert "冲突计入LIST_BAD" "1" "$LIST_BAD"
t_match  "detail含conflict" "conflict:com.example.shared" "$LIST_BAD_DETAIL"
# 引擎巡检门控与存量杀 (spec §5/D1/D5)
sed -n '/^freeze_active()/,/^}/p; /^freeze_reap()/,/^}/p' "$D/../engine/memory.sh" > /tmp/tf/fn.sh
. /tmp/tf/fn.sh
BR=/tmp/tf/guard.conf
printf 'VERSION=1\nMODE=observe\nFREEZE_ENABLED=1\nFREEZE com.example.fz\n' > $BR
t_assert "门: 桥开+有行" "1" "$(freeze_active $BR)"
printf 'VERSION=1\nMODE=observe\nFREEZE com.example.fz\n' > $BR
t_assert "门: 无ENABLED=0" "0" "$(freeze_active $BR)"
printf 'VERSION=1\nMODE=observe\nFREEZE_ENABLED=1\n' > $BR
t_assert "门: 有ENABLED无行=0" "0" "$(freeze_active $BR)"
printf 'VERSION=1\nFREEZE_ENABLED=1\nFREEZE com.example.fz\n' > $BR
t_assert "不存在包零输出" "" "$(freeze_reap $BR com.example.never.exists)"
pgrep() { echo 12345; }   # 函数shadow: 兼容busybox ash applet优先(设备)与dash(本地)
am() { :; }
OUT=$(freeze_reap $BR com.example.fz)
t_match "杀成功行格式" "12345|com.example.fz||FREEZE|engine reap" "$OUT"
# 同包重复条目去重(桥单行)
cat > /tmp/tf/dup.conf << 'CONF'
{
WHITE com.a
FREEZE com.dup
FREEZE com.dup
FREEZE com.other
}
CONF
eval "$(parse_lists /tmp/tf/dup.conf)"
t_assert "FREEZE去重=单值" "com.dup com.other" "$FREEZE_LIST"
t_done
