#!/system/bin/sh
# frozencap.sh — 面板冻结观测卡 (v1.1.0): 系统墓碑覆盖透明化, 单行输出
# 输出: OK:<冻结进程数>|<pkg1>,<pkg2>,...  (遍历 cgroup frozen 状态, 与 lru 无关, <100ms)
out=""; n=0
for ev in /sys/fs/cgroup/apps/uid_*/pid_*/cgroup.events; do
  [ -f "$ev" ] || continue
  grep -q '^frozen 1$' "$ev" 2>/dev/null || continue
  d=${ev%/cgroup.events}; pid=${d##*_}
  pkg=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | awk '{print $1}')
  [ -n "$pkg" ] || continue
  pkg=${pkg%%:*}
  case ",$out," in *",$pkg,"*) continue;; esac
  out="${out:+$out,}$pkg"; n=$((n+1))
done
echo "OK:$n|${out:-无}"
