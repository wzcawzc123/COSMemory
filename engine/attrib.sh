#!/bin/sh
# engine/attrib.sh — 可归因性函数(v0.3): 白名单死亡检测 + stats轮转

# DEATH 检测: 上一轮白名单快照有、本轮消失 → 记 DEATH(pkg/pid/最后状态)
# $1=parsed.txt(本轮) $2=WHITE_LIST  状态文件=$WORKDIR/wl_prev.txt
detect_death() {
  [ -n "$2" ] || return 0
  awk -F'|' -v wl="$2" '
    BEGIN { n=split(wl, w, " ") }
    {
      for (i=1; i<=n; i++) {
        if ($4 == w[i]) { print $3 "|" $1 "|" $4; break }
        if (index(w[i], ":") == 0 && index($4, w[i] ":") == 1) { print $3 "|" $1 "|" $4; break }
      }
    }' "$1" > "$WORKDIR/wl_now.txt"
  if [ -f "$WORKDIR/wl_prev.txt" ]; then
    while IFS='|' read -r pid lastst pkg; do
      [ -z "$pid" ] && continue
      if ! grep -q "^$pid|" "$WORKDIR/wl_now.txt" 2>/dev/null; then
        echo "[$(date '+%F %T')] DEATH $pkg pid=$pid last_state=$lastst" >> "$STATS_LOG"
      fi
    done < "$WORKDIR/wl_prev.txt"
  fi
  mv "$WORKDIR/wl_now.txt" "$WORKDIR/wl_prev.txt" 2>/dev/null
}

# stats 轮转: >512KB 截尾 64KB (防 17MB/月)
rotate_stats() {
  [ -f "$STATS_LOG" ] || return 0
  sz=$(wc -c < "$STATS_LOG" 2>/dev/null)
  [ -n "$sz" ] && [ "$sz" -gt 524288 ] || return 0
  if tail -c 65536 "$STATS_LOG" > "$STATS_LOG.tmp" 2>/dev/null; then
    mv "$STATS_LOG.tmp" "$STATS_LOG"
    echo "[$(date '+%F %T')] ROTATED from=${sz}B to=65536B" >> "$STATS_LOG"
  fi
}

# 白名单 kill 采集(v0.3): events缓冲时间窗增量抓 am_proc_died/am_kill
# $1=WHITE_LIST  归档=$WORKDIR/kill_capture.log (>64KB截尾)
capture_kills() {
  [ -n "$1" ] || return 0
  LAST=$(cat "$WORKDIR/kill_last" 2>/dev/null || echo 0)
  LAST=${LAST%%.*}
  PAT=$(echo "$1" | tr ' ' '|')
  EV=$(logcat -d -b events -v epoch -t 300 2>/dev/null) || return 0
  # 增量(>上次窗口) 且 白名单相关 且 died/kill事件
  echo "$EV" | awk -v L="$LAST" '{t=$1; sub(/\..*/, "", t); if (t+0 > L+0) print}' \
    | grep -E 'am_proc_died|am_kill' | grep -E "$PAT" >> "$WORKDIR/kill_capture.log" 2>/dev/null
  # 推进窗口基准(events首行=最旧,需取最大epoch → 用最后一行)
  echo "$EV" | tail -1 | awk '{print int($1)}' > "$WORKDIR/kill_last"
  # 轮转
  sz=$(wc -c < "$WORKDIR/kill_capture.log" 2>/dev/null)
  if [ -n "$sz" ] && [ "$sz" -gt 65536 ]; then
    tail -c 16384 "$WORKDIR/kill_capture.log" > "$WORKDIR/kill_capture.tmp" \
      && mv "$WORKDIR/kill_capture.tmp" "$WORKDIR/kill_capture.log"
  fi
}
