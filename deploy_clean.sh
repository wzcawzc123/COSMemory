#!/system/bin/sh
# v0.3 部署清场: 杀光所有 COSMemory 看门狗/引擎 → 只起一个 → 验证死因
M=/data/adb/modules/COSMemory
PATTERN_SERVICE='COSMemory/service.sh'
PATTERN_ENGINE='COSMemory/engine/memory.sh'

# 清场(本脚本 cmdline 不含上述模式, 无自匹配)
n=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in
    *"$PATTERN_SERVICE"*|*"$PATTERN_ENGINE"*)
      kill -9 "${d#/proc/}" 2>/dev/null && n=$((n+1)) ;;
  esac
done
echo "清场: 杀掉 $n 个进程"
sleep 3
# 确认清空
left=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *"$PATTERN_ENGINE"*) left=$((left+1));; esac
done
echo "残留引擎=$left (须为0)"

# 状态清理(让死因从零可测)
rm -f "$M/data/engine.started" "$M/data/wl_prev.txt"

# 起唯一看门狗
setsid env LIST_PATH=/sdcard/Android/COSMemory/名单列表.conf \
  sh "$M/service.sh" </dev/null >/dev/null 2>&1 &
sleep 12
# 验证
echo "=== 起后状态 ==="
cnt=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *"$PATTERN_ENGINE"*) echo "引擎 pid=${d#/proc/}"; cnt=$((cnt+1));; esac
done
echo "引擎数=$cnt (须为1)"
echo "started=$(cat "$M/data/engine.started" 2>/dev/null)"
echo "看门狗数:"
wc=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *"$PATTERN_SERVICE"*) wc=$((wc+1));; esac
done
echo "看门狗进程数=$wc (须为1或2: 主+subshell)"
