# Spike 报告：AMS 杀进程链侦查（阶段二·第 0 步）

> 日期：2026-09-29 · 状态：**第 1 阶段完成（进程杀链源码级钉死）**，Activity trim 留第 2 阶段
> 方法：jadx 反编译设备真实 `services.jar`(39.9MB/4dex) + `oplus-services.jar`(26MB/2dex)，锚点追踪
> 本报告为立项决策依据（spike 产出=证据，非实现）

## 1. 核心发现：进程杀链（源码级完整）

**文件**：`com/android/server/am/OomAdjuster.java` → `updateAndTrimProcessLSP()`（:1110，AOSP 标准方法）

```
超量杀总开关:
  doKillExcessiveProcesses = shouldKillExcessiveProcesses(now)
      && !mOomAdjusterExt.shouldRestrictCacheKill()      ← Oplus 扩展可禁
  + PROACTIVE_KILLS_ENABLED (AOSP swap低时主动杀)

LRU 尾部遍历(最旧缓存先死) → 按 procState 分组计数 → 超限即杀:

  cached超限 (:1203-1206):
    if (numCached - lastCachedGroup > cachedProcessLimit)
        if (!mOomAdjusterExt.onHookKillCacheEmpty(app))          ← ★闸门: 返回true=阻止
            app.killLocked("cached #N", "too many cached", 13, 2, true)

  empty超时 (:1225): killLocked("empty for Ns", "empty for too long", ...)
  empty超限 (:1232): killLocked("empty #N", "too many empty", ...)
```

**这就解释了压力实验的全部死亡**（800-985 档、按 LRU 序、`am_proc_died` procState=19/10）——
**按 procState+LRU 限额杀，不看 adj**（我们此前的实验归因与源码完全吻合）。

## 2. Oplus 改造面评估

- OomAdjuster 内有 osense 扩展（`mUserAwareManagerExt`、trace `updateOomAdj_oplusAdjust`）
- **但核心杀链未被旁路**——仍走 AOSP `updateAndTrimProcessLSP`，Oplus 仅通过 Ext 接口注入策略 ✓
- **`IOomAdjusterExt` 全套预留钩子**（Oplus 自己的接口面，稳定）：
  | 钩子 | 语义 |
  |---|---|
  | `onHookKillCacheEmpty(app)` | **杀前闸门，true=阻止（本 spike 核心）** |
  | `checkCchKillCycle(...)` | 每轮杀循环回调（带限额上下文） |
  | `shouldRestrictCacheKill()` | 超量杀总开关 |
  | `hookEndTrimProcess()` | trim 结束回调 |
- 实现类：`com.android.server.am.OomAdjusterExtImpl` + `OplusOomAdjusterService`（oplus-services.jar 同包注入，ExtLoader 机制）
- **闸门现有实现（smali 源码级确认）**：
  ```java
  OomAdjusterExtImpl.onHookKillCacheEmpty(app):
      if (athena.skipAmsEmptyKill(app.getWindowProcessController())) return true;   // Athena 路径1
      return OplusAthenaAmManager.getInstance().skipCacheEmptyKill(app);           // Athena 路径2
  ```
  → **Oplus 已在此实现一套免死机制**（雅典娜管理器判定），读的是 `mSkippedCaccProcess`（**运行时 Set，动态填充**，填充源在 Athena 内部决策逻辑）
  → **配置路线证据不足**（非静态名单文件，settings 写入无法触达）；**hook 路线确立**：在该方法返回前拦截叠加即可，不破坏现有逻辑

## 3. Hook 方案（双轨，待立项）

**轨道 A · 通用轨（AOSP 标准点，全 ROM 适用）**：
- Hook `ProcessRecord.killLocked(String, String, int, int, boolean)`，**按 reason 过滤**：
  `"too many cached"` / `"too many empty"` / `"empty for too long"` + 包名白名单 → 拦截
- killLocked 是 AOSP 标准方法、reason 是 AOSP 原味文案（本 jar 已证实）→ **跨 ROM 通用**
- 与已验证的 lmkd/adj 路径正交，覆盖 AMS 这条缺失防线

**轨道 B · ColorOS 优化轨（更稳）**：
- Hook `OomAdjusterExtImpl.onHookKillCacheEmpty(ProcessRecord)` 白名单→return true
- 优点：Oplus 自家接口面、带 ProcessRecord 上下文；缺点：仅 ColorOS 有效（非 Oplus ROM 无此类）

**建议**：实现走轨道 A（通用），ColorOS 上可叠加轨道 B 做双保险。

## 4. 风险与缺口

- [x] `OomAdjusterExtImpl.onHookKillCacheEmpty` 现有实现**已读**（baksmali 突破 jadx OOM）：Athena 动态 Set 判定，hook 叠加安全（返回前拦截，不触碰其内部逻辑）
- [ ] Activity trim 入口未定位（`destroyIfPossible` 三处已定位：TaskFragment/ActivityTaskSupervisor/Task，均非内存 trim 路径）；**但根因链指向进程死连带**（QQ 365→23414 换代=进程死过→Activity 消失）——**挡进程杀可能已解决全部冷启**，trim 可后置验证
- [ ] 打点验证：hook 点位需 LSPosed 打点实测（只 log 不拦截）确认调用频率与参数

## 5. 性价比初判

- 可行性：**高**（点位源码级确认、双轨设计覆盖通用性、LSPosed 构建能力现成=qalink 工程模板）
- 风险：system_server hook 的稳定性要求高；Oplus 升级改 Ext 实现（轨道 A 不受影响）
- **结论：值得立项**（2026-09-29 定案）——闸门语义源码级确认、Oplus 旁路排除（杀链未被改造）、双轨点位就绪、构建能力现成（qalink 模板）；第 1 步 = LSPosed 打点模块验证调用频率与参数
