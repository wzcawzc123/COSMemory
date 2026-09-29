#!/system/bin/sh
# 部署清场: 杀光所有 COSMemory 看门狗/引擎 → 起唯一实例 → 验证单链
# 用法(真机): sh tools/deploy_clean.sh
# 用途: 引擎文件更新后重启用; 多次部署防实例累积(v0.3 实战教训)
M=/data/adb/modules/COSMemory
n=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in
    *COSMemory/service.sh*|*COSMemory/engine/memory.sh*)
      kill -9 "${d#/proc/}" 2>/dev/null && n=$((n+1)) ;;
  esac
done
echo "清场: 杀掉 $n 个进程"
sleep 3
left=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *COSMemory/engine/memory.sh*) left=$((left+1));; esac
done
echo "残留引擎=$left (须为0)"
rm -f "$M/data/engine.started" "$M/data/wl_prev.txt"
setsid env LIST_PATH=/sdcard/Android/COSMemory/名单列表.conf \
  sh "$M/service.sh" </dev/null >/dev/null 2>&1 &
sleep 12
cnt=0
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *COSMemory/engine/memory.sh*) echo "引擎 pid=${d#/proc/}"; cnt=$((cnt+1));; esac
done
echo "引擎数=$cnt (须为1); started=$(cat "$M/data/engine.started" 2>/dev/null)"
