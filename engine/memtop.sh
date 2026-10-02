#!/system/bin/sh
# memtop.sh — 面板内存占用卡 (v1.1.0): dumpsys meminfo → 按包聚合PSS TOP8, 单行输出
# 输出: OK:<pkg>=<KB>|<pkg>=<KB>|... (桥单行约定; dumpsys约2.6s, 面板按需调用不进轮询)
# 截段: Total PSS by process 起 → 下一个 "Total PSS by" 段头止; 子进程(:sub)归并主包
r=$(timeout 8 dumpsys meminfo 2>/dev/null \
  | awk '/^Total PSS by process:/{f=1;next} /^Total PSS by/{if(f)exit} f' \
  | sed -n 's/^ *\([0-9,]*\)K: \([^ ]*\).*/\2 \1/p' \
  | awk '{gsub(/,/,"",$2); split($1,a,":"); s[a[1]]+=$2} END {for (k in s) printf "%s=%d\n", k, s[k]}' \
  | sort -t= -k2 -rn \
  | head -8 \
  | tr '\n' '|' \
  | sed 's/|$//')
echo "OK:${r:-空}"
