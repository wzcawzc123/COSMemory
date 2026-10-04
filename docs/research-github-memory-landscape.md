# 调研报告：GitHub 内存管理模块生态与功能拓展方向

> 日期：2026-10-05 · 状态：**调研完成（功能立项前的阅读 legwork）**
> 方法：`gh search repos` + `gh api` 直读候选项目 README / 目录 / 源码 / 提交历史（一手来源，未采信二手文章）
> 结论用途：为 COSMemory 下一批功能拓展（v1.2+/Phase 1）提供候选方向与可借鉴实现
> 检索覆盖：memory management、lmkd、zram/swap、freezer、keep alive、OomAdjuster、greenify/scene/thanox 等 30+ 组关键词（GitHub 搜索为 AND 语义，词组越少命中越准）

---

## 1. 生态总览（按与本项目的相关度排序）

| 项目 | Star | 最后更新 | 与 COSMemory 的关系 |
|---|---|---|---|
| [Tornaco/Thanox](https://github.com/Tornaco/Thanox) | 3295 | 2026-09-22 | 同赛道标杆（情景模式/后台管理），Apache-2.0，Java，Android 16，Xposed/Shizuku 激活 |
| [OneB1ank/A1Memory](https://github.com/OneB1ank/A1Memory) | 787 | **2023-11-26 停更** | 本项目上游；2 个 issue 至今无人回（#7 原理、#3 LSPosed SEPolicy） |
| [lululoid/LMKD-PSI-Activator](https://github.com/lululoid/LMKD-PSI-Activator) | 84 | 活跃 | **调参层最佳参考**：动态 swappiness / 增量 ZRAM / LMKD PSI，含 C++ 守护 |
| [Drsexo/Greenify4Magisk-KSU-Reborn](https://github.com/Drsexo/Greenify4Magisk-KSU-Reborn) | 64 | — | Greenify 本体不开源，第三方系统化集成件（boost mode、批量生成名单） |
| [hakavlad/mg-lru-helper](https://github.com/hakavlad/mg-lru-helper) | 62 | 活跃 | MGLRU 内核回收器状态控制（内核层，非应用层） |
| [Referrance/B1Mem](https://github.com/Referrance/B1Mem) | 2 | 2026-02-25 | **A1Memory 唯一仍在维护的 fork**，见 §2.2 |
| [shadow3aaa/lmkd_hook](https://github.com/shadow3aaa/lmkd_hook) | 19 | — | ptrace+Dobby hook lmkd 禁杀，与本项目「不 hook lmkd」裁决相反 |
| [niwenshuai/BackgroundKillGuard](https://github.com/niwenshuai/BackgroundKillGuard) | 3 | 2026-08-21 | **Oplus 厂商杀链同题答卷**，见 §2.3（最重要发现） |
| [zwajton/OomAdjuster](https://github.com/zwajton/OomAdjuster) | 6 | 2026-04-25 | adj 强制守护 + WebUI，同源但更激进，见 §2.5 |
| [gurnoorpannu/ForeSightApk](https://github.com/gurnoorpannu/ForeSightApk) | 0 | 2026-07-15 | **预测性内存管理**（LSTM 下一跳预测），全新范式，见 §2.6 |

补充事实：A1Memory 的 19 个 fork 里除 B1Mem 外全部停在 2023-11（多为 star=0 快照），**本项目是该生态里唯一持续演进的分支**（v1.1.5，2026-10-05）。Scene（helloklf/vtools，1530★，GPL-3.0）最后更新 2023-12，属停更工具箱。

---
## 2. 重点候选项目细读

### 2.1 上游 A1Memory（基线，已吸收完毕）
- 787★ / 19 fork / GPL-3.0，最后提交 `2023-11-26 perf: 更新ndk和llvm`
- 开放 issue：#7「能说下什么原理吗」、#3「LSPosed提示 SEPolicy 未被正确读取」——后者在本项目换成 libxposed 方案后已不适用
- **可借鉴**：无新增（功能已吸收并重构），仅作差异化对照基线

### 2.2 Referrance/B1Mem —— 同源 fork 的差异化选择
- fork 自 A1Memory，`pushed 2026-02-25`，Shell 为主，GPL-3.0，2★
- README 自述定位：**"aimed to be less aggressive, for low RAM devices"**（面向低内存设备、更保守）
- 它做的取舍（与本项目不同）：
  - 「Preventing Low Memory Killer Daemon from killing background processes」——**直接防 lmkd 杀**，与本项目「lmkd 由 adj=200 官方输入通道覆盖、不 hook」裁决相反
  - 「Putting applications to sleep to reduce CPU and memory usage」——**休眠省电**维度（本项目无）
  - 引入 **HAMv2 框架**（C/C++，自述低功耗）、`amui` 终端 TUI、配置可被其他模块嵌入
  - JSON 配置带 `name`/`author` 元信息并打进日志（配置可署名溯源）
- **可借鉴**：①「休眠降 CPU/内存」是本项目缺的维度；②配置署名进日志；③但它含闭源成分（自述 "Some code is proprietary and I can't edit it"），且 2023 年核心代码未动、2026 只改文档，参考价值有限

### 2.3 niwenshuai/BackgroundKillGuard —— 最重要发现（厂商杀链同题答卷）
- Java / Apache-2.0 / `pushed 2026-08-21`，**Android 16 + Oplus + LSPosed**，与 COSGuard 完全同场景
- README 钉死的 Oplus 杀链（一手，含事件日志实证 `Cached(nirvana)[(cch-empty)]`）：

```
NirvanaManager.doClear(...)
  -> OplusOsenseKillAction.executeNirvanaClear(Bundle)
  -> OplusOsenseKillAction.killOneProcessLocked(...)
  -> OplusOsenseKillAction.killLocked(ProcessRecord, ...)
  -> Process.killProcessQuiet(pid)
  -> ProcessList.killProcessGroup(uid, pid)
```

- 另有一条**绕过 OplusOsenseKillAction 的直接链**（作者自己选择不再拦截，避免误伤 BootClear）：
  `TerminateObserverManager / OsenseResEventManager -> OplusOsenseCommonManager.killPid(pid, reason) -> ProcessRecord.killLocked("o-kill(...)")`
- 它的策略设计（值得抄思路）：
  - **白名单软优先级**：不禁杀，只让名单内主进程「稍晚被选中」——不改触发阈值、不改停止条件，只动候选排序，天然不越厂商硬保护边界
  - **全局模式分级**：关 `tryToKillThermal()`（热清理），保留 `tryToKillNormal()`、Athena MemoryGuard、BootClear
  - **AppCare 有效值排序**：把白名单应用组提升到本轮清理阈值以内，但明写「白名单数量超过生存名额时仍可能被清理」
  - 曾 Hook `scanAllProcIfNeeded()`（担心被 ART 内联）→ 1.4.4 改为直接读 `KillContext`，**踩过 hook 被内联的坑**
- 源码 7 个 Java，职责清晰：`KillGuardHook` / `SoftPriorityPolicy` / `ProtectionEventReceiver` / `ForegroundPackageOverlayService`（悬浮窗快捷加白）+ `verification/` 两个策略自测类
- **对本项目的意义**：这正是 COSMemory「已知限制」里 **"killLocked 之外的旁路杀点（厂商私有路径）不承诺覆盖"** 的同题解答。它证明 Oplus 16 存在 `Nirvana`/`o-kill` 厂商杀链，**部分仍汇聚到 `ProcessRecord.killLocked`**（COSGuard 的 3 个 hook 能见到），也有完全绕开的终端接口；同时印证本项目 `o-stop` block 规则命名与真实 reason 体系一致。

---
### 2.4 lululoid/LMKD-PSI-Activator —— 调参层最佳参考
- 84★，Magisk 模块，README + `config.yaml` + `tuning_example.md` 齐全，含 C++ 守护（`dynv.cpp`）与多个 service.sh
- 核心机制（一手，README 配置段）：
  - **动态 swappiness**：按 PSI 三轴（cpu/memory/io）查表映射，`cpu_pressure: [[5,120],[10,100],[20,80],[60,60],[100,40]]`，取达到的最高压力档；`time_window` 支持 avg10/avg60/avg300
  - **增量 ZRAM**：`activation_threshold: 80`（ZRAM 用量 80% 激活下一块）、`deactivation_threshold: 55`；`deactivate_in_sleep` 睡眠时才回收省电
  - **内核可选特性**：UFFD garbage collection、ZRAM 数据去重（探测到才开）
  - **LMKD PSI 参数调优**（替代 minfree_levels 的 PSI 模式）+ Magisk action.sh 报告实时压力
  - 作者诚实标注坏功能（`pressure_binding` 标 "This function is broken"）与 MIUI 兼容坑（需配 dantmnf/NoSwipeToKill）
- **对本项目的意义**：ROADMAP「调参模块 Phase 1」最直接的参考。它证明「只读观测窗 → 可写开关」路线可行，且**动态 swappiness 本质是本项目已有 PSI 采集能力（CAP_PSI 采 avg10）的下游消费者**。README 明确提醒 swappiness 区间过窄会震荡（oscillations → system instability），低 min = 更激进杀应用换性能。

### 2.5 zwajton/OomAdjuster —— adj 强制派的对照
- 6★，HTML/JS 为主，MIT，Magisk/KSU/APatch + WebUI（形态与本项目同类）
- 机制：两级保护 `Critical=-1000`（内核 OOM 永不杀）/ `Restartable=-999`；原生 `oom_guardian` 守护每 **100ms** 扫描强制写 adj，不支持架构回退 shell 循环
- 内存动作：RAM>85% 清系统缓存、压力下压缩受保护应用内存、swap>85% force-stop 低优先级 cached 进程、**每 60s LRU 去优先级**（force-stop procState 19 空进程、procState 14-18 后台进程 adj 抬到 999）
- **对本项目的意义**：对照价值大于借鉴价值。`-1000` 比 `adj=200` 激进一个数量级（受保护应用完全不参与回收，影响整机公平性），而它「按 procState 分档处理 14-18 / 19」印证本项目引擎只管 `cch*` 的边界合理；其 100ms 强写频率反衬本项目 2-8s 轮询的低开销定位。**不建议跟进 -1000**，但「swap 超阈值才 force-stop cached」可作为激进回收档的补充触发源（现为 PSI+水位双条件）。

### 2.6 gurnoorpannu/ForeSightApk —— 范式级参考（预测性内存管理）
- 0★ / Kotlin / 2026-07 更新，含独立 ML 仓库 `ForeSight-MLpipeline`
- 机制（README 一手）：`UsageStatsManager` 取最近 10 次前台切换（24h→7d→30d 递增回看）→ TFLite LSTM（独立 `:inference` 进程跑，崩溃不拖垮 UI）→ `AppDecisionEngine` 输出 **PROTECT / FREEZE / UNFREEZE / IGNORE** 四态 → `PreWarmEngine` 按置信度**预热启动** top 预测应用（带 RAM 安全阀）
- 亮点设计：
  - `ShadowEvaluationStore` 记录 top-1/3/5 准确率 + **安全指标（把即将打开的应用冻掉的概率）**，作为奖励信号
  - 每夜 WorkManager 只微调 embedding 层（LSTM 冻结），全本地、数据不出机
  - 每轮动作封顶（capped per cycle），避免激进
- **对本项目的意义**：这是**「保活谁」的决策层升级**——本项目现在是静态白名单，它是预测式动态白名单。落地不需要新 hook（FREEZE 可用现有引擎动作），但需 UsageStats 权限 + 模型 + 评估闭环，工程量大。可先做**轻量版**：用「最近使用频率/上次使用时间」这类无模型信号动态调整 KEEPADJ 优先级。其 `ShadowEvaluationStore` 的「安全指标」思路尤其值得抄——本项目同样需要一个「保活策略是否反而伤害用户」的度量。

### 2.7 内核侧（不属于本项目，仅记录边界）
- `mg-lru-helper`(62★)、`re-swappiness`(15★，修 MGLRU 的 `vm.swappiness` 失效)、`GKID-Kernels`(76★ 含 MGLRU) —— 内核回收器属内核/ROM 层，本项目「AOSP 标准件、零内核依赖」定位不碰，但**探测并展示 MGLRU/swap 状态**可进 Phase 1 观测窗
- `lmkd_hook`(19★，ptrace+Dobby hook lmkd 禁杀) —— 与 2026-09-29「不 hook lmkd」裁决相反，维持原裁决（hook 解的是不存在的问题，且引入黑盒注入负担）

---
## 3. 对 COSMemory 的功能拓展候选（按价值/成本排序）

| # | 方向 | 依据 | 参考项目 | 工程量 | 优先级 |
|---|---|---|---|---|---|
| 1 | **Oplus 厂商杀链观测与拦截补全** | 本项目「已知限制」明写旁路杀点不覆盖；BackgroundKillGuard 已证 Oplus 16 存在 Nirvana/o-kill 厂商链 | BackgroundKillGuard §2.3 | 中（需 spike 反编译验证本机 reason 全集） | **高**：补齐诚实边界的直接短板，有同场景开源实现可对照 |
| 2 | **SKIP/杀伤统计可观测性补强** | ROADMAP 二期已挂（KILLED 只计本轮、SKIP 四类不落日志） | 自身已有 | 小（纯日志） | **高**：账上已认领，半天量级 |
| 3 | **调参观测窗（只读）→ 动态 swappiness** | ROADMAP Phase 1 已定案；**地基已打**：CAP_LMKD_CFG 存在性探测(probe.sh) + PSI avg10 采集 + 诊断包 meminfo 快照 + spec 已侦查参数路径(device_config lmkd_native / minfree 六档 / lmkd.reinit, 2026-09-28)；**缺的是本体**——面板常驻展示 swappiness/ZRAM/minfree/device_config 当前值与出厂对照(实测面板+webroot 对这 4 类关键词 0 命中) | LMKD-PSI-Activator §2.4 | 中偏小（探针可扩 probe.sh 骨架，主要是面板卡片+快照对照） | **高**：Phase 1 主线内容，也是写操作「改前快照」的前置 |
| 4 | **swap/水位作为激进回收补充触发源** | 现有触发仅 PSI+水位 | OomAdjuster §2.5 | 小 | 中 |
| 5 | **保活策略安全度量（Shadow Evaluation）** | 缺「策略是否帮倒忙」的度量 | ForeSight §2.6 | 中 | 中：与 #2 同属可观测性，可合并设计 |
| 6 | **动态保活优先级（无模型轻量版）** | 静态白名单外的补充信号 | ForeSight §2.6 | 中 | 中低：先做信号采集，模型后置 |
| 7 | 休眠降 CPU/内存维度 | 本项目缺此维度 | B1Mem §2.2 | 大（涉冻结/唤醒语义，与 FREEZE 重叠） | 低：先厘清与现有 FREEZE 的边界 |
| 8 | 内核 MGLRU/swap 状态展示 | 观测窗素材 | mg-lru-helper §2.7 | 小 | 低：并入 #3 观测窗 |

**明确排除（维持既有裁决）**：hook lmkd（lmkd_hook 路线，2026-09-29 已裁决）、`oom_score_adj=-1000` 强制派（OomAdjuster，影响整机回收公平性）、Greenify 式休眠唤醒（Greenify 本体不开源，只能抄第三方集成件）。

---

## 4. 检索方法备注（供后续复用）

- `gh search repos` 是 **AND 语义**，关键词堆叠会返回空集；正确用法是单短语 + `--sort stars`，多方向分多次查询
- `gh search ... --json X -q '<jq>'` 组合会静默返回空，改用 `--json` 全量取回再本地解析
- 一手来源取用：`gh api repos/{r}`（元数据）/ `contents`（目录）/ `readme | base64 -d`（正文）/ `commits`（活跃度）/ `git/trees?recursive=1`（源码文件清单）
- Star 数只代表关注度，不等于质量：BackgroundKillGuard 仅 3★ 但源码级信息密度最高；Thanox 3295★ 但 README 不含技术细节，需另查文档站

## 5. 来源清单

1. https://github.com/Tornaco/Thanox （元数据 + README，2026-10-05 读取）
2. https://github.com/OneB1ank/A1Memory （元数据 + commits + issues + forks）
3. https://github.com/lululoid/LMKD-PSI-Activator （README 全文 + 目录）
4. https://github.com/niwenshuai/BackgroundKillGuard （README 全文 + 源码文件树）
5. https://github.com/Referrance/B1Mem （README + commits + fork 关系）
6. https://github.com/zwajton/OomAdjuster （README 全文）
7. https://github.com/gurnoorpannu/ForeSightApk （README 全文）
8. https://github.com/shadow3aaa/lmkd_hook 、https://github.com/hakavlad/mg-lru-helper 、https://github.com/firelzrd/re-swappiness （README 摘要）
