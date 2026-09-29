#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/snapshot.sh"
F="$D/fixtures/lru_sample.txt"
OUT=$(lru_parse "$F")
LINE=$(echo "$OUT" | grep '|com.tencent.mm$' | head -1)
t_match "微信主进程解析" "15942|com.tencent.mm" "$LINE"
t_match "前台状态保留" "fg|TOP|11098|io.github.mangi.eta" "$OUT"
ALT=$(echo "$OUT" | grep "com.ss.android.ugc.aweme$" | head -1)
t_match "后台App保留cch态" "cch|LAST|6213" "$ALT"
t_match "子进程冒号保留" "com.tencent.mm:appbrand1" "$OUT"
t_match "无表头污染" "" "$(echo "$OUT" | grep 'ACTIVITY MANAGER')"
eval "$(lru_stats "$F")"
t_assert "总数>100" "yes" "$([ "$LRU_TOTAL" -gt 100 ] && echo yes || echo no)"
t_assert "解析率>=50%" "yes" "$([ $((LRU_PARSED*100/LRU_TOTAL)) -ge 50 ] && echo yes || echo no)"
t_done
