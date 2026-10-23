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

- [x] 写失败测试：临时 SQLite/配置，Claude / Codex endpoint、proxy route 与默认项分开、官方/第三方识别、busy/缺库/不兼容、来源只读、不持久化秘密；余额完整/缺失/负数/非有限/多币种。
- [x] 编译接口与最小骨架后运行失败断言，再实现只读参数绑定查询与金额解析；验证通过。
- [x] 集成 test.sh，记录范围与测试证据并提交。

### Task 2: 查询与状态隔离

**Files:** Create `Sources/DeepSeekBalanceClient.swift`, `Sources/ConnectedAccountState.swift`；Extend `Tests/ConnectedAccounts/main.swift`。
**Interfaces:** `DeepSeekBalanceClient.fetch(connection:completion:)`；`shutdown()`；状态按 connectionID + generation 应用结果，凭据仅在查询内存中解析。

- [x] 先写失败测试：固定 GET `/user/balance`、Bearer 从原配置解析、拒绝重定向、401/429/500、1MiB 上限、取消、连接变更、单次回调、30 秒预算与去重调度。
- [x] 使用 URLProtocol 合成响应测试真实 URLSession 传输；实现有界流式传输与至多两并发，纯状态用测试覆盖过期数据与代际隔离。
- [x] 运行相关测试、完整套件并提交。

### Task 3: 原生玻璃与账户视图

**Files:** Create `Sources/GlassAppearance.swift`, `Sources/ConnectedAccountsView.swift`；Modify `Sources/AppController.swift`, `Sources/CapsuleView.swift`, `Sources/ProviderMark.swift`, `Sources/main.swift`, `Tests/Capsule/main.swift`, `scripts/build.sh`, README、RELEASE_NOTES。
**Interfaces:** 来源连接/读取状态交给 AppController；独立界面构造器消费脱敏模型与闭包；旧平台继续现有查询路径。

- [x] 先使旧黑底像素断言在玻璃外观需求下失败，改为验证比例边界、64 点点击分区、深浅/减少透明度和金额无进度。
- [x] 实现账户/工具/原有平台入口、来源连接选择、固定到菜单栏、金额明细与更新时间；保持一轮查询与缓存。
- [x] 构建截图/离线交互检查，不使用真实金额截图；声明 macOS 15 兼容、26+ 原生分支未实机验证。
- [x] 版本标记本地 1.8.0 / 12，完整套件与通用构建，独立代码审阅，修复后安装到 ~/Applications。
- [x] 从安装版验证真实 DeepSeek 读数、两个 60 秒调度、登录启动与原有 Codex；更新本地交接，保留本地提交，不推送/发布。

## 范围说明

Kimi、GLM、Kilo、Kiro、Grok 的新额度适配、任意 JS、自动切换模型、全局所有钱包汇总不在本次实现范围。原有八个平台通过原入口保留，新增来源中无法查余额的连接明确显示能力限制。

### Task 4: 中英文与统一显示来源（用户追加）

**Goal:** 应用支持完整中文/英文界面，默认跟随 macOS 语言，可在应用中选择“跟随系统 / 中文 / English”，立即生效并持久化；GitHub 项目首页提供明确的中英文介绍和互相切换入口。用户反馈固定/账户/官方套餐多套切换状态混乱，统一成一个显示来源。

**Ownership:** 本任务实现者可修改 Sources、必要构建脚本/资源、Tests、README.md、README.en.md、RELEASE_NOTES.md；不改 CC Switch 配置、系统语言、现有安装版，不推送/发布，不创建其他子代理。控制者负责最终安装、真实轮询、本地交接、推广文案。

**Required behavior:**
- 覆盖账户/工具/官方套餐、连接授权与目录选择、更新检查与安装确认、登录启动/退出、状态与错误、额度周期/金额标签、tooltip/accessibility。平台名、账户/连接名、协议字段、URL、外部配置匹配条件保持原值，不能为翻译改动查询语义。
- 语言偏好只写 QuotaNest 的 UserDefaults。不要触碰 AppleLanguages 或系统设置；未设置时中文系统使用中文，其他系统使用英文。切换语言时，已有缓存成功读数和错误文字也应同步呈现，不能等到下一次查询。
- 使用简单的标准本地化实现；不引入依赖、翻译服务、字符串子串替换器。确保不在读写业务协议时翻译数据。
- 用户反馈操作混乱，最新交互要求覆盖旧 Task 3 的账户/工具/固定模式：弹窗顶部仅有一个“菜单栏显示 / Menu bar shows”选择器。列出八个官方平台（标注“套餐余量 / Subscription quota”，实验平台保留实验标记）和已连接且支持余额的 DeepSeek 配置（标注“API 余额 / API balance”，含 harness 与用户连接名区分多个来源）。选择即同步更新菜单栏与详情；不另设“查看账户”的独立选择，不保留固定/取消固定按钮，不再藏第二个官方平台 picker。可沿用 selectedProvider/pinnedCCSwitchConnection 两个旧偏好实现迁移，但用户界面只有一个当前来源。
- 主界面显示选择器对应的套餐详情或 API 余额详情，保留一次明确的“立即刷新”动作；仅有独立“设置 / Settings”入口。设置中放 CC Switch 连接管理、已连接配置/路由说明、语言、登录启动、应用更新和退出。返回主界面不改变显示来源。连接新来源只增加选择项，不自动更改用户的当前显示。来源丢失时仍可从同一选择器选择官方平台恢复；同一来源被删除或不再支持不能显示旧余额。
- API 单币种不提供伪周期切换；多币种按钮清楚标记切换币种，套餐按钮保留周期切换。用“套餐余量”和“API 余额”区分百分比与金额，不混算。选择官方平台会清除持久化 API pin；选择 API 会设置其 ID 并同步 detail，不依赖其他隐藏状态。
- 保持 64 点胶囊及原功能；英文更长，检查 380 点弹窗和滚动/按钮不溢出。DeepSeek 币种按 CNY/USD 原值保留，不改金额精度。
- README 两版同步覆盖新功能、语言选择、统一来源选择器、版本仍是本地未发布 1.8.0。移除“界面仅中文”、旧黑底/不支持 API 等过期描述；首页第一屏清楚列出中文/English链接、双语简短介绍。不要声称公开 Release 已含新功能。
- 版本保持 1.8.0，build 从 12 升到 13，以区别已安装的单语版本。

**Verification:**
- 先写有意义的失败测试，再实现系统语言选择/显式覆盖/持久化、中文英文代表性静态和动态文本、已有错误随语言变化、协议/用户连接名不被翻译。
- 中英文真实 AppKit 视图渲染与按钮动作、顶部单一选择器可见位置、长英文布局检查；验证选择 Codex→API→Claude 同时改变详情与菜单栏显示状态、来源删除后能从选择器回到官方平台，设置往返/连接新服务不暗改显示来源。将所有测试加入 scripts/test.sh，旧测试若依赖中文，显式设置测试语言，不能依赖宿主语言。
- 完整 ./scripts/test.sh 通过，并编译开发主程序以证明 AppController/所有源文件接通；不要跑通用构建或安装，由控制者审查后执行。
- 本任务改动本地提交；报告包含改动、测试命令结果、边界。报告写本任务 workspace，不要输出凭据或真实金额。


## 最终验收记录

- Task 1–3 完成后按用户反馈由 Task 4 的统一来源选择器替代账户/工具/固定模式；最终版本为本地 1.8.0 / build 13。功能提交 74ade27，未推送、合并 main 或发布。
- 完整 scripts/test.sh 327 条 PASS；最后标题兜底修复后，原生双语相关四组用例再次通过。独立最终审查与修复复审全部关闭。
- 最终主程序/更新助手的 Intel + Apple Silicon 构建与严格签名检查通过；最终安装 bundle 的真实中英文资源、格式化文本验证通过。
- 安装版 DeepSeek 启动与两轮定时查询于 2026-10-23 13:57:25、13:58:25、13:59:25（Asia/Shanghai）成功，60 秒间隔，无错误；Codex 查询、登录启动及既有偏好保留。
- macOS 15.7.7 本机验证；macOS 26 原生玻璃分支、真实管理员更新和国内五个实验适配真实账号不在本次验收结论内。
- 中文小红书更新文案、英文 X 首次介绍文案已按本地预览口径生成，未发布；GitHub About 已在线改为中英双语，两份 README 已在本分支更新。
