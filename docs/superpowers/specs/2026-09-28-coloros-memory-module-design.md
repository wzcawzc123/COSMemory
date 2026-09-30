# ColorOS 内存管理模块 · 设计文档（spec）

- 日期：2026-09-28
- 状态：已通过用户评审（5 段逐段确认）
- 基准：fork 自 wzcawzc123/A1Memory（上游 OneB1ank/A1Memory，GPLv3）
- 下一步：writing-plans 生成实现计划

## 0. 背景与真相测试结论

原计划「以 A1Memory 二进制为基准做适配」。真相测试（2026-09-28，一加11 / ColorOS 16 / Android 16 / KSU）结论：

- HC_memory 能启动、读配置、写日志，但打印 `This Android version does not support automatic configuration`（内置版本门止于 Android 14）。
- 12 秒 CPU tick 增量 = 0；改名单 / 改配置 / 切前台 / 压内存均无响应（日志零增长、无 /proc fd）。
- 之前观察到的 adj 变化与守护无因果关系（杀掉守护后依旧出现）。
- **判定：会呼吸的尸体。路线 1（只改外壳沿用二进制）已死。**

因此本项目走**路线 2：继承外壳协议，自研 shell 引擎**。

调研补记（同日本机实测）：
- AOSP `ro.lmk.*` 全空；实际走 `device_config lmkd_native`（thrashing_limit_critical=300）、`sys.lmk.minfree_levels` 六档、`lmkd.reinit` 热重启入口。
- Oplus 私有：`persist.sys.lmk.oplus.kill_memleak_process`、`lmkd_super_critical_threshold_{8,12,16}g`、hybridswap/osense memcg、opluspcm。
- ZRAM 10GB 已用 ~4.7GB，swappiness=100；vm 参数正常可写。
- 现有 13 个模块均不碰 lmk/memory，战场干净。
- 性能基准：`dumpsys activity lru` = 12ms（125 个 App 进程 + 状态）；meminfo+PSI+属性 = 19ms/轮；遍历 /proc 全表 ≈ 3200–5167ms（不可用）。

## 1. 定位与目标

> 「A1 内存管理的精神续作」：**引擎通用于 Android 12+（依赖均为 AOSP 标准件：dumpsys lru/oom_score_adj/PSI，零 hook 零厂商件）**，已实测 ColorOS 15~16（一加/OPPO/realme）；白名单保活 + 白名单外智能回收，KSU/Magisk（兼 Apatch）双端，效果可观测、可验证，面向社区发布。其他 ROM 免装可用（哨兵+降级保证安全试用），效果按验证矩阵滚动扩展。
> （2026-09-29 定位修订：通用性三层架构 AOSP 基线/厂商叠加/验证矩阵见 ROADMAP §通用性架构；lmkd 不 hook（adj 输入通道已覆盖）；AMS hook 留阶段二且目标为 AOSP 标准点位。）

核心目标 **C**：名单内保活、名单外聪明回收（保活与省内存不冲突，名单是权衡工具）。

### 一级需求（与引擎平级，社区成功公式）

1. **保守默认**：出厂白名单宽、KILL 少、激进选项显式开关
2. **可见状态面板**：把不可见的保活/回收变成可见数字
3. **可验证效果**：每个宣称都可用 dumpsys/meminfo 前后对比证明

### 非目标

- 不做性能调优炫技（Oplus 已调过，调参模块默认关）
- 不承诺「16G 变 32G」；轻负载下模块应安静
- 不 hook、不 zygisk、不改系统分区

## 2. 架构总图

```
模块包
├── module.prop              # 新 id/名称/版本（不冒充原作者）
├── customize.sh             # 安装：名单初始化、KSU/Magisk 检测、旧配置迁移
├── service.sh               # 引擎守护入口 + 看门狗
├── post-fs-data.sh          # 早期属性（如需要）
├── system.prop              # lmkd/oplus 属性（继承+按 CO15/16 修订）
├── uninstall.sh             # 干净卸载、全部还原
├── engine/                  # ★ 新写 shell 引擎（替代 HC_memory）
│   ├── memory.sh            # 主循环：状态机
│   ├── snapshot.sh          # dumpsys lru + meminfo/PSI 采集
│   ├── policy.sh            # 决策：保活/回收/冻结
│   └── exec.sh              # 执行：写 adj / 杀进程 / 调参
├── config/
│   ├── memory.json          # 参数（继承 A1 协议 + 新字段）
│   ├── 名单列表.conf          # WHITE/KILL/FREEZE，出厂保守
│   └── Language/            # 多语言（继承五语框架）
├── panel/                   # ★ 状态面板（只读 stats，不参与决策）
│   └── stats.sh + WebUI
└── META-INF/                # KSU/Magisk 标准安装器
```

进程模型：
1. 引擎守护（常驻 shell 状态机；每轮全开销 ≤30ms，已实测）
2. 面板服务（按需起，只读 stats.log；面板崩不影响引擎）

数据流：`snapshot(12ms) + meminfo/PSI(19ms) + 名单/config → policy → exec → stats.log → panel`

### 设计原则

1. 只读快照、不遍历 /proc 全表
2. 引擎与面板解耦（单向追加日志）
3. 保守默认
4. 全部可回滚（动作记 before 值，卸载还原）
5. 署名与许可：NOTICE 标明基于 HChai/OneB1ank A1Memory 二次开发，继承 GPLv3；新仓库、新 id、不覆盖上游

## 3. 引擎逻辑（状态机）

```
SLEEP（等待）
  触发：① 前台切换（2s 轻探）② PSI some avg10 > 阈值
        ③ 距上次全量巡检 > 60s（兜底）④ 名单/config inotify
→ SNAPSHOT（~30ms：dumpsys lru + meminfo + PSI）
→ POLICY（纯计算）→ EXECUTE（只做变化，记 before + stats）→ SLEEP
```

### 决策一 保活（WHITE）
- 退后台的白名单 App → `oom_score_adj = 200`（默认，中档；不设 0）
- 每轮仅在偏离目标值时写回（施压式保活，容忍 Oplus memcg 调走）

### 决策二 回收（KILL + 智能兜底）
- 保守档（默认开）：杀名单点名的 `包名:子进程`
- 激进档（默认关）：PSI 超阈值 + MemAvailable 低于水位时，回收 adj≥900 且不在白名单者，从高到低杀到压力回落
- 杀前三重检查：非白名单 → 非前台/可见 → 冷却期外

### 决策三 调参（默认关）
- 日常不碰 Oplus 参数；一期仅只读监测 + 报告；改动必须可还原

### 安全阀
- 单轮击杀上限（默认 5）；同进程冷却 60s
- 永不触碰：系统进程、persistent、白名单、前台
- 看门狗：引擎异常退出 30s 内由 service.sh 重启并记 stats.log

## 4. 名单协议与配置

目录：`/sdcard/Android/$MODULE_ID/`，`$MODULE_ID` 取自 module.prop 的 id（安装期确定，与模块同名同目录，便于卸载清理）；不沿用上游的 `/sdcard/Android/HChai/`。
语法兼容 A1（WHITE/KILL/`{}`/`#`），解析容错：非法行跳过 + 警告，不连坐失效。

```
{
WHITE com.tencent.mm            # 保活
KILL  com.tencent.mm:toolsmp    # 点名杀子进程
FREEZE com.xxx.bloatware        # 新增：杀 + 冷却期内阻止拉起
}
```

出厂名单：WHITE 国民级应用；KILL 仅收录逐条实测无副作用者（老名单 2023 年版不得照抄）；FREEZE 出厂空。

`memory.json` 字段分组（英文键，中文文档）：

```json
{ "project": {},
  "keepAlive": { "adj": 200, "enforce": true },
  "reclaim": { "aggressive": false, "psiThreshold": 5.0,
               "maxKillPerRound": 5, "cooldownSec": 60 },
  "freeze": { "enabled": true },
  "tuning": { "enabled": false },
  "log": { "path": "", "level": "info" },
  "panel": { "port": 8085 } }
```

安装时迁移旧 `memory.json`（已知字段迁移、未知字段保留）。inotify 热更新，改完下一轮生效。
多语言继承五语框架，一期保证中英。

## 5. 兼容层

### Root 框架
- 引擎纯 shell，不依赖框架特性 → 兼容面小
- busybox 探测：KSU `/data/adb/ksu/bin/busybox`、Magisk `/data/adb/magisk/busybox`、Apatch `/data/adb/ap/`，`ASH_STANDALONE=1`
- system.prop 与标准 META-INF 安装器两端等价（沿用已验证模板）
- 验收：KSU 与 Magisk 各装一次（未实测分支在发布物中如实标注）

### ColorOS 15/16：能力探测，不猜版本
启动时 `cap_probe()`：
- dumpsys lru 可解析？→ 否则降级 `dumpsys activity processes`（42ms）
- PSI 可读？→ 否则退化 meminfo 阈值
- oom_score_adj 可写（写后读回验证）？→ 保活能力
- device_config lmkd_native / lmkd.reinit 可写？→ 调参能力
- `persist.sys.lmk.oplus.*` 存在？→ oplus 扩展

能力缺失 → 对应功能静默关闭 + 面板显示「本机不支持 XX」（降级可见，不做无感尸体）。

### dumpsys 格式风险（命脉）
1. 宽松正则解析；未知状态码归「保守区」（不杀不改）
2. 格式哨兵：命中率 <50% → 报警 + 面板红字 + **停止一切写操作**（宁停不错）
3. 发布分级：已验证 / 未验证（风险自担）

### 模块共存
- 不挂载系统、不改 lmkd 二进制、不 zygisk → 与现有模块零冲突面
- 属性被其他模块覆盖时面板提示

## 6. 验证方案

只认行为证据，不认日志自嗨：

- L1 存活：进程存在 + CPU tick（空闲近 0，事件后有计算）
- L2 动作：因果对照（守护开/关两段 adj 对比，方法即本次 exp_adj 系列）
- L3 效果：冷启动计数、可用内存、PSI 前后面板可见
- L4 破坏性：错配名单/压内存 → 不杀系统、不死循环、看门狗生效

验证矩阵：本机（一加11/CO16/16GB/KSU）全量深度；8GB/分辨率差异走配置分档；CO15 与 Magisk 无实机则如实标「未验证」。

### 发布节奏
```
v0.1 引擎跑通 + L1/L2
v0.3 面板 + 保守出厂名单（KILL 逐条实测）
v0.5 能力探测/降级 + L4 安全阀
v1.0 发布帖：效果数据 + 验证矩阵 + 已知限制
```

### 仓库落地
- fork 仓库作上游参照（协议/多语言/LICENSE）
- 新模块新仓库、新 id；NOTICE 写明二次开发关系
- spec 通过后 → writing-plans 出实现计划
