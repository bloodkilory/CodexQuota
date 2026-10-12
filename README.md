<p align="center"><img src="assets/quotanest.png" width="136" alt="QuotaNest icon"></p>
<h1 align="center">余度 QuotaNest</h1>
<p align="center"><b>所有 AI 余量，一眼有数。</b><br>AI subscription quotas, right in your Mac menu bar.</p>
<p align="center">
<img src="https://img.shields.io/badge/macOS-13%2B-111827?logo=apple&logoColor=white" alt="macOS 13+">
<img src="https://img.shields.io/badge/Universal-Intel%20%2B%20Apple%20Silicon-06b6d4" alt="Universal binary">
<img src="https://img.shields.io/badge/Swift-Native-f97316?logo=swift&logoColor=white" alt="Native Swift">
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-8b5cf6" alt="MIT License"></a>
</p>
<p align="center"><a href="#安装">安装</a> · <a href="#连接账号">连接账号</a> · <a href="#使用">使用</a> · <a href="README.en.md">English</a></p>

---

QuotaNest 是一款轻量的原生 macOS 菜单栏应用，将 **Codex、Claude Code 和 Google Antigravity** 的套餐余量放进一颗小胶囊。每 3 分钟刷新，点击即可查看各额度窗口和重置时间。

- **一眼知道还能用多少**：显示剩余百分比，彩色背景宽度随剩余比例变化，已用部分为黑色。
- **三个平台，一个入口**：切换平台，独立查询，记住上次选择。
- **沿用官方登录**：通过本机官方 CLI 或订阅 OAuth 查询，不需要把密钥粘贴给本应用。
- **原生且克制**：Swift + AppKit，无 Electron，无内置分析追踪，无模型对话请求。

> 独立社区项目，与 OpenAI、Anthropic、Google 无隶属关系。界面目前为中文。仅支持官方账号套餐额度，不支持第三方 API 中转余额。

## 安装

**系统要求：macOS 13 或更新版本。** DMG 内含 Intel / Apple Silicon 通用应用；对应平台的官方 CLI 需要另外安装并登录。

1. 在本仓库 **[Releases](https://github.com/bloodkilory/QuotaNest/releases/latest)** 页面下载 `QuotaNest-1.4.0-universal.dmg`。
2. 打开 DMG，将 **QuotaNest.app** 拖到 **Applications**。
3. 推出磁盘映像，从“应用程序”打开 QuotaNest。
4. 在菜单栏找到 带平台图标的百分比胶囊，完成下面的账号登录后等待刷新。
5. 需要开机自启时，点击胶囊并勾选 **登录时启动**。

**首次打开提示无法验证开发者？** 当前社区构建使用 ad-hoc 签名，尚未经过 Apple Developer ID 签名及公证。尝试打开后，在 **系统设置 → 隐私与安全性 → 仍要打开** 中单独允许此应用。无需关闭 Gatekeeper。受管理的工作电脑可能不允许此操作。

下载后可对照 Release 中的 `SHA256SUMS.txt` 检查文件完整性：

```sh
shasum -a 256 ~/Downloads/QuotaNest-1.4.0-universal.dmg
```

## 从 CodexQuota 升级

先退出旧应用，再安装并打开 QuotaNest，最后将旧的 CodexQuota.app 移到废纸篓。原有平台选择和登录自启动开关会保留；已开启的登录项将在启动新版时更新路径。为兼容旧版，内部标识 `local.codexquota` 和诊断目录 `Application Support/CodexQuota` 保持不变。

## 连接账号

| 平台 | 准备工作 | 查询方式 |
| --- | --- | --- |
| Codex | 安装 [官方 Codex CLI](https://github.com/openai/codex)，运行 `codex login` 使用套餐账号登录 | 本机 app-server 的 `account/rateLimits/read` |
| Claude Code | 安装 [官方 Claude Code](https://code.claude.com/docs/en/setup)，运行 `claude auth login` 登录订阅账号 | 读取默认订阅 OAuth 凭证，查询官方额度端点 |
| Antigravity | 安装 [官方 CLI](https://antigravity.google/docs/cli)，版本 ≥ 1.1.11，并完成其官方登录流程 | `agy -p /usage --output-format json` |

每个平台独立工作；未安装的服务会显示未连接，不影响其他平台。

**Claude 钥匙串**：后台刷新不会主动弹出授权框。需要时在 Claude 面板点击“授权 Claude 登录读取”，由 macOS 请求权限。凭证过期后，请在官方客户端重新登录。本应用不会替 Claude 刷新或改写凭证。CLI 显示已登录不一定代表存在可读取订阅额度的 OAuth 权限；API Key、代理 Token 与订阅 OAuth 不等价。

**默认探测位置**：Codex 为 `~/.local/bin/codex`、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex`；Antigravity 对应同目录的 `agy`。Claude 使用 `~/.claude/.credentials.json` 或默认钥匙串服务 `Claude Code-credentials`。目前不自动遍历多账号、自定义配置目录或其他密码库。

## 使用

![菜单栏图标和余量填充示例（放大 3 倍，示例数据）](assets/capsule-preview.png)

OpenAI 标志、Claude Code 像素机器人和 Antigravity 标志替代字母缩写；悬停可查看完整平台名称。

| 胶囊状态 | 含义 |
| --- | --- |
| 平台图标 + `82%` | 当前所选平台的剩余百分比（示例值） |
| 彩色填充 / 黑色背景 | 剩余 / 已用比例；每次查询后同步更新 |
| 灰色填充 | 刷新失败时保留上次比例，并显示 `!` |
| 绿色 / 橙色 / 红色 | 余量 ≥ 20% / 10%–20% / < 10% |
| `!` | 本次刷新失败，显示的是上次成功的数据 |
| `—` | 尚未获取到有效额度 |

点击胶囊后，可切换平台、查看分组额度、重置时间、刷新状态，或点击 **立即刷新**。时间按系统当前时区显示。应用启动、电脑唤醒时也会刷新；常规刷新间隔为 180 秒，系统调度和网络可能造成延迟。

**百分比怎么计算？** Codex 使用主额度桶中各有效窗口的最低剩余值；Claude 和 Antigravity 使用各有效额度组的最低剩余值。它表示最紧张的限制，不是所有模型额度的平均值。详情中保留独立窗口；某个模型组耗尽时，其他组仍可能可用。

## 隐私与数据

- Codex 和 Antigravity 的登录与刷新由各自官方 CLI 处理。
- Claude 凭证仅在内存中用于向 `https://api.anthropic.com/api/oauth/usage` 发起认证请求；禁用重定向，不写入本应用缓存或日志。该客户端端点可能随服务更新而变化。
- 查询不会发送模型对话、不自动购买或兑换额度。官方客户端自身的网络行为仍由其实现决定。
- 本应用没有自建服务器、分析追踪或自动更新服务。
- 本地诊断文件 `~/Library/Application Support/CodexQuota/status.json` 记录刷新时间、次数、额度及错误状态，不保存令牌或账号 ID。提交 Issue 前仍请检查并隐藏不想公开的信息。

## 常见问题

**打开后没有窗口？** 这是菜单栏应用，没有 Dock 图标。检查右上角菜单栏；菜单栏空间不足时可先关闭部分其他菜单栏项目。

**一直显示未登录或刷新失败？** 先确认对应官方 CLI 可用、订阅有效、网络正常。Claude 可重新登录并在面板中授权读取。下次刷新会重试。

**更换了应用位置？** 从新位置打开应用，再关闭并重新开启“登录时启动”，更新登录项中的路径。不要直接从 DMG 内启用自启动。

**如何卸载？** 在面板取消“登录时启动”，退出应用，再把 Applications 中的应用移到废纸篓。可按需删除 `~/Library/Application Support/CodexQuota`。源码安装脚本产生的 `~/Applications` 安装可用 `./scripts/uninstall.sh` 卸载。

## 从源码构建

需要 Xcode Command Line Tools（`xcode-select --install`），无需第三方 Swift 包。

```sh
./scripts/test.sh          # 协议、解析与子进程回归测试
./scripts/build.sh         # Intel + Apple Silicon 通用 .app
./scripts/package-dmg.sh   # dist/ 中生成 DMG 与 SHA-256
./scripts/install.sh       # 可选：安装到 ~/Applications
```

源码安装脚本首次安装默认开启登录自启；DMG 安装通过面板手动开启。已有安装保留开关状态。设置 `SIGNING_IDENTITY` 可使用本机 Developer ID 证书签名；公证需要维护者另行通过 Apple notarytool 完成。未公证构建不能宣称通过 Apple 安全审核。

```sh
/Applications/QuotaNest.app/Contents/MacOS/QuotaNest --check-all
```

Apple Silicon 产物为交叉编译版本；当前本地运行验证在 Intel Mac 上完成。macOS 13 为构建最低部署版本，尚未完成所有系统版本的实机测试。

## 参与项目

欢迎通过 Issues 报告问题或提出建议，通过 Pull Requests 改进适配器和界面。请附系统版本、应用版本、相关 CLI 版本、复现步骤以及去除隐私的错误信息；**不要提交 OAuth Token、API Key 或完整凭证文件**。

如果它帮你少切换了一次额度页面，可以给项目点一颗 Star，让更多人发现它。

[MIT License](LICENSE) · 原创应用图标由 AI 辅助生成，随项目一起提供。第三方名称及商标归各自所有者。
