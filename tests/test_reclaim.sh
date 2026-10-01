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
# apply_actions RECLAIM 分支 (exec.sh): 不存在pid → missing=1 (区别于default的write=1)
. "$D/../engine/exec.sh"
printf 'RECLAIM 999999 test_reclaim.app 200\n' > $T/acts2
OUT=$(apply_actions $T/acts2 $T/st 2>/dev/null)
t_match "RECLAIM进执行分支(missing=1)" "missing=1" "$OUT"
t_assert "非default分支(write=0)" "0" "$(printf '%s' "$OUT" | sed -n 's/.*write=\([0-9]*\).*/\1/p')"
# ---- 模拟完整链(spec §6): 注入配置/PSI/水位 驱动 reclaim_cycle ----
sed -n '/^reclaim_cycle()/,/^}/p' "$D/../engine/memory.sh" > $T/rc.sh
. $T/rc.sh
MK=$T/mod; mkdir -p $MK/config
printf '{ "reclaim": { "aggressive": true, "depth": "service", "psiThreshold": 5.0, "memFloorMB": 1024, "cooldownSec": 60 } }\n' > $MK/config/memory.json
WD=$T/wd; mkdir -p $WD
printf 'svc|SVC|555|com.z.app\ncch|CAC|666|com.tencent.mm\n' > $WD/parsed.txt
: > $WD/acts
printf 'some avg10=9.00 avg60=4.00\n' > $T/psi2
printf 'MemAvailable:  300000 kB\n' > $T/mem2
run_rc() {
  MODDIR=$MK WORKDIR=$WD WHITE_LIST="com.tencent.mm" MAX_KILL=5 CAP_PSI=1 \
    PSI_PATH=$T/psi2 MEMINFO_PATH=$T/mem2 TELEM_PATH=$T/telem reclaim_cycle
}
run_rc
t_match  "模拟链: acts产出RECLAIM" "RECLAIM 555 com.z.app" "$(cat $WD/acts)"
t_assert "模拟链: 白名单免疫" "0" "$(grep -c 666 $WD/acts)"
t_assert "模拟链: 深度=service命中svc" "1" "$(grep -c '555' $WD/acts)"
t_assert "冷却时间戳落盘" "1" "$([ -f $WD/reclaim.last ] && echo 1 || echo 0)"
: > $WD/acts
run_rc
t_assert "冷却节流: 二跑零新增" "0" "$(grep -c RECLAIM $WD/acts)"
# 总闸关
printf '{ "reclaim": { "aggressive": false, "depth": "cached" } }\n' > $MK/config/memory.json
rm -f $WD/reclaim.last
run_rc
t_assert "总闸关: 零动作" "0" "$(grep -c RECLAIM $WD/acts)"
t_assert "PSI等于阈值也算(>=)" "1" "$(reclaim_should_fire 1000 1 8.5 1024 60 1 $T/psi $T/mem $T/last)"
t_assert "坏cool(两行值)回默认不炸" "1" "$(reclaim_should_fire 1000 1 5 1024 "60
60" 1 $T/psi $T/mem $T/last)"
rm -rf $T
t_done
