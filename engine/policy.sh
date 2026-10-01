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

# ===== 激进回收 (spec 2026-10-01, R1-R4) =====
# reclaim_should_fire <now> <agg> <psi_t> <floor_kb> <cool_sec> <cap_psi> <psi_file> <mem_file> <last_file>
# R2: AND+降级+节流; 读失败一律0 (fail-safe)
reclaim_should_fire() {
  now=$1; agg=$2; psi_t=$3; floor=$4; cool=$5; cap=$6; psif=$7; memf=$8; lastf=$9
  [ "$agg" = "1" ] || { echo 0; return 0; }
  if [ -f "$lastf" ]; then
    last=$(cat "$lastf" 2>/dev/null); [ -n "$last" ] || last=0
    [ $(( now - last )) -lt "$cool" ] && { echo 0; return 0; }
  fi
  ma=$(awk '/MemAvailable/{print int($2/1024); exit}' "$memf" 2>/dev/null)
  [ -n "$ma" ] || { echo 0; return 0; }
  [ "$ma" -lt "$floor" ] || { echo 0; return 0; }
  if [ "$cap" = "1" ]; then
    p=$(awk '/some/{for(i=1;i<=NF;i++) if ($i ~ /^avg10=/) {split($i,a,"="); print a[2]; exit}}' "$psif" 2>/dev/null)
    [ -n "$p" ] || { echo 0; return 0; }
    hit=$(awk -v v="$p" -v t="$psi_t" 'BEGIN{print ((v+0)>(t+0)) ? 1 : 0}')
    [ "$hit" = "1" ] || { echo 0; return 0; }
  fi
  echo 1
}

# depth_match <state> <depth> -> exit 0匹配
depth_match() {
  case "$2" in
    cached)   case "$1" in cch*) return 0;; *) return 1;; esac ;;
    previous) case "$1" in cch*|prev*) return 0;; *) return 1;; esac ;;
    service)  case "$1" in cch*|prev*|svc|svcb) return 0;; *) return 1;; esac ;;
    *) return 1 ;;
  esac
}

# plan_aggressive <parsed快照> <WHITE_LIST> <depth> <cap> -> stdout: RECLAIM pid pkg
# R3按lru行序(≈adj从高到低) R4三重保护继承
plan_aggressive() {
  n=0
  while IFS='|' read -r state proc pid pkg; do
    [ -z "$pkg" ] && continue
    depth_match "$state" "$3" || continue
    is_protected "$state" && continue
    w_hit=0
    for w in $2; do
      if [ "$pkg" = "$w" ]; then w_hit=1; break; fi
      case "$w" in *:*) ;; *) case "$pkg" in "$w":*) w_hit=1; break;; esac;; esac
    done
    [ "$w_hit" = 1 ] && continue
    echo "RECLAIM $pid $pkg"; n=$((n+1))
    [ "$n" -ge "$4" ] && break
  done < "$1"
}
