# 面板名单编辑器 设计 (list-editor)

日期: 2026-10-01 | 状态: 待审 | 关联: freeze-design, cosguard-design, aggressive-reclaim-design
版本规划: 模块 v0.7.0 + COSGuard APK 随项发版

## 1. 背景与目标

名单页 ListView 目前只读 (parseListConf 展示 WHITE/KILL/FREEZE 三组)。本项让面板成为名单的
一等编辑入口: 三组可增删、kill 历史一键加 FREEZE、已装应用选择器 (应用名+图标)。

非目标: 批量导入导出; 名单版本历史; 多用户并发编辑 (单 WebView 前提); hooks 之外的引擎决策改动。

## 2. 现状架构 (查证结论, 2026-10-01)

- 单一事实源: /sdcard/Android/COSMemory/名单列表.conf (LIST_PATH 可覆盖)。
  行式: `WHITE <pkg>` | `KILL <procName>` | `FREEZE <pkg>[:group]`; 注释#/花括号/空行跳过;
  awk 校验同源 engine/lists.sh parse_lists; D4 冲突 (WHITE∩FREEZE) 双向剔除并计 bad。
- 前端通道: KSU WebUI 模式。ksu/WebUIX/mmrl.exec(cmd) 执行 root shell, execRead=(cmd)|base64
  回读 (panel/src/composables/ksu.ts)。无独立 HTTP 服务。
- 引擎生效: engine/memory.sh 主循环每轮 eval $(parse_lists conf) → 引擎对 conf 近实时。
  KILL 消费=plan_reclaim 精确等值匹配进程名 (快照 pkg 字段带 :后缀); WHITE 有 pkg:* 子进程通配豁免。
- hook 生效: service.sh `guard_bridge()` 从 conf+memory.json 生成 /data/system/cosmem/guard.conf
  (tmp+mv 原子, 644 system:system); COSGuard ConfigStore 5s mtime 热加载, fail-open。
- kill 历史: engine/guard_stats.sh 聚合 telemetry → killEvents JSON {ts,pkg,rule,act,reason},
  DefenseView 已渲染, 数据源具备。

## 3. 范围

In:
- S1 ListView 编辑模式 (显式进入/退出): 行级删除 + 每组新增表单。
- S2 shell 写入层 engine/listedit.sh: list_add/list_del, 原子写, 与 parse_lists 同源校验,
  D4 冲突前端拦截 (返回结构化错误, 不落盘)。
- S3 生效链: 写 conf 后调用 guard_bridge() 即时再生成 (引擎循环自然重读, hook ≤5s 热载)。
- S4 应用选择器: COSGuard 新增 AppCatalog → /data/system/cosmem/apps.json (pkg,label,system,
  third-party 全量; icon 逐包 /data/system/cosmem/icons/<pkg>.png), 选择器单次 exec 批量回读。
- S5 DefenseView killEvents 行内「加 FREEZE」联动。
Out: KILL 的 :后缀语义改动 (维持进程名精确匹配, 出厂空+逐条实测门槛不变); guard 决策链改动。

## 4. 详细设计

### 4.1 前端编辑模式 (S1)
- ListView 右上「编辑/完成」切换。编辑态: 每行出现删除钮 (点按弹二次确认, 无手势),
  每组卡片尾部「+ 新增」展开行内表单。
- 表单字段按组: WHITE=包名; KILL=包名+进程后缀 (如 :push, 拼接为 pkg:后缀, 后缀必填);
  FREEZE=包名+可选组下拉 (现有 conf 内组集合+自定义)。
- 校验 (前端, 与 listconf 同源正则): 包名 `[a-zA-Z][a-zA-Z0-9._]+`, 后缀/组非空且无空白。
  重复 (同组已存在) 与 D4 冲突 (目标已在另一组) 前端即拦并提示具体原因。
- 每次增/删 = 一次 execRead(listedit.sh 命令) → 成功后重新拉取 conf 原文刷新;
  失败展示解析后的 ERR 文本。编辑态保留至用户点「完成」。
- 选择器: 表单内「从已装应用选」→ 单次 execRead 取 apps.json+可见项 icon → 搜索过滤
  (按 label/pkg) → 点选回填表单。系统应用仅 label (无 icon 行, 用首字母占位)。

### 4.2 写入层 (S2) — engine/listedit.sh
- `list_add <WHITE|KILL|FREEZE> <target>` / `list_del <group> <target>`,
  CONF=${LIST_PATH:-默认}。流程: 校验 group/target 格式 → 复制 conf 至 tmp →
  awk 定位 (del: 行首 action+target 精确匹配删除; add: 在末条同组行后插入,
  无同组行则插到收尾 } 前, 都没有则追加末尾) → 对 tmp 跑 parse_lists 验证
  (bad 不增、无新 conflict) → mv 原子替换 → 调 guard_bridge → 输出 `OK`。
- 失败输出 `ERR:<code>` (badfmt|dup|conflict:<pkg>|parsefail|iofail), 不落盘。
- KILL dup 检测按整行 target; FREEZE/WHITE 按包名。guard_bridge 调用失败不回滚 conf
  (文件已是新态, 引擎循环自会重读; hook 侧下次 bridge 再生成补上) — 记录 WARN 到输出。

### 4.3 生效链 (S3)
写 conf (原子) → guard_bridge() 再生成 → 引擎: 下轮主循环 eval 即得新名单;
hook: ConfigStore ≤5s mtime 热载 guard.conf。FREEZE 另受 freeze.enabled 开关门
(bridge 只在开关开且名单非空时出行 — 维持现语义, 编辑 FREEZE 组时前端提示当前开关状态)。

### 4.4 AppCatalog (S4) — COSGuard
- 新类 AppCatalog: Context.getPackageManager().getInstalledPackages(0) →
  每包 {pkg, label, third} 写 apps.json; icon PNG 存 icons/<pkg>.png (仅 third-party 预生成,
  系统应用不生成)。原子写 tmp+mv, 与 guard.conf 同目录 (775 system:system, 文件 644)。
- 时机: HookMain 初始化延迟 30s 首建 (避开开机高峰); mtime 检查 apps.refresh 触发文件
  (shell touch 后 ≤10s 重建, 允许用户装/卸应用后手动刷新); 每 24h 兜底重建。
- 失败 fail-soft: apps.json 缺失/解析失败 → 选择器降级为手打包名模式 (提示不可用原因),
  不影响名单页主流程与 hook 决策。
- 前端单次 execRead: `cat apps.json` + 对所选行逐包 base64 cat icon (首屏上限 30 包,
  其余滚动按需) — 具体批量协议在 plan 定, 约束: 一次交互 ≤2 个 exec 调用。

### 4.5 kill 历史联动 (S5)
DefenseView killEvents 每行新增「加 FREEZE」: 取行 pkg → 复用 S2 list_add FREEZE <pkg>
(同校验/D4 流程) → 成功行内变「已加」。act≠kill 的行不显示该钮 (仅实杀记录可拉黑)。

## 5. 错误处理

- 一切写路径 fail-safe: 校验不过不落盘; parse 验证不过不落盘; mv 原子防半写。
- guard_bridge 失败不回滚 conf (§4.2), 输出带 WARN; 引擎/hook 任一侧短暂不一致可被
  下轮循环/下次 bridge 自愈, 与全链 fail-open 原则一致。
- 前端 exec 失败/空输出: 保留编辑态, 提示重试; conf 原文刷新失败沿用旧渲染。
- 输入长度上限: target ≤128 字符; 每次操作 conf 总行数 ≤500 (超出拒绝新增, 防误灌)。

## 6. 测试计划

- shell (listedit): add/del 三组; 格式保持 (注释/花括号/顺序); D4 冲突拒绝且原文件不变;
  dup 拒绝; 坏格式拒绝; parsefail 回滚; guard_bridge 调用 (mock); 行数上限; KILL 后缀拼接。
- vitest: ListView 编辑模式 (进入/退出, 表单校验矩阵, D4/dup 提示, 成功刷新/失败保态);
  killEvents 联动钮可见性规则。
- hook JUnit: AppCatalog 解析 (原子写/icon 缺失 fail-soft/触发文件重建)。
- 回归: 现有 shell 11 套 + vitest 38 + cosguard 34 全绿。
- 真机 e2e: 面板加/删一条 → conf 变 → guard.conf 变 (≤5s) → hook 日志热载确认;
  选择器真机取数; 一键拉黑全链。

## 7. 发布

模块 v0.7.0 (panel+engine+打包) + COSGuard APK 新版 (AppCatalog)。沿用 pack_release.sh,
发布包归档 /storage/emulated/0/内存管理模块/ (旧版入 旧版/)。署名规范随既有 README。
