# KILL 名单实测排除清单 (2026-09-28, 一加11 / ColorOS 16)

规则: 每条 KILL 候选必须实测通过才可收录; 失败/无意义 → 记录于此, 永不收录。

| 候选 | 实测结果 | 结论 |
|---|---|---|
| com.tencent.mm:toolsmp / :tools | 进程不存在(2026年微信版本已无此进程) | 排除 |
| com.tencent.mobileqq:peak / :tool | 进程不存在 | 排除 |
| com.tencent.mm:appbrand1 | 存活但短命(采样间隙自然退出), 杀了无感知收益 | 排除 |
| com.tencent.mm:push | 杀掉后 **8s 内被系统自动重连**(新 pid 即刻出现), 主进程无恙 | **排除: 安全但无意义**, 反而引入 ~8s 消息延迟窗口 |

## 判定
- 老 A1 (2023) KILL 名单在 2026 年的 App 版本上**全部失效** — 印证 spec「老名单不得照抄」。
- KILL 执行链路本身已验证可用(自建假进程 `com.fake.killme` 被 apply_actions 正确击杀, APPLIED=0 KILLED=1)。
- **出厂 KILL 名单维持空**; 需要时由用户自行添加并自担风险。
