#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/lists.sh"
cat > /tmp/tl.conf << 'CONF'
# 注释行
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
KILL com.tencent.mm:toolsmp
FREEZE com.bloat.app
bad_line_without_action
WHITE
KILL com.a:b
}
CONF
eval "$(parse_lists /tmp/tl.conf)"
t_assert "白名单2个" "com.tencent.mm com.tencent.mobileqq" "$WHITE_LIST"
t_assert "KILL带子进程(含com.a:b, 合法)" "com.tencent.mm:toolsmp com.a:b" "$KILL_LIST"
t_assert "FREEZE" "com.bloat.app" "$FREEZE_LIST"
t_assert "非法行计数=2" "2" "$LIST_BAD"
eval "$(parse_lists "$D/../config/名单列表.conf")"
t_assert "出厂名单零非法行" "0" "$LIST_BAD"
t_match "出厂含微信白名单" "com.tencent.mm" "$WHITE_LIST"
t_done
