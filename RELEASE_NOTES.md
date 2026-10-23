# QuotaNest 1.8.0

- build 13：完整中文 / English 界面；默认跟随 macOS，可在设置选择跟随系统、中文或 English，立即更新已有读数与错误并保存偏好。
- 顶部统一“菜单栏显示 / Menu bar shows”选择器，八个官方套餐与已连接的 DeepSeek API 余额同步切换胶囊与详情；移除独立账户选择与固定开关。连接新服务、设置往返不暗改当前来源；来源丢失后可直接恢复官方平台。
- CC Switch 连接管理、来源说明、语言、登录启动、更新和退出集中到设置。只读连接已有 Claude Code / Codex 服务，不提供 Key 输入、另存、创建或自动切换。
- 支持 DeepSeek 官方 API 可用余额与充值/赠送明细；同凭据共享正在执行的请求，选择余额显示到菜单栏时不伪造百分比。
- 胶囊与弹窗采用玻璃风格，保留 64 点占用、深浅外观与减少透明度。macOS 15 兼容外观已验证；新 SDK 构建在 macOS 26+ 使用原生弹窗玻璃 API，该分支尚未实机验收。
- 保留一分钟刷新、原有八个平台、应用更新与登录启动设置；来源变更丢弃旧结果，持续查询失败保留过期提示。
- CC Switch 自定义脚本及其他新 API 余额适配尚不支持；GLM、Kimi API、Kilo、Kiro、Grok 仍在后续设计范围。
- 国内五项仍是实验适配，尚未真实账号验证；继续复用各自官方登录，本次未增加它们的 API 余额适配。

macOS 13+；Intel / Apple Silicon 通用构建。使用 ad-hoc 签名，未经过 Apple Developer ID 公证。

## English

- Chinese and English UI, following macOS by default. Change **Settings → Language** instantly, including cached readings and errors.
- One **Menu bar shows** selector controls both the capsule and details. Choose a subscription quota or a DeepSeek API balance, with no separate pin toggle.
- Connect existing Claude Code / Codex configurations from CC Switch in read-only mode. Reuse existing credentials for the fixed official DeepSeek balance endpoint; no key entry, extra key storage, inference requests, routing changes, or custom scripts.
- View available, topped-up, and granted balances. Shared credentials deduplicate concurrent queries; source changes discard obsolete results. Transient failures retain explicitly stale readings.
- A glass UI with light/dark appearances, a 64-point capsule, one-minute quota refresh, application updates, and launch at login.
- Five existing domestic-provider adapters remain experimental and unverified with real accounts. New GLM, Kimi API, Kilo, Kiro, and Grok balance adapters are not included.

macOS 13+; universal Intel / Apple Silicon build. Ad-hoc signed, not Apple-notarized. The macOS 15 glass appearance was tested locally; the macOS 26 native glass branch has not been tested on a physical device.

[中文说明](https://github.com/bloodkilory/QuotaNest/blob/v1.8.0/README.md) · [English documentation](https://github.com/bloodkilory/QuotaNest/blob/v1.8.0/README.en.md)
