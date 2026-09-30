#!/system/bin/sh
# guard_stats.sh — COSGuard 遥测聚合(spec §7.1) → 单个 JSON
# 测试注入: GS_BRIDGE GS_LIVE GS_ARCHIVE GS_MOD
D=$(dirname "$0")
BRIDGE=${GS_BRIDGE:-/data/system/cosmem/guard.conf}
LIVE=${GS_LIVE:-/data/system/cosmem/guard.telemetry}
ARCH=${GS_ARCHIVE:-$D/../data/guard}
MODPKG=${GS_MOD:-com.xune.cosguard}
PARSED=${GS_PARSED:-$D/../data/parsed.txt}
DATE=${1:-$(date +%F)}
TODAY=$(date +%F)

MODE=observe
[ -f "$BRIDGE" ] && MODE=$(sed -n 's/^MODE=//p' "$BRIDGE" | head -1)
[ "$MODE" = guard ] || MODE=observe
MODULE=absent
command -v pm >/dev/null 2>&1 && pm path "$MODPKG" >/dev/null 2>&1 && MODULE=installed
AGE=-1
if [ -f "$BRIDGE" ]; then
  MT=$(stat -c %Y "$BRIDGE" 2>/dev/null || echo 0)
  AGE=$(( $(date +%s) - MT ))
fi
LIVE_TODAY=0; [ -s "$LIVE" ] && LIVE_TODAY=1

# 源 = 目标日归档; 仅当目标日为今天才并入 live
SRC="${TMPDIR:-/tmp}/gs.$$.src"
cat "$ARCH/$DATE.log" 2>/dev/null > "$SRC"
[ "$DATE" = "$TODAY" ] && [ -f "$LIVE" ] && cat "$LIVE" >> "$SRC"

# dates[] = 归档文件名列表(倒序)
DATES=$(ls "$ARCH" 2>/dev/null | sed -n 's/^\([0-9][0-9-]*\)\.log$/\1/p' | sort -r \
  | awk '{printf "%s\"%s\"", (NR>1?",":""), $0}')
# 白名单(bridge WHITE 行) — whitelist 统计只覆盖名单内包
WL=$(sed -n 's/^WHITE //p' "$BRIDGE" 2>/dev/null | tr '\n' ' ')
BODY=$(awk -F'|' -v date="$DATE" -v mode="$MODE" -v module="$MODULE" \
           -v age="$AGE" -v lt="$LIVE_TODAY" -v wl="$WL" '
function jesc(s){ gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); gsub(/\r/,"",s); return s }
$1 ~ /^[0-9]+$/ && NF >= 6 {
  act = $5
  cnt[act]++
  if (act == "BLOCK") {
    if (!($4 in rules)) rules[$4] = 0
    rules[$4]++
    hb[int(($1 + 28800) % 86400 / 3600)]++      # 设备固定 UTC+8 按本地小时分桶
    pblock[$3]++
  }
  if (act == "FUSE") hf[int(($1 + 28800) % 86400 / 3600)]++
  if ($2 != "0" && index(" " wl " ", " "$3 " ") > 0) { last[$3]=$1; lastact[$3]=act }
  n++
  if (n <= 200) { rts[n]=$1; rpkg[n]=$3; rrule[n]=$4; ract[n]=act; rreason[n]=$6 }
}
END {
  printf "{\"date\":\"%s\",\"mode\":\"%s\",\"module\":\"%s\",\"live_today\":%s,", \
         date, mode, module, (lt ? "true" : "false")
  printf "\"snapshot_age_s\":%d,\"fuse_threshold\":10,", age
  printf "\"today\":{\"block\":%d,\"fuse\":%d,\"error\":%d,\"pass_observe\":%d},", \
         cnt["BLOCK"]+0, cnt["FUSE"]+0, cnt["ERROR"]+0, cnt["PASS_OBSERVE"]+0
  printf "\"hourly\":["
  for (h = 0; h < 24; h++)
    printf "%s{\"h\":%d,\"block\":%d,\"fuse\":%d}", (h ? "," : ""), h, hb[h]+0, hf[h]+0
  printf "],\"rules\":["
  f = 1
  for (k in rules) { printf "%s{\"rule\":\"%s\",\"n\":%d}", (f ? "" : ","), k, rules[k]; f = 0 }
  printf "],\"whitelist\":["
  f = 1
  for (k in last) {
    printf "%s{\"pkg\":\"%s\",\"block\":%d,\"last_ts\":%d,\"last_act\":\"%s\"}", \
           (f ? "" : ","), k, pblock[k]+0, last[k], lastact[k]
    f = 0
  }
  printf "],\"recent\":["
  f = 1; shown = 0
  for (i = n; i >= 1 && shown < 10; i--) {
    if (i > 200 || rts[i] == "") continue
    printf "%s{\"ts\":%d,\"pkg\":\"%s\",\"rule\":\"%s\",\"act\":\"%s\",\"reason\":\"%s\"}", \
           (f ? "" : ","), rts[i], rpkg[i], rrule[i], ract[i], jesc(rreason[i])
    f = 0; shown++
  }
  printf "]"
}' "$SRC")

# FREEZE 字段 (Task 4): freezeToday=当日 FREEZE+FREEZE_BLOCK; freezeList=桥行+parsed 判活
FZT=$(awk -F'|' '$5=="FREEZE" || $5=="FREEZE_BLOCK" {n++} END{print n+0}' "$SRC")
FZ=""
for p in $(sed -n 's/^FREEZE //p' "$BRIDGE" 2>/dev/null); do
  alive=false
  [ -f "$PARSED" ] && awk -F'|' -v p="$p" '$4==p{f=1} END{exit !f}' "$PARSED" && alive=true
  FZ="$FZ${FZ:+,}{\"pkg\":\"$p\",\"alive\":$alive}"
done
printf '%s,"freezeToday":%s,"freezeList":[%s],"dates":[%s]}\n' "$BODY" "$FZT" "$FZ" "$DATES"
rm -f "$SRC"
