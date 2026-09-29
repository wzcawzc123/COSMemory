#!/system/bin/sh
# v0.3 T2: attrib.sh — DEATH检测 + stats轮转 (红→绿)
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/attrib.sh"

WORKDIR=/tmp/ta2; rm -rf $WORKDIR; mkdir -p $WORKDIR
STATS_LOG=$WORKDIR/stats.log; : > $STATS_LOG

# --- detect_death 测试 ---
cat > $WORKDIR/wl_prev.txt << 'P'
100|cch|com.tencent.mm
200|svc|com.tencent.mm:MSF
300|cch|com.tencent.mobileqq
P
cat > /tmp/ta2_parsed.txt << 'S'
cch|SVC|400|com.tencent.mm
cch|CAC|500|com.coolapk.market
S
detect_death /tmp/ta2_parsed.txt "com.tencent.mm com.tencent.mobileqq"
LOG=$(cat $STATS_LOG)
t_match "微信主进程死亡被记" "DEATH com.tencent.mm pid=100 last_state=cch" "$LOG"
t_match "微信MSF死亡被记" "DEATH com.tencent.mm:MSF pid=200 last_state=svc" "$LOG"
t_match "QQ死亡被记" "DEATH com.tencent.mobileqq pid=300 last_state=cch" "$LOG"
t_match "新pid不误报" "" "$(echo "$LOG" | grep 'pid=400')"

# 第二轮: 无死亡 → 无新DEATH
: > $STATS_LOG
cat > $WORKDIR/wl_prev.txt << 'P2'
400|cch|com.tencent.mm
P2
echo 'cch|SVC|400|com.tencent.mm' > /tmp/ta2_parsed.txt
detect_death /tmp/ta2_parsed.txt "com.tencent.mm"
t_assert "存活不报DEATH" "" "$(cat $STATS_LOG)"

# 首轮无prev → 不报错不报DEATH
rm -f $WORKDIR/wl_prev.txt; : > $STATS_LOG
detect_death /tmp/ta2_parsed.txt "com.tencent.mm"
t_assert "首轮静默" "" "$(cat $STATS_LOG)"
t_assert "首轮建立prev" "400|cch|com.tencent.mm" "$(cat $WORKDIR/wl_prev.txt)"

# --- rotate_stats 测试 ---
rm -rf /tmp/ta2_big; mkdir -p /tmp/ta2_big
BIG=/tmp/ta2_big/s.log
awk 'BEGIN{for(i=0;i<16000;i++) print "LINE_FILLER_" i "_xxxxxxxxxxxxxxxxxxxx"}' > $BIG
echo "MARKER_TAIL_LINE" >> $BIG
SZ0=$(wc -c < $BIG)
STATS_LOG=$BIG rotate_stats
SZ1=$(wc -c < $BIG)
t_assert "超阈值被轮转" "yes" "$([ "$SZ0" -gt 524288 ] && [ "$SZ1" -le 65600 ] && echo yes || echo no)"
t_match "轮转留尾" "MARKER_TAIL_LINE" "$(tail -2 $BIG)"
t_match "轮转记日志" "ROTATED" "$(grep ROTATED $BIG | tail -1)"

SMALL=/tmp/ta2_big/small.log; echo "keep" > $SMALL
STATS_LOG=$SMALL rotate_stats
t_assert "小文件不轮转" "keep" "$(cat $SMALL)"

rm -rf $WORKDIR /tmp/ta2_parsed.txt /tmp/ta2_big
t_done
