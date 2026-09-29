#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/policy.sh"

cat > /tmp/tp_snap << 'SNAP'
cch|SVC|15942|com.tencent.mm
cch+5|SVC|9751|com.tencent.mobileqq
fg|TOP|6213|com.ss.android.ugc.aweme
vis|BFGS|5610|com.android.launcher
svc|SVC|17111|com.tencent.mm:push
cch|CAC|16879|com.coolapk.market
SNAP

OUT=$(plan_keepalive /tmp/tp_snap "com.tencent.mm com.coolapk.market" 200)
t_assert "保活2个" "KEEPADJ 15942 com.tencent.mm 200
KEEPADJ 16879 com.coolapk.market 200" "$OUT"
t_assert "前台不保活" "" "$(plan_keepalive /tmp/tp_snap "com.ss.android.ugc.aweme" 200)"

rm -rf /tmp/tp_cool
OUT=$(plan_reclaim /tmp/tp_snap "com.tencent.mm:push" /tmp/tp_cool 5 "")
t_assert "KILL命中" "KILL 17111 com.tencent.mm:push" "$OUT"
t_assert "白名单进程不被KILL" "SKIP whitelist com.tencent.mm" "$(plan_reclaim /tmp/tp_snap "com.tencent.mm" /tmp/tp_cool 5 "com.tencent.mm")"

mkdir -p /tmp/tp_cool; date +%s > /tmp/tp_cool/17111
OUT=$(plan_reclaim /tmp/tp_snap "com.tencent.mm:push" /tmp/tp_cool 5 "")
t_match "冷却跳过" "SKIP cooldown com.tencent.mm:push" "$OUT"
rm -rf /tmp/tp_cool

cat > /tmp/tp_snap2 << 'SNAP2'
cch|CAC|111|a.x:p1
cch|CAC|222|a.x:p2
cch|CAC|333|a.x:p3
SNAP2
OUT=$(plan_reclaim /tmp/tp_snap2 "a.x:p1 a.x:p2 a.x:p3" /tmp/tp_none 2 "")
t_assert "上限生效" "KILL 111 a.x:p1
KILL 222 a.x:p2
SKIP cap a.x:p3" "$OUT"
t_done
