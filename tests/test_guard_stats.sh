#!\/system\/bin\/sh
# B3: guard_stats.sh 输出契约 (host 可跑, 注入环境变量绕开设备路径)
D=$(dirname "$0"); . "$D/run_tests.sh"
TMP=$(mktemp -d); mkdir -p "$TMP/arch"
T0=1790700000
# 6 种 ACT 各若干: BLOCK×2(o-stop,frozen) FUSE×1 ERROR×1 PASS_OBSERVE×2 PASS_NO_RULE×1 PASS_DUP×1
cat > "$TMP/live" <<EOF
$T0|4242|com.tencent.mm|o-stop|BLOCK|stop com.tencent.mm due to o-stop(40)
$((T0+3600))|4242|com.tencent.mm|o-stop|BLOCK|stop again
$((T0+7200))|4242|com.tencent.mm|frozen|BLOCK|Sync transaction while frozen
$((T0+10800))|4242|com.tencent.mm|o-stop|FUSE|stop x due to o-stop(40)
$((T0+14400))|0|*|config|ERROR|missing
$((T0+18000))|99|com.tencent.mm|o-stop|PASS_OBSERVE|any reason
$((T0+21600))|99|com.tencent.mm|o-stop|PASS_OBSERVE|any reason
$((T0+25200))|99|com.tencent.mm||PASS_NO_RULE|remove task
$((T0+28800))|99|com.tencent.mm|o-stop|PASS_DUP|dup
$((T0+32400))|88|com.other.app|o-stop|PASS_NO_RULE|x
EOF
printf 'VERSION=1\nMODE=guard\nWHITE com.tencent.mm\n' > "$TMP/bridge.conf"
printf 'not-a-pipe-line\nbad\n' > "$TMP/arch/1999-01-01.log"
touch "$TMP/arch/$(date +%F).log" 2>/dev/null || true

OUT=$(GS_BRIDGE="$TMP/bridge.conf" GS_LIVE="$TMP/live" GS_ARCHIVE="$TMP/arch" \
      GS_MOD=com.xune.cosguard \
      sh "$D/../engine/guard_stats.sh" "$(date +%F)" 2>/dev/null)

t_assert  "JSON 非空且以}结尾" "1" "$(echo "$OUT" | grep -c '}$')"
t_assert  "mode=guard"            "1" "$(echo "$OUT" | grep -c '"mode":"guard"')"
t_assert  "block=3"               "1" "$(echo "$OUT" | grep -c '"block":3,"fuse":1,"error":1,"pass_observe":2')"
t_assert  "rules 含 o-stop n=2"   "1" "$(echo "$OUT" | grep -c '"rule":"o-stop","n":2')"
t_assert  "rules 含 frozen n=1"   "1" "$(echo "$OUT" | grep -c '"rule":"frozen","n":1')"
t_assert  "whitelist 最近事件=PASS_DUP" "1" "$(echo "$OUT" | grep -c '"pkg":"com.tencent.mm".*"last_act":"PASS_DUP"')"
t_assert  "whitelist block 计数=3" "1" "$(echo "$OUT" | grep -c '"pkg":"com.tencent.mm","block":3')"
t_assert  "recent 最多 10 条"     "10" "$(echo "$OUT" | grep -o '"ts":[0-9]*' | wc -l | tr -d ' ')"
t_assert  "hourly 24 桶"          "24" "$(echo "$OUT" | grep -o '"h":[0-9]*' | wc -l | tr -d ' ')"
t_match   "dates 含今天"          "$(date +%F)" "$OUT"
t_match   "JSON 内 reason 转义后无裸竖线" "o-stop(40)" "$OUT"
# 空源: 不崩且结构完整
OUT2=$(GS_BRIDGE="$TMP/bridge.conf" GS_LIVE="$TMP/none" GS_ARCHIVE="$TMP/empty_dir" \
       sh "$D/../engine/guard_stats.sh" "2000-01-01" 2>/dev/null)
t_assert  "空源 block=0" "1" "$(echo "$OUT2" | grep -c '"block":0,"fuse":0,"error":0,"pass_observe":0')"
# FREEZE 字段 (Task 4)
printf 'VERSION=1\nMODE=guard\nFREEZE_ENABLED=1\nFREEZE com.fz.alive\nFREEZE com.fz.dead\nWHITE com.tencent.mm\n' > "$TMP/bridge.conf"
printf 'svc|SVC|111|com.fz.alive\n' > "$TMP/parsed.txt"
printf '%s|7|com.fz.alive||FREEZE|engine reap\n%s|0|*|fz|FREEZE_BLOCK|start blocked\n' "$((T0+36000))" "$((T0+39600))" >> "$TMP/live"
OUT=$(GS_BRIDGE="$TMP/bridge.conf" GS_LIVE="$TMP/live" GS_ARCHIVE="$TMP/arch" GS_MOD=com.xune.cosguard GS_PARSED="$TMP/parsed.txt" sh "$D/../engine/guard_stats.sh" "$(date +%F)" 2>/dev/null)
t_assert  "freezeToday=2" "1" "$(echo "$OUT" | grep -c '"freezeToday":2')"
t_match   "freezeList alive=true" '"pkg":"com.fz.alive","alive":true' "$OUT"
t_match   "freezeList alive=false" '"pkg":"com.fz.dead","alive":false' "$OUT"
rm -rf "$TMP"; t_done
