#!/system/bin/sh
# L4 v5 — 破坏性测试(安全阀验收)
# 教训汇总: 1)先停看门狗再杀引擎 2)KILL须带:后缀 3)SKIP不进stats.log,断言直调决策层
#           4)决策层测试须source库+取真实快照(T3后parsed是坏数据) 5)恢复用setsid防终端回收
M=/data/adb/modules/COSMemory
LIST=/sdcard/Android/COSMemory/名单列表.conf
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
dump_eng() { for p in $(pgrep -f 'COSMemory/engine/memory\.sh'); do echo "    残留: pid=$p cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-90)"; done; }

. "$M/engine/lists.sh"
. "$M/engine/policy.sh"
. "$M/engine/snapshot.sh"

eng_count() { pgrep -f 'COSMemory/engine/memory\.sh' 2>/dev/null | wc -l; }
eng_pid()   { pgrep -f 'COSMemory/engine/memory\.sh' 2>/dev/null | head -1; }
eng_alive() { [ "$(eng_count)" -gt 0 ]; }
stop_wd()   { for p in $(pgrep -f 'COSMemory/service\.sh'); do kill -9 $p 2>/dev/null; done; sleep 1; }
stop_eng()  { for p in $(pgrep -f 'COSMemory/engine/memory\.sh'); do kill -9 $p 2>/dev/null; done; sleep 2; }
iso_stop()  { stop_wd; stop_eng; }
start_eng() {
  setsid env LIST_PATH=$LIST WORKDIR=$M/data STATS_LOG=$M/data/stats.log \
    sh "$M/engine/memory.sh" </dev/null >/dev/null 2>&1 &
  sleep 10
}
start_wd()  { setsid env LIST_PATH=$LIST sh "$M/service.sh" </dev/null >/dev/null 2>&1 & sleep 1; }
assert_zero() { n=$(eng_count); [ "$n" -eq 0 ] && ok "$1: 零引擎残留" || { bad "$1: 残留$n个"; dump_eng; }; }
mm_main_alive() {
  for d in /proc/[0-9]*; do c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null) || continue
    case "$c" in 'com.tencent.mm '*) return 0;; esac; done; return 1
}

echo "=== 准备 ==="
cp "$M/config/名单列表.conf" /tmp/list.factory.bak || exit 1
iso_stop; assert_zero "准备"

echo "=== T1: 名单非法行(不连坐) ==="
printf 'GARBAGE_LINE_XYZ\nWHITE\nKILL nosuffix_invalid\n' >> "$LIST"
start_eng
eng_alive && ok "引擎带非法名单启动" || bad "启动失败(连坐)"
grep -q 'LIST_BAD=3' "$M/data/stats.log" && ok "LIST_BAD=3上报" || bad "LIST_BAD未报"
grep -q 'KEEPADJ.*com.tencent.mm' "$M/data/stats.log" && ok "合法行生效" || bad "合法行连坐"
cp /tmp/list.factory.bak "$LIST"

echo "=== T2: 看门狗 ==="
iso_stop; start_wd
i=0; while [ $i -lt 9 ] && ! eng_alive; do sleep 5; i=$((i+1)); done
eng_alive && ok "看门狗$((i*5))s拉起 pid=$(eng_pid)" || bad "45s未拉起"
grep -q 'WATCHDOG restart' "$M/data/stats.log" && ok "WATCHDOG记录" || bad "无WATCHDOG记录"

echo "=== T3: 快照源损坏 → 哨兵 ==="
iso_stop; assert_zero "T3隔离"
mkdir -p /tmp/fakebin
cat > /tmp/fakebin/dumpsys << 'FK'
#!/system/bin/sh
N=$(cat /tmp/fakebin/.n 2>/dev/null || echo 0); N=$((N+1)); echo $N > /tmp/fakebin/.n
[ $N -le 3 ] && exec /system/bin/dumpsys "$@"
echo "COMPLETELY BROKEN OUTPUT"
FK
chmod 755 /tmp/fakebin/dumpsys; rm -f /tmp/fakebin/.n
BEFORE=$(grep -c 'SENTINEL HALT' "$M/data/stats.log")
setsid env LIST_PATH=$LIST WORKDIR=$M/data STATS_LOG=$M/data/stats.log PATH=/tmp/fakebin:$PATH \
  sh "$M/engine/memory.sh" </dev/null >/dev/null 2>&1 &
sleep 15
AFTER=$(grep -c 'SENTINEL HALT' "$M/data/stats.log")
[ "$AFTER" -gt "$BEFORE" ] && ok "SENTINEL HALT触发" || bad "哨兵未触发 B=$BEFORE A=$AFTER"
n=$(eng_count); [ "$n" -eq 1 ] && ok "单引擎在控" || { bad "引擎数=$n"; dump_eng; }
L1=$(wc -l < "$M/data/stats.log"); sleep 7
NEW=$(( $(wc -l < "$M/data/stats.log") - L1 ))
[ "$NEW" -eq 0 ] && ok "停机窗口7s零写入" || bad "停机期新增${NEW}行"
stop_eng; rm -rf /tmp/fakebin
mkdir -p /tmp/fb2; printf '#!/system/bin/sh\necho broken\n' > /tmp/fb2/dumpsys; chmod 755 /tmp/fb2/dumpsys
rm -rf /tmp/x9w
setsid env LIST_PATH=$LIST WORKDIR=/tmp/x9w STATS_LOG=/tmp/x9w/stats.log PATH=/tmp/fb2:$PATH \
  sh "$M/engine/memory.sh" </dev/null >/dev/null 2>&1
RC=$?
grep -q 'halt: no lru source' /tmp/x9w/stats.log 2>/dev/null && [ $RC -eq 9 ] \
  && ok "启动即坏 exit 9" || bad "未exit9 RC=$RC"
rm -rf /tmp/fb2 /tmp/x9w
sleep 2; assert_zero "T3结束"

echo "=== T4: 白名单子进程被点名 → 拒杀 ==="
printf 'KILL com.tencent.mm:push\n' >> "$LIST"
# (a) 决策层: 真实快照 + 直调 plan_reclaim(SKIP不进stats.log)
dumpsys activity lru > /tmp/t4_snap.txt 2>/dev/null
lru_parse /tmp/t4_snap.txt > /tmp/t4_parsed.txt
grep -q 'com.tencent.mm:push' /tmp/t4_parsed.txt && ok "快照含push进程" || bad "快照无push"
eval "$(parse_lists "$LIST")"
OUT=$(plan_reclaim /tmp/t4_parsed.txt "$KILL_LIST" "$M/data/cool" 5 "$WHITE_LIST")
echo "$OUT" | grep -q 'SKIP whitelist com.tencent.mm:push' \
  && ok "决策层拦截 SKIP whitelist" || bad "决策层未拦截: [$OUT]"
echo "$OUT" | grep -q '^KILL .*com\.tencent\.mm' && bad "决策层输出了白名单KILL" || ok "决策层无白名单KILL输出"
rm -f /tmp/t4_snap.txt /tmp/t4_parsed.txt
# (b) 端到端
if ! mm_main_alive; then
  monkey -p com.tencent.mm -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 6
  am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1; sleep 6
fi
start_eng; sleep 10
grep -E '^KILL [0-9]+ com\.tencent\.mm' "$M/data/stats.log" >/dev/null \
  && bad "存在白名单KILL执行" || ok "无白名单KILL执行(端到端)"
mm_main_alive && ok "微信主进程存活" || bad "微信主进程消失"
cp /tmp/list.factory.bak "$LIST"

echo "=== T5: 恢复出厂 ==="
iso_stop
grep -q 'GARBAGE' "$LIST" && bad "名单残留垃圾" || ok "名单还原出厂"
[ "$(grep -c '^KILL' "$LIST")" -eq 0 ] && ok "无测试残留" || bad "KILL条目残留"
start_wd; start_eng; sleep 3
n=$(eng_count)
[ "$n" -ge 1 ] && ok "恢复: 看门狗+引擎运行(pid=$(eng_pid))" || { bad "恢复失败"; dump_eng; }
rm -f /tmp/list.factory.bak

echo ""
echo "--- L4 结果: pass=$PASS fail=$FAIL ---"
exit $FAIL
