#!/system/bin/sh
# v0.3 T1: exec.sh 可归因性增强测试 (红→绿)
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/exec.sh"
SELF=$$
STATE=/tmp/te3_state; rm -rf $STATE; mkdir -p $STATE
export STATS_LOG=/tmp/te3_stats.log; : > $STATS_LOG

echo 100 > /proc/$SELF/oom_score_adj

# 1) KEEPADJ 带 pid
OUT=$(printf 'KEEPADJ %s test_exec3.sh 200\n' "$SELF" | apply_actions /dev/stdin "$STATE")
t_match "KEEPADJ汇总" "APPLIED=1 KILLED=0 FAILED=0" "$OUT"
t_match "KEEPADJ带pid" "KEEPADJ $SELF test_exec3.sh 100->200" "$(cat $STATS_LOG)"
t_assert "adj已写" "200" "$(cat /proc/$SELF/oom_score_adj)"

# 2) FAILED 分类: cmdline不符 → mismatch
OUT=$(printf 'KILL 1 wrong.pkg\n' | apply_actions /dev/stdin "$STATE")
t_match "FAILED分类汇总" "FAILED=1" "$OUT"
t_match "mismatch计数" "mismatch=1" "$OUT"
t_match "missing=0" "missing=0" "$OUT"

# 3) 不存在的pid → missing
OUT=$(printf 'KEEPADJ 999999 nonexistent.pkg 200\n' | apply_actions /dev/stdin "$STATE")
t_match "missing计数" "missing=1" "$OUT"

# 4) SKIPPED 汇总(acts里的SKIP行计数)
OUT=$(printf 'SKIP cooldown com.a:p\nSKIP whitelist com.b\nKEEPADJ %s test_exec3.sh 300\n' "$SELF" | apply_actions /dev/stdin "$STATE")
t_match "SKIPPED计数" "SKIPPED=2" "$OUT"
t_match "SKIP不执行只计数" "APPLIED=1" "$OUT"

# 5) 空格式基线(兼容旧断言风格)
OUT=$(printf '' | apply_actions /dev/stdin "$STATE")
t_match "空输入全零" "APPLIED=0 KILLED=0 FAILED=0 missing=0 mismatch=0 write=0 SKIPPED=0" "$OUT"

restore_state "$STATE"
t_assert "还原成功" "100" "$(cat /proc/$SELF/oom_score_adj)"
rm -rf $STATE $STATS_LOG
t_done
