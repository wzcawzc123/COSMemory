#!/system/bin/sh
# engine/lists.sh — 名单解析(容错: 非法行跳过计数, 不连坐)
parse_lists() {
  awk '
    BEGIN { w=""; k=""; f=""; bad=0; detail="" }
    /^[[:space:]]*(#|\{|})/ || /^[[:space:]]*$/ { next }
    {
      action=$1; target=$2
      if (action=="WHITE" && target ~ /^[a-zA-Z][a-zA-Z0-9._]+(:.+)?$/) w=w target " "
      else if (action=="KILL" && target ~ /^[a-zA-Z][a-zA-Z0-9._]+:.+$/) k=k target " "
      else if (action=="FREEZE" && target ~ /^[a-zA-Z][a-zA-Z0-9._]+(:.+)?$/) f=f target " "
      else { bad++; detail=detail "L" NR ":" $0 "|" }
    }
    END {
      sub(/ $/, "", w); sub(/ $/, "", k); sub(/ $/, "", f)
      printf "WHITE_LIST=\"%s\"\nKILL_LIST=\"%s\"\nFREEZE_LIST=\"%s\"\nLIST_BAD=%d\nLIST_BAD_DETAIL=\"%s\"\n", w, k, f, bad, detail
    }' "$1"
}
