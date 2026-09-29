#!/system/bin/sh
# 取证: 所有嫌疑进程的完整 cmdline + ppid 链
echo '=== 所有含 service.sh / memory.sh 的进程 ==='
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in
    *service.sh*|*memory.sh*)
      pid=${d#/proc/}
      ppid=$(awk '{print $4}' "$d/stat" 2>/dev/null)
      st=$(stat -c %y "$d" 2>/dev/null | cut -d. -f1)
      echo "pid=$pid ppid=$ppid mtime=$st"
      echo "   cmd=$(echo "$c" | cut -c1-140)"
      ;;
  esac
done
echo
echo '=== 看门狗启动时间(区分新旧代码) ==='
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
  case "$c" in *service.sh*) echo "pid=${d#/proc/} mtime=$(stat -c %y $d | cut -d. -f1)";; esac
done
echo '=== 模块 service.sh 的 mtime(新代码时间) ==='
stat -c '%y %n' /data/adb/modules/COSMemory/service.sh
