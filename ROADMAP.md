# COSMemory 路线图

> 状态快照：**2026-10-04 · v1.1.1**（面板三连修：白屏根因 boot-after-paint（冷开首帧 5.7s→1.1s A/B 实测）、日期切换 ref 解包赋值 bug、日期菜单 dropup 裁剪；+按钮底部 toast 反馈、app-shell 导航根治下沉。此前 v1.0 封版收数：guard\/FREEZE 三天 BLOCK 11 全正向、FAILED=0、保护机制实弹全过；发布帖待发）

## 当前状态

- **v0.2 已交付**：shell 引擎 + KSU WebUI 面板（Vue3 单文件），部署于一加 11 / ColorOS 16 / 16GB / KernelSU
- 发布包：`COSMemory-v0.2.zip`（md5 `5c730f0185d0b10c2fd5a3fd471ad113`，已归档 旧版/）
- **v0.3 完成（2026-09-29）**：可归因性七件套全部实现并真机验证，55断言双端全绿；成品归档规则：`/storage/emulated/0/内存管理模块/` 外层仅最新版，历史版本进 `旧版/`
- **L3 进行中（2026-09-29 首日初检 + 三轮深挖收官）**：7.5h 保活纠正 752 次、零 KILL、零非法行、两次真机重启保护机制全部自动恢复
- **QQ 冷启三轮归因（2026-09-29 上午）**：①`no_frozen` 厂商豁免实验**阴性已回滚**（framework 无此键/Athena 重读无效/Hans 照冻）②Hans 冻结**无害**（收包 15s 解冻）③真凶=**AOSP 标准的 AMS cached 回收 + Activity trim**（`am_proc_died adj=905` 按 procState 杀不看 adj）④对照组：**微信昨夜同样死亡 15 次**（09:26 `mm:support` 905 档），「微信免疫」是使用频率造成的错觉——系统对所有 App 一视同仁

### 验证矩阵

| 维度 | 状态 | 说明 |
|---|---|---|
| 单元测试 | ✅ 三端全量 | shell 全套 total_fail=0（含 test_listedit 27 断言）+ vitest 68 + JUnit 37 |
| **KILL 逐条实测** | ✅ 2026-10-01 | 决策层单测（正向命中 + WHITE pkg:* 豁免 SKIP whitelist）+ 真机端到端（heytap.health:SportDaemonService 杀→系统重拉→按 pid 冷却续杀, stats 明细 KILLED=1×2, 归因实锤）；编辑器 add/del 全链, 测后 conf 还原出厂 KILL=0 |
| L1 存活 | ✅ | 引擎常驻 + CPU 空闲近 0 |
| L2 因果 | ✅ | 引擎关 adj=905 → 开 adj=200 → 触发后再纠正 |
| L4 破坏性 | ✅ 20/20 | 名单容错不连坐 / 看门狗 5s 拉起 / 哨兵停机零写入 / exit 9 / 白名单拒杀 |
| 开机自启 | ✅ | 重启后 service.sh 拉起 + KEEPADJ 生效 |
| 面板真机 | ✅ | 奶油粉风格 + Solar 图标，打开 <100ms |
| **Magisk 端** | ⬜ 未验证 | 无实机，发布须如实标注 |
| **ColorOS 15** | ⬜ 未验证 | 无实机，发布须如实标注 |
| **8GB / 非一加机型** | ⬜ 未验证 | 配置已分档，实际未测 |

## 通用性架构（2026-09-29 定案）

引擎依赖全部是 **AOSP 标准件**（`dumpsys activity lru` / `oom_score_adj` / PSI），零 hook、零厂商件依赖。通用性按三层支撑：

| 层 | 内容 | 策略 |
|---|---|---|
| **L1 · AOSP 基线** | lmkd（按 adj 杀）+ AMS cached 回收/Activity trim（按 procState）——**所有安卓共有**，「挂后台点开冷启」是全安卓通病 | ✅ 主战场：lmkd 防线已由 adj=200 覆盖（已验证）；AMS 防线留阶段二 **hook AOSP 标准点**（`CachedAppOptimizer`/trim）→ 一个 hook 天然通吃所有 ROM |
| **L2 · 厂商叠加** | ColorOS=Hans 冻结（已证无害）/MIUI=神隐/三星=Device Care/OriginOS=原子冻结… | 能力探测范式扩展（`CAP_HANS` 等）：探测到才适配，探测不到不影响 L1，面板标注「本 ROM 有额外层」 |
| **L3 · 验证矩阵** | 代码通用 ≠ 效果已证 | 每 ROM 实测状态诚实标注，社区滚动回填；哨兵+降级保证未验证 ROM **安全试用**（最坏不干活，不会干错活） |

定位表述：**「引擎通用于 Android 12+（AOSP 标准件），已实测 ColorOS 15/16；其他 ROM 免装可用、效果待社区验证」**。

## 发布前检查清单（→ v1.0）

- [ ] **L3 长期日用数据**（进行中，样本持续累积）：
  - [x] 被动半天（2026-09-28 23:15→09-29）：752 次保活纠正、零 KILL、零故障、2 次真机重启自动恢复
  - [x] **主动压力实验（2026-09-29，PASS）**：/dev tmpfs 分档填充 5GB，PSI 0.08→1.02、lmkd free 14MB 极限水位、22 进程死亡——**adj=200 档零死亡**（死亡全分布 500~985，800 档 21 个最多）；QQ 被引擎连续 8 次 KEEPADJ 摁在 200 全程幸存；微信✓ QQ✓；引擎压力期 DEATH×3 归因实战首秀。日志存档 `/data/local/tmp/eta/stress_exp.log`
  - [x] 长稳天数累积（2026-10-03 收数：KEEPADJ 914 / FAILED=0 / 哨兵4次HALT+看门狗5次拉起全按设计工作，凌晨4次系统重启全自动恢复）
- [x] ~~no_frozen 厂商豁免实验~~ → **阴性，已回滚还原（2026-09-29）**：system_server framework 无此键、Athena(com.oplus.athena) 重启重读无效、Hans 照常冻结；Doze 白名单/待机桶/frozen_dlg 对比微信 QQ 全部同待遇——豁免名单路线整体排除
- [x] **可归因性补齐**（v0.3 完成）：
  - [x] DEATH 行：白名单进程快照消失即记录（pkg/pid/最后状态）— 真机实测(杀appbrand 12s内记录)
  - [x] KEEPADJ 带 pid（区分进程换代）
  - [x] am_proc_died 白名单 kill 采集（events时间窗增量 → kill_capture.log >64KB截尾）— 真机抓到真实事件
- [x] **日志卫生**（v0.3 完成）：
  - [x] stats.log 轮转（>512KB 截尾 64KB）+ kill_capture 同款轮转
  - [x] 看门狗死因 prev_alive（真机实测 76s/100s 两条有效记录）
  - [x] FAILED 分类（missing/mismatch/write）+ SKIPPED 汇总
- [x] **SKIP 拦截可见化**（v0.3 完成 2026-09-29）：exec 汇总行 SKIPPED 计数 + stats.log 累计 + 面板异常区「白名单拦截/白名单死亡」两行
- [ ] **发布帖**：效果数据 + 验证矩阵 + 已知限制（诚实清单是社区信任的根基）
- [ ] v1.0 打 tag + 终版发布包 + README 数据更新

## 二期功能（v1.x，按需排期）

- [x] **激进回收档**（v0.6.0）：触发=PSI≥阈值 AND 水位<下限(CAP_PSI=0 降级单看水位)；深度三档可配、白名单免疫、单轮封顶+冷却；T-R1 真机强制触发/白名单零伤亡/T-R2 静默/模拟链全过
- [x] **FREEZE 名单实现**（v0.5.0）：在册即封杀 — 引擎存量杀+巡检（T-FREEZE ①③④⑤实测过）+ 拦拉起 hook（T-FREEZE ②实测: startProcess=1, FREEZE_BLOCK 拦截、进程零创建）；总闸 freeze.enabled、冲突双向拒绝
- [ ] **调参模块**（2026-10-01 复议改判，随通用化目标）：不砍，挂 **Phase 1（OPPO系）** — 原"本机不碰厂商参数"论据在通用机型语境下失效（OEM 调参参差不齐, lmkd/ZRAM 正是通用痛点）；准入门槛=回滚三件套（存在性探测→探测不到只读/隐藏 + 改前快照 + 一键还原），Phase 1 先落**只读观测窗**（lmkd/ZRAM 当前值展示），可写锁在三件套后；v1.0 不带此功能
- [x] **面板名单编辑器**（v0.7.0，2026-10-01）：显式编辑模式（WHITE/KILL/FREEZE 三组增删+行级二次确认）+ 已装应用选择器（COSGuard AppCatalog: apps.json 561应用+第三方图标79张, 30s首建/refresh触发/24h兜底）+ 防线事件一键加 FREEZE（D4 包名级前端拦截）；写入层 engine/listedit.sh（同源校验/parsefail回滚/原子mv/即时guard_bridge, test_listedit 27断言）；修 FREEZE 带组解析、AppCatalog 数组头孤儿逗号；真机 UI 链全绿（screencap 逐屏验收）
- [x] **阶段二 · AMS hook spike 第 1 阶段（2026-09-29 完成，源码级侦查）**：jadx/baksmali 反编译设备真实 services.jar + oplus-services.jar → **杀链钉死**：`OomAdjuster.updateAndTrimProcessLSP` 三处杀点（cached/empty 超限 + empty 超时）全部被闸门 `onHookKillCacheEmpty(app)` 包住（**返回 true=免死**，源码证明）；Oplus 未旁路杀链（仅 Ext 注入策略），闸门现有实现=Athena 动态 Set（`skipCacheEmptyKill`），**配置路线排除、hook 路线确立**；双轨方案：A 轨 hook `ProcessRecord.killLocked` 按 reason 过滤（AOSP 通用）+ B 轨 hook `OomAdjusterExtImpl.onHookKillCacheEmpty`（ColorOS 更稳）。报告：[docs/spike-ams-hook-report.md](docs/spike-ams-hook-report.md)
- [x] **阶段二 · LSPosed hook**：已超额完成 — COSGuard(killLocked hooks=3, observe/guard双模) 2026-09-30 UAT PASS + 21.6h观察收数通过, guard已放量日用
- [ ] **lmkd 裁决（2026-09-29 定案）**：不 hook lmkd（adj=200 已通过官方输入通道覆盖该防线，hook 解的是不存在的问题）；调参（minfree/device_config）留可选开关默认关，日常不碰厂商已调好的参数
- [ ] ~~厂商豁免同步~~ no_frozen 路线已排除；待研究其他 ROM 豁免接口（按 L2 厂商层逐个探测）

## 通用化路线（2026-10-01 用户定调）

- **Phase 0 · v1.0 本机封版**（本周）：10-03 guard/FREEZE 日用满 3 天 → 发帖 → tag v1.0（一加11 跑通为先）。
- **Phase 1 · v1.x OPPO 系横向扩展**：架构分层（ColorOS 通用层 vs 机型特化层）→ 能力矩阵报告（装机体检）→ 调参观测窗（只读）→ 兼容声明扩至 OPPO/一加/realme · ColorOS 15-16（不匹配警告不硬拦）；**验证=社区群测**（用户拉群，机型矩阵后补；开发机暂只有一加11，Phase 1 中不依赖第二台机器的部分先行）。
- **Phase 2 · v2.x 跨生态（小米/三星）**：每家一次独立杀链侦查 spike（MIUI/HyperOS、OneUI 各自定制杀后台逻辑, hook 点完全不同, 复用 AMS spike 方法论）；调参需避让 MIUI 内存扩展 / 三星 RAM Plus（ZRAM 变体冲突）。

## 已知限制（发布帖引用）

- 引擎只管 **`cch*` 缓存态**进程；服务/前台/最近任务态由系统托管（设计如此，面板显示「系统托管」）
- **KILL 动作必须带 `:进程后缀`**（整包封杀请用 FREEZE，协议见名单文件头注释）
- 出厂 KILL 名单**为空**——每条候选须逐条实测，老 A1 (2023) 名单在 2026 年已全部失效（见 [docs/kill-exclusions.md](docs/kill-exclusions.md)）
- **adj=200 保活只覆盖 lmkd 内存压力路径**；AOSP 标准的 AMS cached 回收按 procState 杀、不看 adj（`am_proc_died adj=905` 实锤，「压 adj→杀」同帧完成，2s 轮询窗口不可入）；Oplus Hans 冻结已证无害（收包即解冻）；`no_frozen` 豁免实验阴性已回滚
- **双路径覆盖（阶段二已完成 2026-09-30）**：lmkd 内存压力杀由 adj=200 覆盖（已验证）；AMS cached/empty 回收（按 procState 杀、不看 adj）由 COSGuard hook `ProcessRecord.killLocked` 按 reason 过滤拦截（UAT PASS + 21.6h 收数，guard 放量日用，BLOCK 11 全正向）。剩余诚实边界：guard 模式才拦、观察模式只记录；桥缺失/解析失败一律 fail-open 只记不拦；killLocked 之外的旁路杀点（进程自身 exit、厂商私有路径）不承诺覆盖
- 对照组事实：微信昨夜同样死亡 15 次——**系统对所有 App 一视同仁，无「微信免疫」**；用户感知差异来自使用频率（常开=Activity 热、挂着=Activity 被 trim）
- **hook 路线已论证排除**：上游 A1 的 libhook_lmkd.so 钩的是 lmkd kill/pidfd，与 adj 同属 lmkd 路径，同样挡不住 AMS/Hans，且引入黑盒二进制维护负担
- 轻负载下模块**安静无感**（设计目标），效果仅在重负载/多任务场景可感知
- Magisk 与 ColorOS 15 理论兼容、未经实机验证

## 文档索引

- 设计 spec：[docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md](docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md)
- v0.1 实现计划（8 任务 43 步，已全部完成）：[docs/superpowers/plans/2026-09-28-memory-engine-v0.1.md](docs/superpowers/plans/2026-09-28-memory-engine-v0.1.md)
- KILL 排除清单：[docs/kill-exclusions.md](docs/kill-exclusions.md)
