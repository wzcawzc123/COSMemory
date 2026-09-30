# Task 0 调研报告 · startProcess 族 hook 点定位（FREEZE spec §4.3）

- 日期：2026-10-01 ｜ 方法：baksmali 解 AOSP `/system/framework/services.jar` classes.dex（AMS-HIT classes.dex + classes3.dex）+ oplus-services.jar smali 交叉引用
- 结论：**可 hook**，主挂点与备选如下。

## 1. 结论表（Task 6 直接消费）

| 键 | 值 |
|---|---|
| `HOOK_CLASS` | `com.android.server.am.ActivityManagerService` |
| `HOOK_METHOD` | `startProcessLocked` |
| 参数类型表（8 参，Xposed 原样） | `String.class, ApplicationInfo.class, int.class, int.class, HostingRecord.class, int.class, boolean.class, boolean.class` |
| 返回 | `ProcessRecord`（拦截 → `setResult(null)`） |
| `PROCNAME_IDX` | **args[1]**（`ApplicationInfo.packageName`，整包语义）；args[0] 为进程名（含 `:子进程` 后缀，FREEZE 整包匹配时须剥后缀） |
| 修饰符 | `final`（包私 final，方法体完整非 native/非 inline）→ Xposed `findAndHookMethod` 反射可达 ✓ |
| `HOOK_SITE_B` | `com.android.server.am.ProcessList.startProcessLocked` 16 参重载（smali 23767 行；主点失效时启用，代价=4 个重载需甄别） |

## 2. 证据

- AMS 定义：`ActivityManagerService.smali:89548` `.method final startProcessLocked(Ljava/lang/String;Landroid/content/pm/ApplicationInfo;ZILcom/android/server/am/HostingRecord;IZZ)Lcom/android/server/am/ProcessRecord;`
- Oplus 调用链存在（`OplusAppStartupManager` 等 5 类引用 startProcessLocked）→ **挂 AMS 主点覆盖 Oplus 启动路径**
- 调用样例：`ActivityManagerService.smali:48141`（AMS 自调）、`ActiveServices.smali:4753`（服务拉起路径）→ `move-result-object` 后按 AOSP 标准模式判 null（`ProcessRecord m == null` 分支返回），**拦截置 null 安全**
- 每次冷启/组件绑定触发一次，频次低（非热循环）

## 3. 挂载 snippet（Task 6 用）

```java
XposedHelpers.findAndHookMethod(
    "com.android.server.am.ActivityManagerService", lpparam.classLoader,
    "startProcessLocked", String.class, android.content.pm.ApplicationInfo.class,
    int.class, int.class, XposedHelpers.findClass("com.android.server.am.HostingRecord", lpparam.classLoader),
    int.class, boolean.class, boolean.class,
    new XC_MethodHook() { /* beforeHookedMethod: pkg=args[1].packageName → FreezeGate.shouldBlock */ });
```

## 4. 风险与回退

- 拦截后调用方判 null 属 AOSP 标准模式（证据 §2）；hook 内异常一律 catch 后放行（spec §6.3）；
- 若实机发现绕过路径（Oplus 定制直启 ProcessList），切 `HOOK_SITE_B`（16 参版）并重跑 T-FREEZE；
- 验证手段：T-FREEZE ②「monkey 拉起 → FREEZE_BLOCK 且进程不存活」即挂点有效性实证。
