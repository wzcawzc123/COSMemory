# 激进回收档 · 设计 spec（COSMemory 二期第 1 项）

- 状态：设计批准（brainstorm Q1档位/Q2触发链 + 方案1引擎内嵌，2026-10-01 用户拍板「不等观察期直接上线」）

## 1. 目标与非目标

**目标**：内存压力时优先牺牲非白名单（按档普杀），为白名单腾空间——保活的进攻形态。
**非目标**：不碰 lmkd/厂商参数（沿承裁决）；不改 KILL/FREEZE 两条既有杀线；不引入新进程。

## 2. 已定决策

| # | 决策 | 结论 |
|---|---|---|
| R1 | 档位 | `reclaim.depth` 可配：`cached`(state cch*) 默认 / `previous`(+prev*) / `service`(+svc/svcb)；出厂 `aggressive=false`，开启默认 cached |
| R2 | 触发链 | `CAP_PSI=1`: PSI some avg10 > psiThreshold **AND** MemAvailable < memFloorMB；`CAP_PSI=0` 降级只看水位；参数 `psiThreshold/memFloorMB/cooldownSec` 全 memory.json 可调 |
| R3 | 架构 | 引擎主循环内嵌（方案1）：`plan_aggressive` 与 `plan_reclaim` 并列，复用 acts/state/cool/apply_actions |
| R4 | 保护 | 白名单免疫（含子进程规则）、is_protected 态、cool 60s、maxKillPerRound——三重保护模板全继承 |
| R5 | 模式关系 | 独立于 observe/guard（开关即授权，同 FREEZE D3）；配置引擎每轮读、热生效≤8s、读失败=默认关 |

## 3. 数据流

```
memory.json reclaim节 →(引擎每轮单行sed读, fail-safe)→ 主循环:
  ①触发判定(AND+降级) ②cooldownSec节流 ③plan_aggressive(按lru行序≈adj从高到低,
  depth档过滤) → acts `RECLAIM pid pkg` ④apply_actions(新增RECLAIM case=KILL同逻辑)
       └→ telemetry追加 TS|pid|pkg||RECLAIM|aggressive depth=<d>
            └→ service收割 → guard_stats.reclaimToday → 面板
```

## 4. 档位→LRU状态词映射（不做数值排序，lru行序即LRU序）

`cached→cch*`；`previous→+prev`；`service→+svc +svcb`。遍历序=快照原始序（lru_dump 已按最近最少使用排列）。

## 5. 面板

- 防线页 W1 数字格加第6格「今日激进」（5列→6列）；
- 设置页新增「激进回收」卡：开关+三档选择，sed 写 reclaim 节（同模式开关的确认交互），≤8s 热生效。

## 6. 测试计划（用户指令：全量测试+真机实测+模拟测试全上）

| 级 | 内容 |
|---|---|
| shell 单测 | plan_aggressive 决策矩阵（三档×白名单×保护×上限）；触发判定注入测试（PSI_PATH/MEMINFO_PATH mock 文件→AND/降级/节流全覆盖）；apply RECLAIM 分支 |
| vitest | reclaimToday 解析 + 设置页 |
| 模拟测试 | 注入层：mock PSI/水位文件驱动完整触发链（不依赖真机压力） |
| **真机实测 T-RECLAIM** | 部署后：①低阈值强制触发一轮真实回收（memFloorMB 临时调大→必然触发→验证按档杀+白名单零伤亡+RECLAIM 事件）②还原阈值→验证静默 ③设置页开关/档位实操 ④改配置≤8s 热生效 |
| 回归 | 既有 shell 全套 + vitest + cosguard JUnit 全绿 |

## 7. 节奏与版本

feat/reclaim 分支 TDD 实施 → 全量测试 → 真机 T-RECLAIM → **直接上线 v0.6.0**（用户已豁免观察期等待）；模块级引擎重启由 Eta 执行，系统重启仍归用户（铁律）。busybox POSIX 兼容红线（禁 \| 类 GNU 扩展）。
