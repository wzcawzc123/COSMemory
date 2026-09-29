#!/system/bin/sh
# all.sh — 聚合跑全部 test_*.sh (部署回归一键入口)
# 设备探测: 无 COSMemory 模块目录时跳过设备专用测试(e2e/l4 硬编码 /data/adb 路径)
D=$(dirname "$0")
ON_DEVICE=0; [ -d /data/adb/modules/COSMemory ] && ON_DEVICE=1
TOTAL_FAIL=0; SKIP=""
for t in "$D"/test_*.sh; do
  n=$(basename "$t")
  case "$n" in
    test_e2e.sh|test_l4.sh)
      [ $ON_DEVICE -eq 0 ] && { SKIP="$SKIP $n"; continue; } ;;
  esac
  printf '== %s ==\n' "$n"
  OUT="${TMPDIR:-/tmp}/all.$$.out"
  timeout 20 sh "$t" > "$OUT" 2>&1
  rc=$?
  tail -3 "$OUT"
  if [ $rc -eq 124 ]; then echo "  FAIL: 超时20s"
  elif [ $rc -ne 0 ]; then TOTAL_FAIL=$((TOTAL_FAIL + 1)); fi
done
echo "=== total_fail=$TOTAL_FAIL | 未跑(设备专用):${SKIP:- 无} | on_device=$ON_DEVICE ==="
exit $TOTAL_FAIL
