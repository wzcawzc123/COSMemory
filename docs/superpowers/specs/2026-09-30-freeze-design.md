# FREEZE 名单执行 · 设计 spec（二期第 1 项）

- 状态：设计批准（brainstorm 五决策 + 七节设计，2026-10-01 用户确认）
- 批准的决策：见 §3；前置调研项见 §4.3（Task 0）

## 1. 背景与依据

- 名单协议中 `FREEZE <包名>` = **整包封杀**（名单头注释定义，区别于 KILL 的 `包:后缀` 点名杀）；
- 解析链已存在：`engine/lists.sh` 产出 `FREEZE_LIST`、面板 `listconf.ts` 解析并分组显示（「FREEZE 封杀」）；
- ROADMAP:61「点名杀 + 冷却期阻止拉起（协议已定义，执行逻辑未实现）」——**执行器即本 spec**；
- 出厂名单 FREEZE 组为空，全靠用户手动点名 → 点名动作本身即授权。

## 2. 目标与非目标

**目标**
1. 白名单之外的点名包：杀存量进程 + 冷却期持续拦拉起，直到条目移出；
2. 双层可靠性：hook 实时拦截（毫秒级） + 引擎周期巡检兜底（hook 失效时补位）；
3. fail-safe：冲突/解析失败/开关关闭一律不执行；hook 侧任何异常 fail-open 放行。

**非目标**
- 不改 WHITE 保活链与防线 observe/guard 语义（FREEZE 独立，见 §3-D3）；
- 不做按条冷却时长参数（`FREEZE pkg:N` 不在首版，YAGNI，见 §3-D2）；
- 不 hook lmkd / 不碰厂商参数（沿承裁决定案）。

## 3. 已定决策记录（brainstorm 五问五答）

| # | 决策点 | 结论 |
|---|---|---|
| D1 | 实现路线 | **B**：引擎首发杀存量 + COSGuard 新增 startProcess 族 hook 拦拉起（跳过轮询中间态；C/C++ 方案因 system_server 崩溃风险与无性能收益被否）|
| D2 | 冷却语义 | **在册即持续封杀**：名单在册期间一直拦，移出即解封；无时长参数 |
| D3 | 与防线模式关系 | **独立**：observe/guard 只管白名单杀因拦截，FREEZE 不受其门控；总闸 = `memory.json` 的 `freeze.enabled` |
| D4 | WHITE∩FREEZE 冲突 | **双向拒绝**：判非法条目，两边都不执行，面板 bad 红色高亮 |
| D5 | 触发时机 | **事件驱动（启动+名单变更）杀存量 + 每轮循环周期巡检兜底** |

## 4. 架构总览

### 4.1 数据流

```
名单列表.conf (FREEZE <pkg>)
      │ engine/lists.sh 解析 + 交叉冲突校验(D4)
      ▼
config桥 /data/system/cosmem/guard.conf 追加 FREEZE 行
      │ service.sh guard_bridge() 生成；freeze.enabled=false → 不写任何 FREEZE 行(桥即状态)
      ├──▶ ① COSGuard hook：快照缓存(5s mtime) → startProcess 路径拦截(D1)
      └──▶ ② engine memory.sh：启动/名单变更杀存量 + 每轮巡检补杀(D5)
              │ 杀成功 append
              ▼
       guard/日期.log (act=FREEZE)  ◀── hook 遥测 (act=FREEZE_BLOCK)
              ▼
       guard_stats.sh 聚合 → WebUI 防线/名单页
```

### 4.2 桥协议扩展（guard.conf 追加行）

```
FREEZE_ENABLED=1            # 仅当 memory.json freeze.enabled=true 时写出
FREEZE com.example.app      # 每包一行；无 FREEZE 行 = hook 与引擎均静默
```

- 复用 VERSION=1 协议（追加行对旧 hook 向前兼容——旧 hook 忽略未知行）；
- 30s service.sh 热加载 + hook 5s mtime 快照，双层刷新节奏不变。

### 4.3 Task 0 · 前置调研（实现的第一个任务）

反编译定位 ColorOS 16 / A16 `system_server` 的进程拉起方法族（`ActivityManagerService.startProcessLocked` / `ProcessList.startProcess*` 一线），产出：类与方法签名、参数中包名/进程名取法、LSPosed hook 可行性结论、与现有 killLocked 三钩共存性验证。**调研报告落档前不写拦截代码。**

## 5. 引擎侧（engine/memory.sh，纯 shell）

1. **存量杀**：引擎启动时 + 每轮检测到 `FREEZE_LIST` 内容变化时（diff 上一轮），对名单内包执行 `am kill <pkg>`（尽力杀，进程不存在时静默跳过不计错）；
2. **周期巡检**：现有主循环每轮（sleep 2/8 节奏不变）解析 `FREEZE_LIST`，快照中存活的名单包 → `am kill`（D5 兜底层，hook 失效/LSPosed 被禁时的最后防线）；
3. **事件记录**：杀执行成功 → `guard/日期.log` 追加 `TS|pid|pkg||FREEZE|engine reap`（复用现有 6 字段管道）；进程不存在 → 不产生事件；
4. **失败处理**：`am kill` 返回非零 → 复用 v0.3 `FAILED` 分类记 `FAILED reap <pid> <pkg>` 到 stats.log；
5. **与 FREEZE 相关的配置读取**：`freeze.enabled` 由 service.sh 消化为桥行（引擎只读桥/名单，不直接读该键——单一事实源在桥）。

## 6. hook 侧（COSGuard 扩展，D1 核心）

1. **hook 点**：以 Task 0 调研报告为准（startProcess 族）；与现有 killLocked 3 钩同文件、同 entry 加载；
2. **决策链**（在既有 MODE→WHITE→BLOCK→FUSE→SKIP 之后追加独立支）：
   ```
   包名 ∈ FREEZE 快照集(桥 FREEZE 行) → 拦截(返回/null 化) + 遥测 FREEZE_BLOCK
   否则 → chain.proceed()（不影响既有链）
   ```
   - **FREEZE 支不看 MODE**（D3）：observe/guard 下均执行；
   - 集合为空或 `FREEZE_ENABLED!=1` → 该支恒放行（零开销短路）；
3. **fail-open**：该支任何异常（集合损坏、反射失败）→ 捕获、放行、随行记 `RULE=freeze ACT=ERROR`，绝不影响其他进程与既有拦截链；
4. **刷新**：沿用 5s mtime 快照缓存（T7 已验证机制）；
5. **测试策略**：JUnit 覆盖集合解析/命中判定/异常放行；实机拦截验证走 §9 的 T-FREEZE。

## 7. 冲突与错误处理矩阵

| 场景 | 行为 | 层 |
|---|---|---|
| WHITE ∩ FREEZE 同包（D4）| 双向拒绝：两边都不进执行链，条目标 bad，面板红高亮 | lists.sh 交叉校验（出口统一）|
| 名单语法非法行 | 维持现有 LIST_BAD 上报，FREEZE 部分不受连坐（l4 已验「不连坐」）| lists.sh |
| `freeze.enabled=false` | 桥不写 FREEZE_ENABLED/FREEZE 行 → hook 与引擎双静默 | service.sh |
| 桥文件缺失/VERSION 不符 | hook fail-open 只记不拦；引擎按空集处理 | 两侧 |
| LSPosed 不可用 | 引擎巡检继续杀（D5 兜底）| 引擎 |
| reboot | 桥开机重建 → hook/引擎自然恢复，无独立持久化 | — |

## 8. 遥测与面板

1. **事件行**（复用 6 字段管道）：`act=FREEZE`（引擎杀）/ `act=FREEZE_BLOCK`（hook 拦拉起）；
2. `guard_stats.sh`：新增 `freeze` 计数（今日拦/杀次数）与 `freezeList`（在册包及存活状态）；
3. **面板**：名单页 FREEZE 组补状态列（存活/今日 FREEZE 次数）；防线页统计卡加 FREEZE 计数——**布局不变，仅增字段**；冲突 bad 行沿用现有红色高亮（`listconf.bad`）；
4. 收割/归档沿用 service.sh 按天归档链，零新管道。

## 9. 测试计划

| 级 | 内容 |
|---|---|
| shell 单测（tests/）| 交叉冲突双向拒绝、桥 FREEZE 行生成/开关关闭不写、lists.sh FREEZE 解析边界（后缀/非法行不连坐）|
| JUnit（cosguard）| FREEZE 集合解析、命中/不命中判定、异常 fail-open、与 MODE 无关性 |
| **T-FREEZE 实机**（部署等长稳/guard 日用窗口）| ① 加 FREEZE 条目 → 存量杀生效（进程消失+act=FREEZE）② 拉起被拦（FREEZE_BLOCK 出现、进程未存活）③ 移出条目 → 桥 30s 撤行 → 拉起恢复 ④ freeze.enabled=false → 全静默 ⑤ 冲突条目 → bad 红 + 零执行 |
| 回归 | 既有 all.sh 全套 + vitest 全绿（不破坏 v0.4 现有能力）|

## 10. 版本与节奏

- 分支开发（不动 guard 日用与 v0.4 现场），目标版本 **v0.5.0**；
- Task 0 调研 → spec 用户审阅 → writing-plans 出实施计划 → TDD 实施；
- 实机验收（§9 T-FREEZE）安排在 guard 日用数据平稳之后；
- 风险：Task 0 若发现 startProcess 族在 ColorOS 16 不可 hook（隐藏/内联），回退方案 = 引擎巡检加密（2s 轮询已是节奏上限）+ 文档声明窗口延迟——**该回退不改本 spec 其余部分**。
