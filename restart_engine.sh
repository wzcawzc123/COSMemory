#!/system/bin/sh
# 精确杀引擎本体(cmdline 等值匹配, 避开含路径的wrapper) → 等看门狗拉新版
M=/data/adb/modules/COSMemory
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in
    "sh $M/engine/memory.sh "|*"busybox ash $M/engine/memory.sh "*)
      # 排除 sh -c 型 wrapper(含 'sh -c ')
      case "$c" in *"sh -c "*) ;; *) kill -9 "${d#/proc/}" && echo "杀引擎 ${d#/proc/}";; esac
      ;;
  esac
done
sleep 2
# 残留检查
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *"$M/engine/memory.sh"*)
    case "$c" in *"sh -c "*) echo "wrapper残留(无害): ${d#/proc/}";; *) echo "引擎仍在: ${d#/proc/} :: $c";; esac ;;
  esac
done
