#!/system/bin/sh
# v0.3 T7: capture_kills 白名单kill采集 (mock logcat)
D=$(dirname "$0"); . "$D/run_tests.sh"
WORKDIR=/tmp/tk; rm -rf $WORKDIR; mkdir -p $WORKDIR
# mock logcat: 输出3行 events(epoch格式), 含白名单与非白名单死亡
mkdir -p /tmp/tk_bin
cat > /tmp/tk_bin/logcat << 'MK'
#!/bin/sh
echo "1790648000.100 3483 I am_proc_died: [0,111,com.tencent.mm:tools,905,10]"
echo "1790648010.200 3483 I am_proc_died: [0,222,com.unknown.app,900,10]"
echo "1790648020.300 3483 I am_proc_died: [0,333,com.tencent.mobileqq:MSF,905,10]"
MK
chmod 755 /tmp/tk_bin/logcat
. $(dirname "$0")/../engine/attrib.sh
export STATS_LOG=$WORKDIR/stats.log; : > $STATS_LOG

# 首次采集: 白名单两个死都收, 非白名单丢弃
PATH=/tmp/tk_bin:$PATH capture_kills "com.tencent.mm com.tencent.mobileqq"
OUT=$(cat $WORKDIR/kill_capture.log 2>/dev/null)
t_match "微信tools死亡被采集" "com.tencent.mm:tools" "$OUT"
t_match "QQ MSF死亡被采集" "com.tencent.mobileqq:MSF" "$OUT"
t_assert "非白名单被过滤" "" "$(echo "$OUT" | grep 'unknown.app')"
t_assert "时间窗基准已记" "1790648020" "$(cat $WORKDIR/kill_last 2>/dev/null | cut -d. -f1)"

# 第二次采集(同mock重复): 时间窗去重 → 不重复追加
PATH=/tmp/tk_bin:$PATH capture_kills "com.tencent.mm com.tencent.mobileqq"
N=$(wc -l < $WORKDIR/kill_capture.log)
t_assert "重复窗口去重" "2" "$N"

# 轮转: 造大文件
awk 'BEGIN{for(i=0;i<3000;i++) print "KFILLER_" i "_xxxxxxxxxxxxxxxx"}' > $WORKDIR/kill_capture.log
PATH=/tmp/tk_bin:$PATH capture_kills "com.tencent.mm"
t_assert "kill_capture轮转" "yes" "$([ $(wc -c < $WORKDIR/kill_capture.log) -le 66000 ] && echo yes || echo no)"

rm -rf $WORKDIR /tmp/tk_bin
t_done
