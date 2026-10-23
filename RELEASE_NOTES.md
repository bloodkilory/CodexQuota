# QuotaNest 1.9.0

- 首次同时发布 macOS 通用 DMG 与 Windows 11 x64 安装包，附统一 `SHA256SUMS.txt`。
- Windows 支持原生 Codex / Claude 官方套餐及 CC Switch 已有 DeepSeek 官方 API 余额。托盘中心显示数字，外圈显示剩余进度，两者使用平台强调色；悬停查看紧凑额度卡片，点击打开设置，返回详情可切换显示来源、模型、周期或币种。没有桌面悬浮胶囊。
- 两端新增模型/额度组单选：只显示所选模型的额度，各平台分别保存，刷新和重启后保留。自动模式保留原规则；未知额度不借用其他模型的读数。
- Mac build 14：详情宽度缩至 240 点，刷新与齿轮设置图标位于标题右侧；由系统统一绘制弹窗背景、箭头和四角，修复双层圆角。设置表单保留 380 点宽。
- 修复 ZCode 免费 Start Plan 查询，复用官方现有登录及设备信息，按模型区分每日和一次性额度；过滤未来/过期额度，一次性额度显示到期时间。已使用本机免费账号验证，付费 Coding Plan 和其余国内适配仍按实验性范围说明。
- 保留中文 / English、每分钟刷新及官方登录复用。应用更新只检查 GitHub 正式 Release，按平台精确选择安装包并校验 SHA-256。

macOS 13+，Intel / Apple Silicon 通用，ad-hoc 签名、未公证。Windows 11 x64 按用户安装，安装包未使用商业代码签名。Windows 的其他六个官方平台尚未迁移；真实 Windows 11 账号、代理与多屏 DPI 尚待用户验收。Windows Server 2025 CI 已验证安装、升级保留偏好、原生模型单选/托盘悬停/点击与卸载；自动化使用模拟凭据，不能替代真实账号验证。

## English

- The first release with both a universal macOS DMG and a Windows 11 x64 installer, plus one combined `SHA256SUMS.txt`.
- Windows supports native Codex / Claude subscriptions and existing CC Switch DeepSeek official API balances. A provider-colored number and hollow progress ring live in the tray. Hover for compact quota details; click for settings and return to details to choose a source, model, period or currency. No floating desktop capsule.
- Model/quota-group radio buttons on both platforms. Each provider remembers the selected model across refreshes and restarts. Automatic mode retains the previous rule; unknown readings never borrow another model's percentage.
- Mac build 14: compact 240-point details, refresh and gear icons in the title row, and one system-drawn popover backdrop/arrow/corner surface. Settings retains its 380-point form width.
- Fixed free ZCode Start Plan balances using existing official sign-in and device information. Daily and one-time model quotas remain separate; future/expired allowances are excluded and one-time grants show expiry rather than reset. Verified with a local free account; paid Coding Plan and other domestic adapters retain their experimental verification limits.
- Chinese / English UI, one-minute quota refresh, existing official logins, and stable GitHub Release updates with exact per-platform assets and SHA-256 verification.

macOS 13+, universal Intel / Apple Silicon, ad-hoc signed and not Apple-notarized. Windows 11 x64 installs per user; the installer has no commercial code-signing certificate. The other six Mac official providers are not yet available on Windows. Windows Server 2025 CI validates install/update, retained preferences, native UI/tray interactions and uninstall using synthetic credentials. Real Windows 11 accounts, proxies and multi-monitor DPI still need user validation.

[中文说明](https://github.com/bloodkilory/QuotaNest/blob/v1.9.0/README.md) · [English documentation](https://github.com/bloodkilory/QuotaNest/blob/v1.9.0/README.en.md) · [Windows](https://github.com/bloodkilory/QuotaNest/blob/v1.9.0/docs/windows/README.md) · [Feature comparison / 功能对照](https://github.com/bloodkilory/QuotaNest/blob/v1.9.0/docs/windows/feature-parity.md)
