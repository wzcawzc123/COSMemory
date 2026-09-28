<div align="center">
<h1>COSMemory 内存管理</h1>
<p><b>ColorOS 15/16 · 白名单保活 + 名单外智能回收 · KernelSU / Magisk 模块</b></p>
<p>作者：<b>是你吗薰儿</b> · 基于 <a href="https://github.com/OneB1ank/A1Memory">HChai/OneB1ank 的 A1Memory</a> 二次开发 (GPLv3)</p>
</div>

## ✨ 功能

- **白名单保活**：`WHITE` 名单内应用退后台后，缓存态 adj 施压式拉至 200——切回去更少冷启动转圈
- **智能回收**：`KILL` 名单点名清理流氓子进程（必须带 `:进程后缀`），单轮上限 + 60s 冷却，防杀疯
- **出厂保守**：白名单含微信/QQ/抖音，KILL 名单出厂为空——每条候选须逐条实测才收录
- **哨兵保护**：进程快照格式异常（解析率 <50%）立即停机零写入，宁停不错
- **看门狗**：引擎崩溃 30 秒内自动拉起，事件全程落日志
- **能力探测**：启动时探测 6 项系统能力，缺失项面板可见、对应功能自动降级
- **WebUI 面板**：KernelSU 内置浏览器直开，Vue3 单文件（~87KB），奶油风格、只读状态面板

## 🏗 技术特点

- **纯 shell 引擎**：无二进制、无 hook、无 zygisk、不挂载系统分区——与其它模块零冲突面
- **快照式架构**：`dumpsys activity lru`（12ms）替代遍历 `/proc`（3200ms），每轮全开销 ≤30ms
- **全部可回滚**：每个 adj 改动记录原始值，卸载自动还原
- **KSU/Magisk 双端**：标准模块结构，busybox 自适应探测

## 📱 面板（KernelSU WebUI）

模块详情 → 打开，即可看到：引擎状态、今日保活/回收统计、白名单实时 adj、六项能力探测、异常监控与引擎日志。纯只读设计——面板崩溃不影响引擎。

## 📦 安装

1. KernelSU 管理器安装 `COSMemory-vX.X.zip`，重启
2. 名单文件：`/sdcard/Android/COSMemory/名单列表.conf`（改完下一轮自动生效，无需重启）
3. 面板：模块详情页 → 打开 WebUI

## ⚠️ 支持范围（诚实清单）

| 环境 | 状态 |
|---|---|
| 一加 11 / ColorOS 16 / 16GB / KernelSU | ✅ 已实机验证 |
| Magisk 端 | ⚠️ 理论兼容，无实机验证 |
| ColorOS 15 | ⚠️ 理论兼容，无实机验证 |
| 其他机型 / 8GB | ⚠️ 未验证，风险自担 |

详细路线与已知限制见 [ROADMAP.md](ROADMAP.md)。

## 📄 文档

- [路线图](ROADMAP.md) · [设计 spec](docs/superpowers/specs/2026-09-28-coloros-memory-module-design.md) · [KILL 名单实测排除清单](docs/kill-exclusions.md)
- 上游项目：[OneB1ank/A1Memory](https://github.com/OneB1ank/A1Memory)（外壳协议源自上游，引擎为本项目重写）

## 📜 许可

GPLv3，详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
