# KILL 名单实测排除清单 (2026-09-28, 一加11 / ColorOS 16)

规则: 每条 KILL 候选必须实测通过才可收录; 失败/无意义 → 记录于此, 永不收录。

| 候选 | 实测结果 | 结论 |
|---|---|---|
| com.tencent.mm:toolsmp / :tools | 进程不存在(2026年微信版本已无此进程) | 排除 |
| com.tencent.mobileqq:peak / :tool | 进程不存在 | 排除 |
| com.tencent.mm:appbrand1 | 存活但短命(采样间隙自然退出), 杀了无感知收益 | 排除 |
| com.tencent.mm:push | 杀掉后 **8s 内被系统自动重连**(新 pid 即刻出现), 主进程无恙 | **排除: 安全但无意义**, 反而引入 ~8s 消息延迟窗口 |


## 2026-10-04 增补 (系统服务批次, 一加11)

同批加 4 条进日用名单实测 8 分钟 (13:12→13:20), 结果:

| 候选 | 实测结果 | 结论 |
|---|---|---|
| com.heytap.health:SportDaemonService | 8 分钟被杀 **10 次** (每 60s 撞冷却上限), 杀完秒重拉换 pid; 主进程 com.heytap.health 229MB 不受影响; 期间处于 fg/prev 保护态时被 `SKIP protected_state` 正常拦截 | **排除: 无净收益**, 子进程 60s 即回, 纯耗 CPU/功耗 |
| com.oplus.pantanal.ums:track | 杀 1 次后观察窗内未再出现 | 收录 (用户日用名单) |
| com.heytap.htms:cloudctrl | 杀 1 次后观察窗内未再出现 | 收录 (用户日用名单) |
| com.nearme.instant.platform:provider | 杀 1 次后未再出现 (cch+15) | 收录 (用户日用名单) |

观察与教训:
- **净收益未验证**: 测试期 MemAvailable=7GB (16GB 设备), 内存不吃紧时杀谁都测不出价值; 3 条「只杀 1 次」可能是它们本就低频拉起, 不能证明是被杀怕了。真实收益须等内存压力场景 (参照 2026-09-29 tmpfs 5GB 压力实验) 再测。
- **汇总行 KILLED 口径问题**: `APPLIED/KILLED` 只统计本轮, 杀伤明细看 `KILL pid pkg` 行 — 汇总行显示 0 不等于没杀 (本次排查绕了一圈)。已列入待办: 汇总行补当日累计。
- **SKIP 分类不可见**: exec.sh 收到 SKIP 只计数, `protected_state/whitelist/cooldown/cap` 四类不落日志, 现场只能靠手动跑 policy.sh 复现。已列入待办: SKIP 明细落 stats.log。
- **单进程包 KILL 不适用**: com.android.vending / com.oplus.screenshot / com.oplus.aiunit / com.coloros.colordirectservice 均无 `:` 子进程形态, KILL 无从下手; FREEZE 属整包封杀+拦拉起, 对可能被 bindService/Provider 调用的系统服务风险过高 → 不收录。

## 判定
- 老 A1 (2023) KILL 名单在 2026 年的 App 版本上**全部失效** — 印证 spec「老名单不得照抄」。
- KILL 执行链路本身已验证可用(自建假进程 `com.fake.killme` 被 apply_actions 正确击杀, APPLIED=0 KILLED=1)。
- **出厂 KILL 名单维持空**; 需要时由用户自行添加并自担风险。
