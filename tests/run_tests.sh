#!/system/bin/sh
# tests/run_tests.sh — 极简断言框架, 被各 test_*.sh source
PASS=0; FAIL=0
t_assert() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "    expected: [$2]"; echo "    actual:   [$3]"; fi
}
t_match() {
  case "$3" in
    (*$2*) PASS=$((PASS+1)); echo "  ok: $1";;
    (*) FAIL=$((FAIL+1)); echo "  FAIL: $1 (pattern $2)"; echo "    actual: [$3]";;
  esac
}
t_done() { echo "--- pass=$PASS fail=$FAIL ---"; exit $FAIL; }
