# CC Switch、DeepSeek 与玻璃界面实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 安装一个可复用 CC Switch 现有 DeepSeek 配置查询余额、使用玻璃外观的本机版本。

**Architecture:** 保留八个平台及其客户端；新增只读来源连接器与 DeepSeek 金额模型，通过连接 ID 管理状态。账户/工具视图使用同一个缓存，固定项决定胶囊显示，金额不伪造百分比。外壳采用公开 AppKit 材质，新系统在可编译且可用时使用原生 Liquid Glass。

**Tech Stack:** Swift 5 mode、AppKit、SQLite3、Foundation URLSession、CryptoKit；macOS 13+。

**Spec:** `docs/superpowers/specs/2026-10-23-connected-accounts-design.md`；用户将本次范围限定为 CC Switch + DeepSeek + 玻璃界面 + 本机安装。

## Global Constraints

- 不提供 Key 输入，不创建或另存 Key；首次主动连接来源后读取已有配置，只查询固定 DeepSeek 官方 origin。
- SQLite 只读，busy timeout 200ms；不改外部 schema、路由、登录、Clash 配置，不运行脚本/helper。
- 60 秒刷新；同池合并请求，最多两项同时查询；30 秒以内的总预算、瞬态最多一次重试，429 尊重 Retry-After。
- 64 点胶囊，金额/百分比分开；真实余额不写公开文档或 fixture。
- 保留更新功能、登录启动、八个原有平台及实验标记。不推送或发布。

## Review Focus

- SQLite 中旧默认配置与 live route 不同：界面只标已配置/路由配置，不假称当前所有会话。
- 连接凭据或 endpoint 在查询中变化：清除错误归属并丢弃旧代结果。
- 非官方服务/占位凭据/任意查询脚本：不能将凭据发送到错误 origin。
- total/granted/topped-up：以总额为主、组成项为明细，不重复求和。
- 明亮/深色/减少透明度、金额溢出：可读且不会出现假进度，按钮范围不变。

### Task 1: 只读来源与余额模型

**Files:** Create `Sources/CCSwitchStore.swift`, `Sources/DeepSeekBalance.swift`, `Tests/ConnectedAccounts/main.swift`；Modify `scripts/test.sh`。
**Interfaces:** `CCSwitchStore.discover() -> [CCSwitchConnection]`；`credential(for:) -> CCSwitchCredential`；`DeepSeekBalance.decode(Data)`，金额 Decimal；连接发现对象无凭据。

- [ ] 写失败测试：临时 SQLite/配置，Claude / Codex endpoint、proxy route 与默认项分开、官方/第三方识别、busy/缺库/不兼容、来源只读、不持久化秘密；余额完整/缺失/负数/非有限/多币种。
- [ ] 编译接口与最小骨架后运行失败断言，再实现只读参数绑定查询与金额解析；验证通过。
- [ ] 集成 test.sh，记录范围与测试证据并提交。

### Task 2: 查询与状态隔离

**Files:** Create `Sources/DeepSeekBalanceClient.swift`, `Sources/ConnectedAccountState.swift`；Extend `Tests/ConnectedAccounts/main.swift`。
**Interfaces:** `DeepSeekBalanceClient.fetch(connection:completion:)`；`shutdown()`；状态按 connectionID + generation 应用结果，凭据仅在查询内存中解析。

- [ ] 先写失败测试：固定 GET `/user/balance`、Bearer 从原配置解析、拒绝重定向、401/429/500、1MiB 上限、取消、连接变更、单次回调、30 秒预算与去重调度。
- [ ] 使用 URLProtocol 合成响应测试真实 URLSession 传输；实现有界流式传输与至多两并发，纯状态用测试覆盖过期数据与代际隔离。
- [ ] 运行相关测试、完整套件并提交。

### Task 3: 原生玻璃与账户视图

**Files:** Create `Sources/GlassAppearance.swift`, `Sources/ConnectedAccountsView.swift`；Modify `Sources/AppController.swift`, `Sources/CapsuleView.swift`, `Sources/ProviderMark.swift`, `Sources/main.swift`, `Tests/Capsule/main.swift`, `scripts/build.sh`, README、RELEASE_NOTES。
**Interfaces:** 来源连接/读取状态交给 AppController；独立界面构造器消费脱敏模型与闭包；旧平台继续现有查询路径。

- [ ] 先使旧黑底像素断言在玻璃外观需求下失败，改为验证比例边界、64 点点击分区、深浅/减少透明度和金额无进度。
- [ ] 实现账户/工具/原有平台入口、来源连接选择、固定到菜单栏、金额明细与更新时间；保持一轮查询与缓存。
- [ ] 构建截图/离线交互检查，不使用真实金额截图；声明 macOS 15 兼容、26+ 原生分支未实机验证。
- [ ] 版本标记本地 1.8.0 / 12，完整套件与通用构建，独立代码审阅，修复后安装到 ~/Applications。
- [ ] 从安装版验证真实 DeepSeek 读数、两个 60 秒调度、登录启动与原有 Codex；更新本地交接，保留本地提交，不推送/发布。

## 范围说明

Kimi、GLM、Kilo、Kiro、Grok 的新额度适配、任意 JS、自动切换模型、全局所有钱包汇总不在本次实现范围。原有八个平台通过原入口保留，新增来源中无法查余额的连接明确显示能力限制。
