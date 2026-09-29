#!/system/bin/sh
# engine/policy.sh — 决策纯函数: 快照 + 名单 → 动作行
# 保护态(任何动作永不触碰): fg vis prcp prev pers psvc — spec §3 全局约束
# 注: svc/svcb 不在保护表(KILL 目标多为 svc 态子进程, 保护则 KILL 名单失效)
PROTECTED="fg vis prcp prev pers psvc"

is_protected() {
  case " $PROTECTED " in *" $1 "*) return 0;; *) return 1;; esac
}

plan_keepalive() {
  # $1=快照文件 $2=WHITE_LIST $3=target_adj
  # 白名单包 + 已退后台(cch*) → KEEPADJ; WHITE 无后缀时匹配整包及其子进程
  while IFS='|' read -r state proc pid pkg; do
    [ -z "$pkg" ] && continue
    case "$state" in cch*) ;; *) continue;; esac
    matched=0
    for w in $2; do
      [ "$matched" = 1 ] && break
      if [ "$pkg" = "$w" ]; then matched=1; continue; fi
      case "$w" in
        *:*) ;;
        *) case "$pkg" in "$w":*) matched=1;; esac ;;
      esac
    done
    [ "$matched" = 1 ] && echo "KEEPADJ $pid $pkg $3"
  done < "$1"
}

plan_reclaim() {
  # $1=快照文件 $2=KILL_LIST $3=cooldown目录 $4=单轮上限 $5=WHITE_LIST(spec §3三重检查: 白名单不杀)
  n=0
  while IFS='|' read -r state proc pid pkg; do
    [ -z "$pkg" ] && continue
    hit=""
    for k in $2; do [ "$pkg" = "$k" ] && { hit=$k; break; }; done
    [ -z "$hit" ] && continue
    if is_protected "$state"; then echo "SKIP protected_state $pkg"; continue; fi
    for w in $5; do
      if [ "$pkg" = "$w" ] || { case "$w" in *:*) false;; *) case "$pkg" in "$w":*) true;; *) false;; esac;; esac; }; then
        echo "SKIP whitelist $pkg"; hit=""; break
      fi
    done
    [ -z "$hit" ] && continue
    if [ -f "$3/$pid" ]; then
      age=$(( $(date +%s) - $(cat "$3/$pid") ))
      [ "$age" -lt 60 ] && { echo "SKIP cooldown $pkg"; continue; }
    fi
    if [ "$n" -ge "$4" ]; then echo "SKIP cap $pkg"; continue; fi
    echo "KILL $pid $pkg"; n=$((n+1))
  done < "$1"
}
