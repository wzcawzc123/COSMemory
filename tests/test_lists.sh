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
# ===== load_lists 容错 (2026-10-05 no-white 修复) =====
. "$D/../engine/lists.sh"
TMP2=$(mktemp -d)
# 1) 文件不存在 → 返回1, 且不污染既有变量
WHITE_LIST="com.keep.me"
if load_lists "$TMP2/nonexistent.conf"; then r=0; else r=1; fi
t_assert "缺失文件返回失败" "1" "$r"
t_assert "缺失文件不污染旧变量" "com.keep.me" "$WHITE_LIST"
# 2) 目录当文件 → 返回1
if load_lists "$TMP2"; then r=0; else r=1; fi
t_assert "不可读路径返回失败" "1" "$r"
# 3) 正常文件 → 返回0 且解析到位
printf '{\nWHITE com.tencent.mm\nKILL com.heytap.htms:cloudctrl\n}\n' > "$TMP2/ok.conf"
if load_lists "$TMP2/ok.conf"; then r=0; else r=1; fi
t_assert "正常文件返回成功" "0" "$r"
t_assert "正常文件解析WHITE" "com.tencent.mm" "$WHITE_LIST"
t_assert "正常文件解析KILL" "com.heytap.htms:cloudctrl" "$KILL_LIST"
rm -rf "$TMP2"


t_done