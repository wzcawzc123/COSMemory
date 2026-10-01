#!\/system\/bin\/sh
# 激进回收: 触发判定(注入) + 档位匹配 + plan_aggressive 决策
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/policy.sh"
T=/tmp/tr; rm -rf $T; mkdir -p $T
printf 'some avg10=8.50 avg60=4.20\nfull avg10=1.10\n' > $T/psi
printf 'MemAvailable:  500000 kB\n' > $T/mem
printf 'some avg10=2.00 avg60=1.00\n' > $T/psi_low
printf 'MemAvailable:  4000000 kB\n' > $T/mem_high
# reclaim_should_fire now agg psi_t floor cool cap_psi psi_file mem_file last_file -> 1/0
t_assert "双条件满足=1"   "1" "$(reclaim_should_fire 1000 1 5 1024 60 1 $T/psi $T/mem $T/last)"
t_assert "PSI低=0"        "0" "$(reclaim_should_fire 1000 1 5 1024 60 1 $T/psi_low $T/mem $T/last)"
t_assert "水位高=0"       "0" "$(reclaim_should_fire 1000 1 5 1024 60 1 $T/psi $T/mem_high $T/last)"
t_assert "降级无PSI只看水位" "1" "$(reclaim_should_fire 1000 1 5 1024 60 0 $T/psi_low $T/mem $T/last)"
t_assert "总闸关=0"       "0" "$(reclaim_should_fire 1000 0 5 1024 60 1 $T/psi $T/mem $T/last)"
echo 990 > $T/last
t_assert "冷却期内=0"     "0" "$(reclaim_should_fire 1000 1 5 1024 60 1 $T/psi $T/mem $T/last)"
echo 800 > $T/last
t_assert "冷却过期=1"     "1" "$(reclaim_should_fire 1000 1 5 1024 60 1 $T/psi $T/mem $T/last)"
# depth_match 档位
t_assert "cached命中cch"   "1" "$(depth_match 'cch+10' cached && echo 1 || echo 0)"
t_assert "cached拒prev"    "1" "$(depth_match 'prev' cached; [ $? -ne 0 ] && echo 1)"
t_assert "previous含prev"  "0" "$(depth_match 'prev' previous; echo $?)"
t_assert "service含svc"    "0" "$(depth_match 'svcb' service; echo $?)"
t_assert "service拒fg"     "1" "$(depth_match 'fg' service; [ $? -ne 0 ] && echo 1)"
# plan_aggressive 决策
cat > $T/parsed << 'PF'
cch+10|CAC|111|com.a.app
svc|SVC|222|com.b.app
cch|CAC|333|com.tencent.mm
fg|TOP|444|com.hot.app
PF
OUT=$(plan_aggressive $T/parsed "com.tencent.mm" cached 5)
t_assert "cached档: 白名单免疫"   "0" "$(echo "$OUT" | grep -c '333')"
t_match  "cached档: 杀a不杀svc"   "RECLAIM 111 com.a.app" "$OUT"
t_assert "cached档: 不含svc"      "0" "$(echo "$OUT" | grep -c '222')"
OUT=$(plan_aggressive $T/parsed "com.tencent.mm" service 5)
t_match  "service档: 含svc"       "RECLAIM 222 com.b.app" "$OUT"
t_assert "service档: 白名单仍免疫" "0" "$(echo "$OUT" | grep -c '333')"
OUT=$(plan_aggressive $T/parsed "" cached 1)
t_assert "cap=1只杀1个"           "1" "$(echo "$OUT" | grep -c '^RECLAIM')"
rm -rf $T
t_done
