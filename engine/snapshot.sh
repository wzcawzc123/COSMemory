#!/system/bin/sh
# engine/snapshot.sh — 快照采集与解析
WORKDIR="${WORKDIR:-/data/local/tmp/cosmem}"

lru_parse() {
  awk '
    /^[[:space:]]*#[0-9]+:/ {
      line=$0
      sub(/^[[:space:]]*#[0-9]+:[[:space:]]+/, "", line)
      if (match(line, /[0-9]+:[a-zA-Z.]/)) {
        head=substr(line, 1, RSTART-1)
        rest=substr(line, RSTART)
        pidpkg=rest; sub(/[[:space:]].*/, "", pidpkg)
        split(head, h, /[[:space:]]+/)
        state=h[1]; procstate=""
        for (i=2; i<=length(h); i++) if (h[i] != "") { procstate=h[i]; break }
        n=index(pidpkg, ":")
        pid=substr(pidpkg, 1, n-1)
        pkg=substr(pidpkg, n+1); sub(/\/.*$/, "", pkg)
        if (pid != "" && pkg != "") print state "|" procstate "|" pid "|" pkg
      }
    }' "$1"
}

lru_stats() {
  total=$(grep -c '^[[:space:]]*#[0-9]*:' "$1")
  parsed=$(lru_parse "$1" | wc -l)
  echo "LRU_TOTAL=$total; LRU_PARSED=$parsed"
}

snapshot_collect() {
  mkdir -p "$WORKDIR"
  dumpsys activity lru > "$WORKDIR/snapshot.txt" 2>/dev/null
}
