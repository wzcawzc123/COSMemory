#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/exec.sh"
SELF=$$
STATE=/tmp/te_state; rm -rf $STATE; mkdir -p $STATE
export STATS_LOG=/tmp/te_stats.log; : > $STATS_LOG

# 基线: 自进程 adj 设为已知值
echo 100 > /proc/$SELF/oom_score_adj
ORIG=$(cat /proc/$SELF/oom_score_adj)

OUT=$(printf 'KEEPADJ %s test_exec.sh 200\n' "$SELF" | apply_actions /dev/stdin "$STATE")
t_match "KEEPADJ计数" "APPLIED=1" "$OUT"
t_assert "adj已写200" "200" "$(cat /proc/$SELF/oom_score_adj)"
t_match "before已记录" "orig=100" "$(cat $STATE/adj_$SELF 2>/dev/null)"
t_match "stats已追加" "KEEPADJ * test_exec.sh 100->200" "$(cat $STATS_LOG)"

# 无变化时不重复写
OUT=$(printf 'KEEPADJ %s test_exec.sh 200\n' "$SELF" | apply_actions /dev/stdin "$STATE")
t_match "无变化不计数" "APPLIED=0 KILLED=0 FAILED=0" "$OUT"

# PID/cmdline 不符 → 拒绝(防PID复用)
OUT=$(printf 'KILL 1 wrong.pkg\n' | apply_actions /dev/stdin "$STATE")
t_match "PID/cmdline不符拒绝" "FAILED=1" "$OUT"

# 还原
restore_state "$STATE"
t_assert "还原回100" "100" "$(cat /proc/$SELF/oom_score_adj)"
t_done
