#!/system/bin/sh
# engine/listedit.sh — 名单编辑写入层 (spec list-editor §4.2)
# 用法: sh listedit.sh add|del <WHITE|KILL|FREEZE> <target>
MODDIR="${MODDIR:-/data/adb/modules/COSMemory}"
CONF="${LIST_PATH:-/sdcard/Android/COSMemory/名单列表.conf}"
BRIDGE_DIR="${BRIDGE_DIR:-/data/system/cosmem}"
BRIDGE="${BRIDGE:-$BRIDGE_DIR/guard.conf}"
. "$MODDIR/engine/lists.sh"
. "$MODDIR/engine/bridge.sh"
PKG='^[a-zA-Z][a-zA-Z0-9._]+$'
PKG_SUB='^[a-zA-Z][a-zA-Z0-9._]+:.+$'
MAX_LINES=500

validate() { # $1=group $2=target → stdout=errcode rc=0/1
  g="$1"; t="$2"
  [ -n "$g" ] && [ -n "$t" ] || { echo badfmt; return 1; }
  [ ${#t} -le 128 ] || { echo badfmt; return 1; }
  case "$g" in
    WHITE)  printf '%s' "$t" | grep -qE "$PKG" || { echo badfmt; return 1; };;
    KILL)   printf '%s' "$t" | grep -qE "$PKG_SUB" || { echo badfmt; return 1; };;
    FREEZE) printf '%s' "$t" | grep -qE "$PKG|$PKG_SUB" || { echo badfmt; return 1; };;
    *) echo badfmt; return 1;;
  esac
  return 0
}
conf_stats() { # $1=file → "bad_count conflict_count"
  eval "$(parse_lists "$1" 2>/dev/null)"
  echo "$LIST_BAD $(printf '%s' "$FREEZE_CONFLICT" | wc -w)"
}

# 名单备份: 每次成功写入后同步到模块 data/list.bak (覆盖安装迁移的恢复源)
sync_bak() {
  b="${LIST_BAK:-$MODDIR/data/list.bak}"
  mkdir -p "$(dirname "$b")" 2>/dev/null
  cp "$CONF" "$b" 2>/dev/null
}

do_add() {
  g="$1"; t="$2"
  [ -f "$CONF" ] || { echo "ERR:iofail"; return 1; }
  err=$(validate "$g" "$t") || { echo "ERR:$err"; return 1; }
  grep -qE "^[[:space:]]*$g[[:space:]]+$t[[:space:]]*$" "$CONF" 2>/dev/null \
    && { echo "ERR:dup"; return 1; }
  [ "$(wc -l < "$CONF")" -ge "$MAX_LINES" ] && { echo "ERR:toomany"; return 1; }
  # D4 后端 (与 awk 同语义: 整串比较); KILL 不参与 D4
  case "$g" in
    WHITE)  grep -qE "^[[:space:]]*FREEZE[[:space:]]+$t[[:space:]]*$" "$CONF" 2>/dev/null \
              && { echo "ERR:conflict"; return 1; };;
    FREEZE) grep -qE "^[[:space:]]*WHITE[[:space:]]+$t[[:space:]]*$" "$CONF" 2>/dev/null \
              && { echo "ERR:conflict"; return 1; };;
  esac
  tmp="$CONF.tmp.$$"
  awk -v g="$g" -v t="$t" '
    { lines[NR]=$0; if ($1==g) lastg=NR; if ($0 ~ /^[[:space:]]*}[[:space:]]*$/) lastb=NR }
    END {
      ins=(lastg>0)?lastg+1:((lastb>0)?lastb:NR+1)
      for(i=1;i<=NR;i++){ if(i==ins) print g" "t; print lines[i] }
      if(ins==NR+1) print g" "t
    }' "$CONF" > "$tmp" 2>/dev/null || { rm -f "$tmp"; echo "ERR:iofail"; return 1; }
  s0=$(conf_stats "$CONF"); b0=${s0% *}; c0=${s0#* }
  s1=$(conf_stats "$tmp");  b1=${s1% *}; c1=${s1#* }
  if [ "$b1" -gt "$b0" ] || [ "$c1" -gt "$c0" ]; then
    rm -f "$tmp"; echo "ERR:parsefail"; return 1
  fi
  mv -f "$tmp" "$CONF" || { rm -f "$tmp"; echo "ERR:iofail"; return 1; }
  sync_bak
  # WARN 语义 = bridge 未产出文件 (chown 等非致命失败不告警, 文件已在即 hook 可读)
  if ! guard_bridge 2>/dev/null && [ ! -f "$BRIDGE" ]; then
    echo "OK"; echo "WARN:bridge"; return 0
  fi
  echo "OK"
}

do_del() {
  g="$1"; t="$2"
  [ -f "$CONF" ] || { echo "ERR:iofail"; return 1; }
  err=$(validate "$g" "$t") || { echo "ERR:$err"; return 1; }
  grep -qE "^[[:space:]]*$g[[:space:]]+$t[[:space:]]*$" "$CONF" 2>/dev/null \
    || { echo "ERR:nomatch"; return 1; }
  tmp="$CONF.tmp.$$"
  awk -v g="$g" -v t="$t" '$1==g && $2==t { next } { print }' "$CONF" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; echo "ERR:iofail"; return 1; }
  s0=$(conf_stats "$CONF"); b0=${s0% *}; c0=${s0#* }
  s1=$(conf_stats "$tmp");  b1=${s1% *}; c1=${s1#* }
  if [ "$b1" -gt "$b0" ] || [ "$c1" -gt "$c0" ]; then
    rm -f "$tmp"; echo "ERR:parsefail"; return 1
  fi
  mv -f "$tmp" "$CONF" || { rm -f "$tmp"; echo "ERR:iofail"; return 1; }
  sync_bak
  # WARN 语义 = bridge 未产出文件 (chown 等非致命失败不告警, 文件已在即 hook 可读)
  if ! guard_bridge 2>/dev/null && [ ! -f "$BRIDGE" ]; then
    echo "OK"; echo "WARN:bridge"; return 0
  fi
  echo "OK"
}
if [ "${LISTEDIT_SOURCED:-}" != 1 ]; then
  case "${1:-}" in
    add) if [ $# -eq 3 ]; then do_add "$2" "$3"; else echo "ERR:badfmt"; fi;;
    del) if [ $# -eq 3 ]; then do_del "$2" "$3"; else echo "ERR:badfmt"; fi;;
    *)   echo "ERR:badfmt";;
  esac
fi
