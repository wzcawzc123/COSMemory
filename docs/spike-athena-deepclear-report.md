# Spike 报告：ColorOS 深度清理 (Athena deep_clear) 杀链侦查

> 日期：2026-10-09 · 状态：**完成，B-track 已实施（COSGuard v1.2.0）**
> 触发：v1.2.0 上线首夜日用审计 — 白名单死亡 6 例逐例 am_kill 归因
> 方法：am_kill reason 字符串溯源 → 字符串池全 jar 扫描 → jadx 反编译 Athena.apk

## 1. 背景：夜间死亡归因（2026-10-09 03:21-07:56 日志）

6 例白名单死亡定性：
- **2 例 = ColorOS deep_clear**（04:23 抖音主+push，`am_kill reason=o-kill(3) K|C:[84]|U:1|M:1185,646 with deep_clear(kill-res)`）
- 4 例 = 微信子进程自杀/瞬态退出（零 am_kill，任何机制不可救 → 已知边界）
- 0 例 = AMS 标准 cached/empty 杀（16GB 本机缓存配额吃不满；A-track 保险继续保留）
- 昨晚（v1.1.5 期）死亡同查：同样零标准杀 → A-track 在本机暂无猎物，通用化目标保留

## 2. 凶手画像（jadx 反编译 /system_ext/app/Athena/Athena.apk）

- **产地**：`com.oplus.athena`（雅典娜，uid=1000 system），dex 内 `deep_clear` 21 处
- **执行器**：`com.oplus.athena.systemservice.utils.s`（tag=`OplusClearSystemService`）
  ```java
  static boolean e(pid, uid, pkg, ..., deepReason) {
      sb = "o-kill(" + i7 + ")";
      g(pid, uid, i7, sb);        // 仅通知 AMS 记 am_kill 日志(事后记账)
      Process.killProcess(pid);   // ★ 直接 SIGKILL — 在 Athena 进程内, 不经 system_server
      // reason 后缀: sb.append(" with ").append(deepReason) → "with deep_clear"
  }
  ```
- **结论：deep_clear 不经过 OomAdjuster、不过 `onHookKillCacheEmpty` 闸门** —
  原 ③ 计划的"闸门一钩双杀"假设被证据否决（2026-10-09）

## 3. 配置面（无钩子路线的情报，留档备用）

- 统一配置系统：`common/parser/athena/s.java`（getFeatureSwitch/getStringConfigListOrDefault...）
- 本地文件：`getProductXmlStringFormFile(name, "/etc/extension/")` → `/my_product/etc/extension/`；
  本地 vs 云端按 `version` 属性比大小，**本地高版本可压过云端**（w3/y3 解析器实证）
- 相关键：
  - `deep_clear_excessive_mem_black_list` = **必杀名单**（在册直接进杀伤队列，压过一切门槛）
  - `force_protected_list` = 保护名单（filter id 37，挂进候选过滤链）
  - `sys_level_deep_clear_switch` = 深清总开关（默认 true，`n1/f1.java:249` 读取）
  - `sys_periodic_deep_clear_config` = 周期深清（**仅云端**，local=null）
  - 最近任务锁定 = 官方豁免（`n1/k2.java:283 "is locked in recent task"`）
- 本机实况：`/my_product/etc/extension/` 无 clear 配置文件（全默认+云端）；设备侧存在
  `oplus.intent.action.REQUEST_SMART_DEEP_CLEAR` 广播入口（m0.java:659，可用于触发测试）

## 4. 采用路线：B-track 钩子（COSGuard v1.2.0）

选钩子弃配置的理由：配置格式/云端优先级/热加载时机三重未知且失败静默；钩子走已验证基建
（libxposed api102 + guard.conf 桥 644 + Athena uid1000 读写无障碍）。

- **落点**：Athena 进程内 hook `android.os.Process.killProcess(int)` /
  `killProcessGroup(int,int)`（稳定框架 API，抗混淆）
- **决策**：复用 GuardEngine 全链（white→mode→dedup→fuse），reason=`athena o-kill`，
  新规则 `case "athena"`（matchRule）；BLOCK 名单经 bridge 注入（memory.json `block_rules`
  与 bridge.sh 兜底均 +`athena`）
- **fail-open**：pid→包名反解（/proc/pid/cmdline + 去 `:子进程` 后缀）失败即放行；
  任何异常放行；非白名单零开销直通（step2）
- **桥**：guard.conf 644 全球可读（Athena uid1000 可读）；telemetry 600 system=Athena uid 可写
- scope.list 增补 `com.oplus.athena`（需 LSPosed 勾选 + 重启生效）

## 5. 验收判据

1. 重启后 logcat：`entry: onPackageReady athena` + `athena kill hooks installed: 2`
2. 触发/等待 deep_clear：遥测出现 `athena o-kill ... BLOCK` 行，白名单进程存活
3. 观察期：stats.log 白名单 DEATH 中 deep_clear 类归零（对照本报告第 1 节基线）

## 6. 已知边界（诚实清单）

- 微信子进程自杀/瞬态退出：不可救（4/6 例），非本方案范围
- Athena 升级改包名/类名不影响（钩子锚定 framework API）；scope 需随模块更新重新勾选
- AMS 标准杀（A-track）在本机零猎物，保留为通用化保险
