# COSMemory 路线图

> 状态快照：**2026-09-28 · v0.2 发布就绪**（开发与验证 100% 完成，待日用攒数据后发 v1.0）

## 当前状态

- **v0.2 已交付**：shell 引擎 + KSU WebUI 面板（Vue3 单文件），部署于一加 11 / ColorOS 16 / 16GB / KernelSU
- 发布包：`COSMemory-v0.2.zip`（md5 `5c730f0185d0b10c2fd5a3fd471ad113`）
- **L3 进行中（2026-09-29 首日初检 + 三轮深挖收官）**：7.5h 保活纠正 752 次、零 KILL、零非法行、两次真机重启保护机制全部自动恢复
- **QQ 冷启三轮归因（2026-09-29 上午）**：①`no_frozen` 厂商豁免实验**阴性已回滚**（framework 无此键/Athena 重读无效/Hans 照冻）②Hans 冻结**无害**（收包 15s 解冻）③真凶=**AOSP 标准的 AMS cached 回收 + Activity trim**（`am_proc_died adj=905` 按 procState 杀不看 adj）④对照组：**微信昨夜同样死亡 15 次**（09:26 `mm:support` 905 档），「微信免疫」是使用频率造成的错觉——系统对所有 App 一视同仁

### 验证矩阵

| 维度 | 状态 | 说明 |
|---|---|---|
| 单元测试 | ✅ 19 断言 | 解析/名单/决策/执行/桥接（Linux + 设备双端） |
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

- [ ] **L3 长期日用数据**：日用几天后分析 `stats.log`——保活纠正成功率、白名单 adj 稳定占比、冷启动体感对比
- [x] ~~no_frozen 厂商豁免实验~~ → **阴性，已回滚还原（2026-09-29）**：system_server framework 无此键、Athena(com.oplus.athena) 重启重读无效、Hans 照常冻结；Doze 白名单/待机桶/frozen_dlg 对比微信 QQ 全部同待遇——豁免名单路线整体排除
- [ ] **可归因性补齐**：白名单进程死亡事件日志（DEATH 行）、KEEPADJ 记录 pid、lmkd kill 日志常驻小缓冲采集
- [ ] **日志卫生**：stats.log 轮转（实测 284KB/半天≈17MB/月）、看门狗重启记录死因、FAILED 分类（cmdline 拒绝 vs 写失败）
- [ ] **SKIP 拦截事件写入 stats.log**：当前拦截只进临时 acts 文件，面板看不见「拦了一次杀」，与设计原则「保守默认可见」相悖
- [ ] **发布帖**：效果数据 + 验证矩阵 + 已知限制（诚实清单是社区信任的根基）
- [ ] v1.0 打 tag + 终版发布包 + README 数据更新

## 二期功能（v1.x，按需排期）

- [ ] **激进回收档**：PSI 超阈值 + 内存水位低时按 adj 从高到低回收（`reclaim.aggressive`，出厂关）
- [ ] **FREEZE 名单实现**：点名杀 + 冷却期阻止拉起（协议已定义，执行逻辑未实现）
- [ ] **调参模块**：lmkd `device_config` / minfree / ZRAM（`tuning.enabled`，出厂关，改动可回滚）
- [ ] **面板名单编辑器**：写操作需评估原子性与配置污染风险，晚于一切读功能
- [ ] **阶段二 · AMS hook spike（第 0 步侦查，低风险）**：用 LSPosed 打点模块（只 log 不拦截）定位 **AOSP 标准**的「cached 回收 + Activity trim」调用链（`CachedAppOptimizer`/trim 路径），确认 Oplus 是否旁路；**hook AOSP 点位而非 ColorOS 私货** → 一个 hook 天然覆盖所有 ROM；参考社区 DisableTrimActivities 成熟思路；结论出来后再评估立项性价比
- [ ] **lmkd 裁决（2026-09-29 定案）**：不 hook lmkd（adj=200 已通过官方输入通道覆盖该防线，hook 解的是不存在的问题）；调参（minfree/device_config）留可选开关默认关，日常不碰厂商已调好的参数
- [ ] ~~厂商豁免同步~~ no_frozen 路线已排除；待研究其他 ROM 豁免接口（按 L2 厂商层逐个探测）

## 已知限制（发布帖引用）

- 引擎只管 **`cch*` 缓存态**进程；服务/前台/最近任务态由系统托管（设计如此，面板显示「系统托管」）
- **KILL 动作必须带 `:进程后缀`**（整包封杀请用 FREEZE，协议见名单文件头注释）
- 出厂 KILL 名单**为空**——每条候选须逐条实测，老 A1 (2023) 名单在 2026 年已全部失效（见 [docs/kill-exclusions.md](docs/kill-exclusions.md)）
- **adj=200 保活只覆盖 lmkd 内存压力路径**；AOSP 标准的 AMS cached 回收按 procState 杀、不看 adj（`am_proc_died adj=905` 实锤，「压 adj→杀」同帧完成，2s 轮询窗口不可入）；Oplus Hans 冻结已证无害（收包即解冻）；`no_frozen` 豁免实验阴性已回滚
- **日常冷启的真正解 = 阶段二 AMS hook（AOSP 点位）**；本期定位是「防内存压力杀、防 lmkd 猎杀」，**不承诺防日常 cached trim**
- 对照组事实：微信昨夜同样死亡 15 次——**系统对所有 App 一视同仁，无「微信免疫」**；用户感知差异来自使用频率（常开=Activity 热、挂着=Activity 被 trim）
- **hook 路线已论证排除**：上游 A1 的 libhook_lmkd.so 钩的是 lmkd kill/pidfd，与 adj 同属 lmkd 路径，同样挡不住 AMS/Hans，且引入黑盒二进制维护负担
- 轻负载下模块**安静无感**（设计目标），效果仅在重负载/多任务场景可感知
- Magisk 与 ColorOS 15 理论兼容、未经实机验证

## 文档索引

- 设计 spec：[docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md](docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md)
- v0.1 实现计划（8 任务 43 步，已全部完成）：[docs/superpowers/plans/2026-09-28-memory-engine-v0.1.md](docs/superpowers/plans/2026-09-28-memory-engine-v0.1.md)
- KILL 排除清单：[docs/kill-exclusions.md](docs/kill-exclusions.md)
