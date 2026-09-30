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
t_done
