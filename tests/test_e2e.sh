#!/system/bin/sh
# L2 因果验证: 引擎关/开 两段 adj 对比 (2026-09-28 实测通过)
# 判定: 段B/C 白名单进程 adj=200 且 stats 有 KEEPADJ; 段A 无 200
C=$(cd "$(dirname "$0")/.." && pwd)
export STATS_LOG=$C/data/stats.log
SNAP() {
  for d in /proc/[0-9]*; do
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$c" in com.tencent.mm*) echo "adj=$(cat $d/oom_score_adj 2>/dev/null) :: $c";; esac
  done | sort
}
stop_engine() {
  [ -f "$C/data/engine.pid" ] && kill -9 "$(cat $C/data/engine.pid)" 2>/dev/null
  rm -f "$C/data/engine.pid"
}
stop_engine; sleep 2
monkey -p com.tencent.mm -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 5
am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1; sleep 8
echo "== 段A: 引擎关(基线) =="; SNAP
LIST_PATH=${LIST_PATH:-/sdcard/Android/COSMemory/名单列表.conf} WORKDIR=$C/data STATS_LOG=$STATS_LOG \
  sh -c "exec sh $C/engine/memory.sh & echo \$! > $C/data/engine.pid; wait" >/dev/null 2>&1 &
sleep 15
echo "== 段B: 引擎开15s =="; SNAP
monkey -p com.coolapk.market -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 4
am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1; sleep 10
echo "== 段C: 切App两轮后 =="; SNAP
echo "== stats 尾部 =="; tail -6 "$STATS_LOG"
stop_engine
