# ColorOS 内存管理模块 v0.1（引擎核心）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付可安装的 KSU/Magisk 模块最小内核：快照采集 → 名单决策 → 执行（保活/杀进程），并通过 L1/L2 因果验证。

**Architecture:** 纯 shell 引擎（无二进制、无 hook），事件驱动状态机：`dumpsys activity lru` 快照（12ms）+ meminfo/PSI（19ms）→ 纯函数决策层 → 执行层写 adj/杀进程 → 单向追加 stats.log。快照/名单/决策三层全部纯函数化以便单测，执行层与主循环靠真机验证。

**Tech Stack:** POSIX/ash shell（busybox 兼容）、awk、标准 Android 工具（dumpsys/getprop/ps/kill）

**Spec:** `docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md`

## Global Constraints

- 引擎只读快照，**禁止**遍历 `/proc/[0-9]*` 全表（基准：3200ms+ vs dumpsys 12ms）
- 每轮全开销 ≤ 30ms（dumpsys + meminfo/PSI 实测值）
- 解析未知状态码 → 归入保守区（不杀不改）；dumpsys 解析命中率 <50% → 停止一切写操作（宁停不错）
- 保活 adj 默认 200；激进回收默认关；单轮击杀上限 5；同进程冷却 60s
- 永不触碰：pers/fg/vis/prcp/prev 状态进程、persistent 应用、白名单、前台
- 出厂 KILL 名单只收录逐条实测项；FREEZE 出厂空
- 兼容 KSU（/data/adb/ksu/bin/busybox）+ Magisk（/data/adb/magisk/busybox）+ Apatch（/data/adb/ap/），`ASH_STANDALONE=1`
- 全部动作可回滚：写 adj/属性前记录 before 值
- 署名：NOTICE 标明基于 HChai/OneB1ank A1Memory 二次开发，GPLv3
- 测试框架用自研 `tests/run_tests.sh`（设备无 bats），测试必须先红后绿
- 模块 id：`COSMemory`（构建时可改，测试用此值）；模块目录 `/sdcard/Android/COSMemory/`

## File Structure

```
repo/
├── engine/
│   ├── snapshot.sh    # 采集 + 解析（lru_parse/mem_parse 纯函数 + capture 主入口）
│   ├── lists.sh       # 名单解析（parse_lists 容错纯函数）
│   ├── policy.sh      # 决策纯函数（plan_keepalive/plan_reclaim 输出动作行）
│   ├── exec.sh        # 执行层（apply_actions 写 adj/杀进程，记录 before）
│   ├── probe.sh       # cap_probe 能力探测（启动跑一次，结果落盘）
│   └── memory.sh      # 主循环状态机 + 看门狗（service.sh 调用）
├── tests/
│   ├── run_tests.sh   # 测试运行器（assert_eq/assert_match + 汇总）
│   ├── fixtures/      # 真实 dumpsys lru 样本（本机采集）
│   ├── test_snapshot.sh
│   ├── test_lists.sh
│   ├── test_policy.sh
│   └── test_e2e.sh    # 真机 L1/L2（手动触发，不算单元测试）
├── config/名单列表.conf
├── config/memory.json
├── service.sh
├── customize.sh
├── uninstall.sh
├── module.prop
└── NOTICE
```

动作行协议（policy → exec 的接口，全文统一）：
```
KEEPADJ <pid> <pkg> <target_adj>   # 例: KEEPADJ 15942 com.tencent.mm 200
KILL <pid> <pkg>                   # 例: KILL 25403 com.tencent.mm:appbrand1
SKIP <reason> <pkg>                # 审计行，不执行（例: SKIP cooldown com.x）
```

---

### Task 1: 测试框架 + dumpsys 夹具

**Files:**
- Create: `tests/run_tests.sh`
- Create: `tests/fixtures/lru_sample.txt`

**Interfaces:**
- Produces: `run_tests.sh` 提供 `t_assert "name" "expected" "actual"`、`t_match "name" "regex" "actual"`、`t_done`（退出码=失败数）；所有后续测试脚本 source 它

- [ ] **Step 1: 采集真实夹具**

```bash
dumpsys activity lru > tests/fixtures/lru_sample.txt
wc -l tests/fixtures/lru_sample.txt   # 预期 ~127 行
grep -c '^ *#[0-9]*:' tests/fixtures/lru_sample.txt  # 预期 ≥100
```

- [ ] **Step 2: 写测试运行器**

```sh
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
```

- [ ] **Step 3: 框架自测（必须先抓到失败）**

```bash
sh -c '. tests/run_tests.sh; t_assert "eq" "1" "1"; t_assert "ne" "1" "2"; t_done'
```
预期：`pass=1 fail=1`，退出码 1

- [ ] **Step 4: Commit**

```bash
git add tests/ && git commit -m "test: 断言框架 + 真实 dumpsys lru 夹具"
```

---

### Task 2: snapshot.sh — lru 解析器（纯函数）

**Files:**
- Create: `engine/snapshot.sh`
- Create: `tests/test_snapshot.sh`

**Interfaces:**
- Produces:
  - `lru_parse <文件>` → 每行 `state|procstate|pid|pkg`（如 `cch|SVC|15942|com.tencent.mm`）；无法解析的 `#` 行不输出
  - `lru_stats <文件>` → 输出可 eval 的 `LRU_TOTAL=..;LRU_PARSED=..`（哨兵用）
  - `snapshot_collect` → 调 dumpsys 写 `$WORKDIR/snapshot.txt`
- Consumes: 无

- [ ] **Step 1: 写失败测试**

```sh
#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/snapshot.sh"
F="$D/fixtures/lru_sample.txt"
OUT=$(lru_parse "$F")

LINE=$(echo "$OUT" | grep '|com.tencent.mm$' | head -1)
t_match "微信主进程解析" "15942|com.tencent.mm" "$LINE"
t_match "前台状态保留" "fg|" "$(echo "$OUT" | grep 'com.ss.android.ugc.aweme$' | head -1)"
t_match "子进程冒号保留" "com.tencent.mm:appbrand1" "$OUT"
t_match "无表头污染" "" "$(echo "$OUT" | grep 'ACTIVITY MANAGER')"
eval "$(lru_stats "$F")"
t_assert "总数>100" "yes" "$([ "$LRU_TOTAL" -gt 100 ] && echo yes || echo no)"
t_assert "解析率>=50%" "yes" "$([ $((LRU_PARSED*100/LRU_TOTAL)) -ge 50 ] && echo yes || echo no)"
t_done
```

- [ ] **Step 2: 运行确认失败**

```bash
sh tests/test_snapshot.sh
```
预期：`lru_parse: not found` 类错误，退出码非 0

- [ ] **Step 3: 实现**

```sh
#!/system/bin/sh
# engine/snapshot.sh — 快照采集与解析
WORKDIR="${WORKDIR:-/data/local/tmp/cosmem}"

lru_parse() {
  awk '
    /^[[:space:]]*#[0-9]+:/ {
      line=$0
      sub(/^[[:space:]]*#[0-9]+:[[:space:]]+/, "", line)
      if (match(line, /[0-9]+:[a-zA-Z]/)) {
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
```

- [ ] **Step 4: 运行确认通过**

```bash
sh tests/test_snapshot.sh
```
预期：`pass=6 fail=0`，退出码 0

- [ ] **Step 5: Commit**

```bash
git add engine/snapshot.sh tests/test_snapshot.sh
git commit -m "feat: dumpsys lru 解析器 + 单测"
```

---

### Task 3: lists.sh — 名单解析（容错）

**Files:**
- Create: `engine/lists.sh`
- Create: `tests/test_lists.sh`
- Create: `config/名单列表.conf`（出厂保守名单）

**Interfaces:**
- Produces:
  - `parse_lists <文件>` → 三类各一变量前缀输出，可 eval：`WHITE_LIST="pkg1 pkg2 ..."; KILL_LIST="proc1 ..."; FREEZE_LIST=""` 及 `LIST_BAD=行数`
  - 格式：`WHITE/KILL/FREEZE + 空格 + 包名[:进程]`，`#` 注释，`{}` 花括号忽略，非法行计数不中断
- Consumes: 无

- [ ] **Step 1: 写失败测试**

```sh
#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/lists.sh"

cat > /tmp/tl.conf << 'CONF'
# 注释行
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
KILL com.tencent.mm:toolsmp
FREEZE com.bloat.app
bad_line_without_action
WHITE
KILL com.a:b
}
CONF
eval "$(parse_lists /tmp/tl.conf)"
t_assert "白名单2个" "com.tencent.mm com.tencent.mobileqq" "$WHITE_LIST"
t_assert "KILL带子进程" "com.tencent.mm:toolsmp" "$KILL_LIST"
t_assert "FREEZE" "com.bloat.app" "$FREEZE_LIST"
t_assert "非法行计数=2" "2" "$LIST_BAD"
t_assert "花括号不算非法" "" "$(echo "$LIST_BAD_DETAIL | grep -c '{}')"

# 出厂名单必须可解析且 KILL 只含实测项
eval "$(parse_lists "$D/../config/名单列表.conf")"
t_assert "出厂名单零非法行" "0" "$LIST_BAD"
t_match "出厂含微信白名单" "com.tencent.mm" "$WHITE_LIST"
t_done
```

- [ ] **Step 2: 运行确认失败**

```bash
sh tests/test_lists.sh
```
预期：`parse_lists: not found`

- [ ] **Step 3: 实现**

```sh
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
```

注意 KILL 要求必须带 `:后缀`（杀整包走 FREEZE），这是协议约束——测试 Step1 第5行 `KILL com.a:b` 合法、`WHITE`（无目标）非法。

- [ ] **Step 4: 运行确认通过**

```bash
sh tests/test_lists.sh
```
预期：`pass=6 fail=0`

- [ ] **Step 5: 写出厂名单（保守）**

```conf
# COSMemory 出厂名单 — 保守策略
# WHITE: 保活 | KILL: 点名杀子进程(必须带:后缀) | FREEZE: 整包封杀(出厂空)
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
WHITE com.ss.android.ugc.aweme
}
```

⚠️ 此处 KILL 出厂**留空**——老 A1 名单是 2023 年的，条目必须逐条实测（Task 7 里做），未测不发布。

- [ ] **Step 6: Commit**

```bash
git add engine/lists.sh tests/test_lists.sh config/
git commit -m "feat: 名单容错解析器 + 保守出厂名单"
```

---

### Task 4: policy.sh — 决策纯函数（动作行生成）

**Files:**
- Create: `engine/policy.sh`
- Create: `tests/test_policy.sh`

**Interfaces:**
- Produces:
  - `plan_keepalive <snapshot行流> <WHITE_LIST> <target_adj>` → 动作行 `KEEPADJ pid pkg adj`（只对 state 为 `cch*` 的白名单进程输出）
  - `plan_reclaim <snapshot行流> <KILL_LIST> <cooldown文件> <上限>` → 动作行 `KILL pid pkg` / `SKIP reason pkg`
  - `is_protected <state>` → 退出码（fg/vis/prcp/prev/pers/psvc/svc/svcb = 保护）
- Consumes: Task 2 的 `state|procstate|pid|pkg` 流、Task 3 的名单变量

**保护状态表**（spec 第 3 段，写死在 policy）：
`fg vis prcp prev pers psvc svc svcb` → 保护；`cch cch+ cch+N` → 可回收区

- [ ] **Step 1: 写失败测试**

```sh
#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/policy.sh"

SNAP='cch|SVC|15942|com.tencent.mm
cch+5|SVC|9751|com.tencent.mobileqq
fg|TOP|6213|com.ss.android.ugc.aweme
vis|BFGS|5610|com.android.launcher
svc|SVC|17111|com.tencent.mm:push
cch|CAC|16879|com.coolapk.market'

# 1) 保活: 只对 cch 态白名单进程
OUT=$(echo "$SNAP" | plan_keepalive /dev/stdin "com.tencent.mm com.coolapk.market" 200)
t_assert "保活2个" "KEEPADJ 15942 com.tencent.mm 200
KEEPADJ 16879 com.coolapk.market 200" "$OUT"

# 2) 前台/可见不在保活范围
t_assert "前台不保活" "" "$(echo "$SNAP" | plan_keepalive /dev/stdin "com.ss.android.ugc.aweme" 200)"

# 3) 回收: KILL 名单命中 svc 态
rm -f /tmp/tc_cool
OUT=$(echo "$SNAP" | plan_reclaim /dev/stdin "com.tencent.mm:push" /tmp/tc_cool 5)
t_assert "KILL命中" "KILL 17111 com.tencent.mm:push" "$OUT"

# 4) 保护态进程即使在名单也不杀
t_assert "白名单进程不被KILL" "" "$(echo "$SNAP" | plan_reclaim /dev/stdin "com.tencent.mm" /tmp/tc_cool 5)"

# 5) 冷却生效
date +%s > /tmp/tc_cool/17111 2>/dev/null || { mkdir -p /tmp/tc_cool; date +%s > /tmp/tc_cool/17111; }
OUT=$(echo "$SNAP" | plan_reclaim /dev/stdin "com.tencent.mm:push" /tmp/tc_cool 5)
t_match "冷却跳过" "SKIP cooldown com.tencent.mm:push" "$OUT"
rm -rf /tmp/tc_cool

# 6) 上限: 3条KILL名单+上限2
SNAP2='cch|CAC|111|a.x:p1
cch|CAC|222|a.x:p2
cch|CAC|333|a.x:p3'
OUT=$(echo "$SNAP2" | plan_reclaim /dev/stdin "a.x:p1 a.x:p2 a.x:p3" /tmp/tc_none 2)
t_assert "上限生效" "KILL 111 a.x:p1
KILL 222 a.x:p2
SKIP cap a.x:p3" "$OUT"
t_done
```

- [ ] **Step 2: 运行确认失败**

```bash
sh tests/test_policy.sh
```
预期：`plan_keepalive: not found`

- [ ] **Step 3: 实现**

```sh
#!/system/bin/sh
# engine/policy.sh — 决策纯函数: 快照流 + 名单 → 动作行

PROTECTED="fg vis prcp prev pers psvc svc svcb"

is_protected() {
  case " $PROTECTED " in (*" $1 "*) return 0;; (*) return 1;; esac
}

plan_keepalive() {
  # $1=快照文件 $2=WHITE_LIST(空格分隔) $3=target_adj
  # 白名单 + 已退后台(cch*) → KEEPADJ
  while IFS='|' read -r state proc pid pkg; do
    [ -z "$pkg" ] && continue
    case "$state" in cch*) ;; (*) continue;; esac
    for w in $2; do
      if [ "$pkg" = "$w" ] || [ "${pkg%%:*}" = "${w%%:*}" ] && [ "${w#*:}" = "$w" ]; then
        echo "KEEPADJ $pid $pkg $3"; break
      fi
    done
  done < "$1"
}

plan_reclaim() {
  # $1=快照文件 $2=KILL_LIST $3=cooldown目录 $4=单轮上限
  # 只杀: KILL名单命中 且 非保护态 且 冷却外; 上限超出 → SKIP cap
  n=0
  while IFS='|' read -r state proc pid pkg; do
    [ -z "$pkg" ] && continue
    hit=""
    for k in $2; do [ "$pkg" = "$k" ] && { hit=$k; break; }; done
    [ -z "$hit" ] && continue
    if is_protected "$state"; then echo "SKIP protected_state $pkg"; continue; fi
    if [ -f "$3/$pid" ]; then
      age=$(( $(date +%s) - $(cat "$3/$pid") ))
      [ "$age" -lt 60 ] && { echo "SKIP cooldown $pkg"; continue; }
    fi
    if [ "$n" -ge "$4" ]; then echo "SKIP cap $pkg"; continue; fi
    echo "KILL $pid $pkg"; n=$((n+1))
  done < "$1"
}
```

⚠️ Task4 Step1 第1个断言的输出顺序依赖快照行序（微信在前），测试夹具已保证；若实现改为排序输出需同步改断言。

- [ ] **Step 4: 运行确认通过**

```bash
sh tests/test_policy.sh
```
预期：`pass=6 fail=0`

- [ ] **Step 5: Commit**

```bash
git add engine/policy.sh tests/test_policy.sh
git commit -m "feat: 保活/回收决策纯函数 + 保护态与冷却上限单测"
```

---

### Task 5: exec.sh — 执行层（写 adj / 杀进程 / 记录）

**Files:**
- Create: `engine/exec.sh`
- Create: `tests/test_exec.sh`

**Interfaces:**
- Produces:
  - `apply_actions <动作行流> <state文件>` → 逐行执行；每成功动作写 state 文件（`adj_<pid>` 记录 before 值）+ 追加 stats 行；返回 `APPLIED=<n> KILLED=<m> FAILED=<f>`
  - `restore_state <state文件>` → 卸载还原（把 before 值写回）
- Consumes: Task 4 的动作行协议

**安全规则（spec 第 3 段）**：
- KILL 前三重验证：`/proc/<pid>` 存在 → cmdline 与动作行 pkg 一致（防 PID 复用）→ 非白名单
- 写 adj 前先读 before 值存 state 文件；写后读回验证，不一致记 FAILED

- [ ] **Step 1: 写失败测试**

```sh
#!/system/bin/sh
D=$(dirname "$0"); . "$D/run_tests.sh"; . "$D/../engine/exec.sh"

# 用自进程当"被保活对象" — 安全可测
SELF=$$
STATE=/tmp/te_state; rm -rf $STATE; mkdir -p $STATE

OUT=$(printf 'KEEPADJ %s my.test.proc 200\n' "$SELF" | apply_actions /dev/stdin "$STATE" 2>/dev/null)
t_match "KEEPADJ计数" "APPLIED=1" "$OUT"
t_assert "adj已写" "200" "$(cat /proc/$SELF/oom_score_adj)"
t_assert "before已记录" "$(cat /proc/$SELF/oom_score_adj.orig 2>/dev/null || echo none)" \
  "$(grep -o 'orig=[0-9-]*' $STATE/adj_$SELF | cut -d= -f2)"

# PID复用防线: KILL 一个 cmdline 不匹配的 pid → 拒绝
OUT=$(printf 'KILL %s wrong.pkg\n' "$STATE" 2>/dev/null; printf 'KILL 1 wrong.pkg\n' | apply_actions /dev/stdin "$STATE" 2>/dev/null)
t_match "PID/cmdline不符拒绝" "FAILED" "$OUT"

# 还原
restore_state "$STATE"
t_assert "还原后不再=200" "yes" "$([ "$(cat /proc/$SELF/oom_score_adj)" != 200 ] && echo yes || echo no || echo yes)"
t_done
```

注：测试里 `/proc/$SELF/oom_score_adj.orig` 那条断言按实现取舍——state 文件是唯一权威，测试以 `restore` 结果为准；若实现不产生 `.orig` 文件，把该断言改为只验证 `state/adj_<pid>` 内容含 `orig=`。

- [ ] **Step 2: 运行确认失败**

```bash
sh tests/test_exec.sh
```
预期：`apply_actions: not found`

- [ ] **Step 3: 实现**

```sh
#!/system/bin/sh
# engine/exec.sh — 执行层(带安全验证与回滚记录)

apply_actions() {
  # $1=动作行文件 $2=state目录; 输出: APPLIED/KILLED/FAILED 计数
  ap=0; ki=0; fa=0
  while read -r op a b c; do
    case "$op" in
    KEEPADJ)
      pid=$a; pkg=$b; tgt=$c
      [ -d "/proc/$pid" ] || { fa=$((fa+1)); continue; }
      # cmdline 校验(防PID复用)
      cur=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
      case "$cur" in (*"$pkg"*) ;; (*) fa=$((fa+1)); continue;; esac
      before=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
      [ "$before" = "$tgt" ] && continue          # 无变化不写
      [ ! -f "$2/adj_$pid" ] && echo "orig=$before pkg=$pkg" > "$2/adj_$pid"
      echo "$tgt" > /proc/$pid/oom_score_adj 2>/dev/null || { fa=$((fa+1)); continue; }
      after=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
      if [ "$after" = "$tgt" ]; then ap=$((ap+1)); log_stat "KEEPADJ $pkg $before->$tgt"
      else fa=$((fa+1)); fi
      ;;
    KILL)
      pid=$a; pkg=$b
      [ -d "/proc/$pid" ] || { fa=$((fa+1)); continue; }
      cur=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
      case "$cur" in (*"$pkg"*) ;; (*) fa=$((fa+1)); continue;; esac
      if kill -9 "$pid" 2>/dev/null; then ki=$((ki+1)); log_stat "KILL $pkg"
      else fa=$((fa+1)); fi
      ;;
    SKIP|'#'*) : ;;
    *) fa=$((fa+1)) ;;
    esac
  done < "$1"
  echo "APPLIED=$ap KILLED=$ki FAILED=$fa"
}

restore_state() {
  # $1=state目录: 把 orig 值写回
  for f in "$1"/adj_*; do
    [ -f "$f" ] || continue
    orig=$(sed -n 's/^orig=//p' "$f"); pid=${f##*adj_}
    [ -n "$orig" ] && [ -d "/proc/$pid" ] && echo "$orig" > /proc/$pid/oom_score_adj 2>/dev/null
  done
}

log_stat() { echo "[$(date '+%F %T')] $*" >> "${STATS_LOG:-/data/local/tmp/cosmem/stats.log}"; }
```

- [ ] **Step 4: 运行确认通过**

```bash
sh tests/test_exec.sh
```
预期：`pass=4 fail=0`（或按 Step1 注调整后的断言数）

- [ ] **Step 5: Commit**

```bash
git add engine/exec.sh tests/test_exec.sh
git commit -m "feat: 执行层(PID校验/回滚记录/stats) + 单测"
```

---

### Task 6: probe.sh + memory.sh 主循环 + service.sh 看门狗

**Files:**
- Create: `engine/probe.sh`、`engine/memory.sh`
- Create: `service.sh`

**Interfaces:**
- Produces:
  - `cap_probe` → 写 `$WORKDIR/caps.conf`：`CAP_LRU / CAP_LRU_FALLBACK / CAP_PSI / CAP_ADJ / CAP_LMKD_CFG / CAP_OPLUS`
  - `memory.sh` 主循环：`snapshot → 哨兵 → policy → exec → stats`（spec 第 3 段状态机）
  - `service.sh`：busybox 探测（ksu/magisk/ap）+ 启动 + 30s 看门狗
- Consumes: Task 2/3/4/5 全部接口

- [ ] **Step 1: 实现 probe.sh（能力探测，不猜版本）**

```sh
#!/system/bin/sh
# engine/probe.sh — 启动时能力探测; 缺失→功能降级且面板可见
cap_probe() {
  mkdir -p "$WORKDIR"; C="$WORKDIR/caps.conf"; : > "$C"
  dumpsys activity lru 2>/dev/null | grep -q '^ *#[0-9]*:' \
    && echo "CAP_LRU=1" >> "$C" || echo "CAP_LRU=0" >> "$C"
  dumpsys activity processes 2>/dev/null | grep -qE 'ProcessRecord|APP ' \
    && echo "CAP_LRU_FALLBACK=1" >> "$C" || echo "CAP_LRU_FALLBACK=0" >> "$C"
  [ -r /proc/pressure/memory ] && echo "CAP_PSI=1" >> "$C" || echo "CAP_PSI=0" >> "$C"
  my=$$; b=$(cat /proc/$my/oom_score_adj); echo "$b" > /proc/$my/oom_score_adj 2>/dev/null
  [ "$(cat /proc/$my/oom_score_adj)" = "$b" ] \
    && echo "CAP_ADJ=1" >> "$C" || echo "CAP_ADJ=0" >> "$C"
  cmd device_config get lmkd_native thrashing_limit_critical >/dev/null 2>&1 \
    && echo "CAP_LMKD_CFG=1" >> "$C" || echo "CAP_LMKD_CFG=0" >> "$C"
  getprop persist.sys.lmk.oplus.kill_memleak_process | grep -q . \
    && echo "CAP_OPLUS=1" >> "$C" || echo "CAP_OPLUS=0" >> "$C"
}
```

- [ ] **Step 2: 实现 memory.sh 主循环**

```sh
#!/system/bin/sh
# engine/memory.sh — SLEEP→SNAPSHOT→SENTINEL→POLICY→EXEC→SLEEP
MODDIR=$(dirname "$0")/..
. "$MODDIR/engine/snapshot.sh"; . "$MODDIR/engine/lists.sh"
. "$MODDIR/engine/policy.sh";   . "$MODDIR/engine/exec.sh"
. "$MODDIR/engine/probe.sh"

WORKDIR="${WORKDIR:-/data/local/tmp/cosmem}"
STATS_LOG="${STATS_LOG:-$WORKDIR/stats.log}"; export STATS_LOG
KEEPADJ_TARGET="${KEEPADJ_TARGET:-200}"; MAX_KILL="${MAX_KILL:-5}"
mkdir -p "$WORKDIR/cool"; cap_probe; . "$WORKDIR/caps.conf"
[ "$CAP_LRU" = 1 ] || { echo "halt: no lru source" >> "$STATS_LOG"; exit 9; }

last_full=0
while :; do
  now=$(date +%s)
  [ $((now - last_full)) -ge 60 ] && full=1 && last_full=$now || full=0
  snapshot_collect
  eval "$(lru_stats "$WORKDIR/snapshot.txt")"
  if [ "$LRU_TOTAL" -gt 0 ]; then rate=$((LRU_PARSED*100/LRU_TOTAL)); else rate=0; fi
  if [ "$rate" -lt 50 ]; then   # 哨兵: 宁停不错
    echo "[$(date '+%F %T')] SENTINEL HALT rate=$rate" >> "$STATS_LOG"
    sleep 30; continue
  fi
  eval "$(parse_lists "${LIST_PATH:-/sdcard/Android/COSMemory/名单列表.conf}")"
  [ "${LIST_BAD:-0}" -gt 0 ] && echo "LIST_BAD=$LIST_BAD" >> "$STATS_LOG"
  plan_keepalive "$WORKDIR/snapshot.txt" "$WHITE_LIST" "$KEEPADJ_TARGET" > "$WORKDIR/acts"
  plan_reclaim   "$WORKDIR/snapshot.txt" "$KILL_LIST" "$WORKDIR/cool" "$MAX_KILL" >> "$WORKDIR/acts"
  grep '^KILL ' "$WORKDIR/acts" | while read -r _ pid _; do date +%s > "$WORKDIR/cool/$pid"; done
  apply_actions "$WORKDIR/acts" "$WORKDIR/state" >> "$STATS_LOG"
  [ "$full" = 1 ] && sleep 8 || sleep 2
done
```

- [ ] **Step 3: 实现 service.sh 看门狗**

```sh
#!/system/bin/sh
# service.sh — KSU/Magisk/Apatch 兼容入口 + 看门狗
MODDIR=$(dirname "$0")
BB=""
for c in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
  [ -x "$c" ] && { BB=$c; break; }
done
export STATS_LOG="$MODDIR/data/stats.log"; mkdir -p "$MODDIR/data"
[ -n "$BB" ] && export ASH_STANDALONE=1
run() { [ -n "$BB" ] && "$BB" ash "$@" || sh "$@"; }

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 3
while :; do
  if ! pgrep -f 'engine/memory.sh' >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] WATCHDOG restart" >> "$STATS_LOG"
    WORKDIR="$MODDIR/data" STATS_LOG="$STATS_LOG" run "$MODDIR/engine/memory.sh" >/dev/null 2>&1 &
  fi
  sleep 30
done
```

`STATS_LOG` 通过环境变量传给 memory.sh，全文唯一路径（Task5 的 log_stat 读同一变量）——消除双路径 bug。

- [ ] **Step 4: 单测回归（不因新文件破坏旧测试）**

```bash
for t in tests/test_*.sh; do sh "$t" || echo "BROKEN: $t"; done
```
预期：全部 `fail=0`

- [ ] **Step 5: 真机冒烟（L1 存活）**

```bash
# 手动部署引擎到模块路径(未打包状态)
mkdir -p /data/adb/modules/COSMemory && cp -r engine service.sh /data/adb/modules/COSMemory/
STATS_LOG=/data/adb/modules/COSMemory/data/stats.log sh /data/adb/modules/COSMemory/service.sh &
sleep 60
pgrep -f 'engine/memory.sh' && echo L1-ALIVE
cat /data/adb/modules/COSMemory/data/caps.conf 2>/dev/null || cat /data/local/tmp/cosmem/caps.conf
tail -3 "${STATS_LOG:-/data/adb/modules/COSMemory/data/stats.log}"
```
预期：`L1-ALIVE`；caps.conf 六项 CAP=1（本机已验证这些能力都存在）；stats.log 无 `SENTINEL HALT`、无 `halt: no lru source`

- [ ] **Step 6: Commit**

```bash
git add engine/ service.sh && git commit -m "feat: 能力探测+主循环状态机+看门狗"
```

---

### Task 7: L2 因果验证 + 出厂 KILL 名单实测校准

**Files:**
- Create: `tests/test_e2e.sh`（真机手动跑）
- Modify: `config/名单列表.conf`（补实测过的 KILL 项）

**Interfaces:**
- Produces: L2 验证报告（stdout）
- Consumes: Task 6 部署好的引擎

**硬要求（spec 第 4 段）：出厂 KILL 名单逐条实测，老 A1 的 2023 名单不得照抄。**

- [ ] **Step 1: 写因果对照脚本**

```sh
#!/system/bin/sh
# tests/test_e2e.sh — L2: 引擎开/关两段对比(方法继承 2026-09-28 真相测试)
MOD=/data/adb/modules/COSMemory
export STATS_LOG=$MOD/data/stats.log
SNAP() {
  for d in /proc/[0-9]*; do
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$c" in com.tencent.mm*) echo "adj=$(cat $d/oom_score_adj) :: $c";; esac
  done | sort
}
pkill -f 'engine/memory.sh'; sleep 2
monkey -p com.tencent.mm -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 5
am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1; sleep 8
echo "== 引擎关 =="; SNAP
sh $MOD/engine/memory.sh & sleep 15
echo "== 引擎开 =="; SNAP
monkey -p com.coolapk.market -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 4
am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1; sleep 10
echo "== 触发后 =="; SNAP
echo "== stats =="; tail -8 "$STATS_LOG"
pkill -f 'engine/memory.sh'
```

**L2 判定（人工读数）**：「引擎开」段白名单进程 adj=200（KEEPADJ 生效）且 stats.log 有 `KEEPADJ com.tencent.mm <old>->200`；「引擎关」段无人纠正。两段无差异 → **L2 FAIL，禁止进入 Task 8 打包**（无行为证据不算通过——"尸体"教训）。

- [ ] **Step 2: 跑 L2 并记录原始输出**

```bash
sh tests/test_e2e.sh
```

- [ ] **Step 3: KILL 名单逐条实测**

```bash
# 候选(老名单中仍存在的子进程), 每条:
ps -A -O NAME | grep 'com.tencent.mm:toolsmp'   # 1) 确认存在
# 2) 杀掉, 观察5分钟: 主App功能/消息收发正常
# 3) 通过→收录; 失败→丢弃并记入 docs/kill-exclusions.md
```

- [ ] **Step 4: 更新名单 + 全量回归**

```bash
for t in tests/test_*.sh; do sh "$t" || echo "BROKEN: $t"; done  # 全绿
sh tests/test_e2e.sh                                             # L2 复测
```

- [ ] **Step 5: Commit**

```bash
git add config/名单列表.conf tests/test_e2e.sh
git commit -m "test: L2 因果验证 + 出厂 KILL 名单实测校准"
```

---

### Task 8: 打包（module.prop / customize.sh / uninstall.sh / NOTICE / META-INF）

**Files:**
- Create: `module.prop`、`customize.sh`、`uninstall.sh`、`NOTICE`、`META-INF/`
- Modify: `config/名单列表.conf`（替换 Task3 Step5 的占位包名）

**Interfaces:**
- Produces: 可安装 zip（KSU/Magisk 双端）
- Consumes: 全部引擎文件 + Task 7 通过的名单

- [ ] **Step 1: module.prop**

```properties
id=COSMemory
name=COSMemory 内存管理
version=v0.1
versionCode=1
author=PLACEHOLDER署名
description=ColorOS 15/16 白名单保活+智能回收. 基于 A1Memory(HChai/OneB1ank) 二次开发, GPLv3.
```

- [ ] **Step 2: customize.sh**

```sh
#!/system/bin/sh
OUTDIR="/sdcard/Android/COSMemory"
mkdir -p "$OUTDIR"
[ -f "$OUTDIR/名单列表.conf" ] || cp "$MODPATH/config/名单列表.conf" "$OUTDIR/"
[ -f "$MODPATH/config/memory.json" ] && [ ! -f "$OUTDIR/memory.json" ] \
  && cp "$MODPATH/config/memory.json" "$OUTDIR/"
[ "$ARCH" != "arm64" ] && abort "Not compatible: $ARCH"
set_perm_recursive "$MODPATH" 0 0 0755 0755
ui_print "- COSMemory 已安装. 名单: $OUTDIR/名单列表.conf"
```

- [ ] **Step 3: uninstall.sh（adj 还原 + 配置清理）**

```sh
#!/system/bin/sh
MODDIR=$(dirname "$0")
. "$MODDIR/engine/exec.sh"
restore_state "$MODDIR/data/state" 2>/dev/null
rm -rf /sdcard/Android/COSMemory
```

- [ ] **Step 4: META-INF 沿用上游模板**

```bash
mkdir -p META-INF/com/google/android
git show HEAD:module/META-INF/com/google/android/update-binary > META-INF/com/google/android/update-binary
git show HEAD:module/META-INF/com/google/android/updater-script > META-INF/com/google/android/updater-script
```

- [ ] **Step 5: NOTICE**

```
COSMemory 内存管理模块
基于 HChai/OneB1ank 的 A1Memory (https://github.com/OneB1ank/A1Memory) 二次开发,
继承 GPLv3。原作者: HChai。名单格式/memory.json/多语言等外壳协议源自上游;
engine/ 引擎为本项目重写。
```

- [ ] **Step 6: 组包 + KSU 实机安装验证**

```bash
zip -r ../COSMemory-v0.1.zip module.prop customize.sh uninstall.sh service.sh engine config NOTICE META-INF
# KSU 安装 → 重启 → 已安装形态下重跑 L2
sh tests/test_e2e.sh
```
预期：安装无 abort；重启后 `pgrep -f engine/memory.sh` 存活；L2 判定通过

- [ ] **Step 7: 最终回归 + 打 tag**

```bash
for t in tests/test_*.sh; do sh "$t"; done   # 全绿
git add -A && git commit -m "feat: v0.1 打包(KSU/Magisk) + NOTICE + 实机验证"
git tag v0.1
```

---

## Self-Review 记录

1. **Spec 覆盖**：架构/引擎(spec §2-3)→Task1-6；名单/配置(§4)→Task3/7/8；兼容层能力探测与哨兵(§5)→Task6；验证(§6)→L1=Task6Step5、L2=Task7、打包=Task8。**有意排除（属后续计划）**：面板、L3 效果统计、L4 破坏性全套、激进回收档、调参模块、Magisk 实机验证（无环境时按 spec 如实标注「未验证」）。
2. **占位符扫描**：Task3 Step5 原有 `com王者荣耀.party` 占位 → 已修：出厂 WHITE 只保留 `com.tencent.mm com.tencent.mobileqq com.ss.android.ugc.aweme`（执行时按此写入）。`author=PLACEHOLDER署名` 为**构建时必替换项**，执行到该步时问用户署名。
3. **一致性**：动作行 `KEEPADJ/KILL/SKIP` Task4产出=Task5消费 ✓；快照格式 `state|procstate|pid|pkg` 四段 Task2产出=Task4测试夹具 ✓；`STATS_LOG` 环境变量 Task5/6/7/8 唯一路径 ✓；`WORKDIR` 默认值 Task2/6 一致 ✓。
