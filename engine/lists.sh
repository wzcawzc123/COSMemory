#!\/system\/bin\/sh
# engine\/lists.sh — 名单解析(容错: 非法行跳过计数不连坐; WHITE∩FREEZE 双向拒绝 D4)
parse_lists() {
  awk '
    BEGIN { w=""; k=""; f=""; bad=0; detail="" }
    /^[[:space:]]*(#|\{|})/ || /^[[:space:]]*$/ { next }
    {
      action=$1; target=$2
      if (action=="WHITE" && target ~ /^[a-zA-Z][a-zA-Z0-9._]+(:.+)?$/) w=w target " "
      else if (action=="KILL" && target ~ /^[a-zA-Z][a-zA-Z0-9._]+:.+$/) k=k target " "
      else if (action=="FREEZE" && target ~ /^[a-zA-Z][a-zA-Z0-9._]+(:.+)?$/) {
        if (!(target in fzset)) { fzset[target]=1; f=f target " " }
      }
      else { bad++; detail=detail "L" NR ":" $0 "|" }
    }
    END {
      sub(/ $/, "", w); sub(/ $/, "", k); sub(/ $/, "", f)
      conflict=""
      nf = split(f, fa, " ")
      for (i = 1; i <= nf; i++) {
        nw = split(w, wa, " "); hit = 0
        for (j = 1; j <= nw; j++) if (wa[j] == fa[i]) { hit = 1; break }
        if (hit) conflict = conflict fa[i] " "
      }
      if (conflict != "") {
        sub(/ $/, "", conflict)
        out = ""; nw = split(w, wa, " ")
        for (j = 1; j <= nw; j++) if (index(" " conflict " ", " " wa[j] " ") == 0) out = out wa[j] " "
        sub(/ $/, "", out); w = out
        out = ""; nf = split(f, fa, " ")
        for (j = 1; j <= nf; j++) if (index(" " conflict " ", " " fa[j] " ") == 0) out = out fa[j] " "
        sub(/ $/, "", out); f = out
        nc = split(conflict, ca, " ")
        for (i = 1; i <= nc; i++) { bad++; detail = detail "conflict:" ca[i] "|" }
      }
      printf "WHITE_LIST=\"%s\"\nKILL_LIST=\"%s\"\nFREEZE_LIST=\"%s\"\nLIST_BAD=%d\nLIST_BAD_DETAIL=\"%s\"\nFREEZE_CONFLICT=\"%s\"\n", w, k, f, bad, detail, conflict
    }' "$1"
}
