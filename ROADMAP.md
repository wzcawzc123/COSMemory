# COSMemory 路线图

> 状态快照：**2026-09-28 · v0.2 发布就绪**（开发与验证 100% 完成，待日用攒数据后发 v1.0）

## 当前状态

- **v0.2 已交付**：shell 引擎 + KSU WebUI 面板（Vue3 单文件），部署于一加 11 / ColorOS 16 / 16GB / KernelSU
- 发布包：`COSMemory-v0.2.zip`（md5 `5c730f0185d0b10c2fd5a3fd471ad113`）
- **L3 进行中（2026-09-29 首日初检）**：7.5h 纯日用期保活纠正 752 次、零 KILL、零非法行、两次真机重启中保护机制全部自动恢复；微信保活体感有效、QQ 一次冷启动已归因（见下）

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

## 发布前检查清单（→ v1.0）

- [ ] **L3 长期日用数据**：日用几天后分析 `stats.log`——保活纠正成功率、白名单 adj 稳定占比、冷启动体感对比
- [ ] **no_frozen 厂商豁免实验（2026-09-29 已写入，待验证）**：白名单三件套已加入 settings secure `no_frozen`（备份+回滚演练通过）；验证点=明早 events 有无新的 `am_proc_died ... mobileqq` + 体感；有效则并入模块（引擎同步 WHITE→no_frozen，卸载还原）
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
- [ ] **厂商豁免同步**（若 no_frozen 实验成功）：引擎启动时 WHITE 名单同步进 `settings secure no_frozen`，卸载精确还原（含冲突检测：他模块也写此项时提示）

## 已知限制（发布帖引用）

- 引擎只管 **`cch*` 缓存态**进程；服务/前台/最近任务态由系统托管（设计如此，面板显示「系统托管」）
- **KILL 动作必须带 `:进程后缀`**（整包封杀请用 FREEZE，协议见名单文件头注释）
- 出厂 KILL 名单**为空**——每条候选须逐条实测，老 A1 (2023) 名单在 2026 年已全部失效（见 [docs/kill-exclusions.md](docs/kill-exclusions.md)）
- **adj=200 保活只覆盖 lmkd 内存压力路径**；AMS 缓存回收与 Oplus Hans 冻结路径不看 adj（2026-09-29 QQ 冷启动归因实锤：`am_proc_died adj=915`，系统压 adj→秒杀同帧完成，2s 轮询窗口不可入）——厂商豁免 `no_frozen` 是根本解，实验中
- **hook 路线已论证排除**：上游 A1 的 libhook_lmkd.so 钩的是 lmkd kill/pidfd，与 adj 同属 lmkd 路径，同样挡不住 AMS/Hans，且引入黑盒二进制维护负担
- 轻负载下模块**安静无感**（设计目标），效果仅在重负载/多任务场景可感知
- Magisk 与 ColorOS 15 理论兼容、未经实机验证

## 文档索引

- 设计 spec：[docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md](docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md)
- v0.1 实现计划（8 任务 43 步，已全部完成）：[docs/superpowers/plans/2026-09-28-memory-engine-v0.1.md](docs/superpowers/plans/2026-09-28-memory-engine-v0.1.md)
- KILL 排除清单：[docs/kill-exclusions.md](docs/kill-exclusions.md)
