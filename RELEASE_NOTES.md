# QuotaNest 1.7.0

- 新增菜单应用更新：启动时静默检查、点击“检查更新”手动重查，仅使用本仓库 GitHub 正式 Release。
- 用户点击更新后下载通用 DMG 和 SHA-256 清单；校验安装包、应用身份、版本、资源、架构及签名完整性，再确认安装并重启。
- 支持 ~/Applications 和 /Applications；系统目录通过 macOS 请求管理员授权。保留登录启动选择和平台设置；保留旧版本备份，替换失败尝试恢复。
- 国内五项仍是实验适配，尚未真实账号验证；继续仅复用官方登录，不增加 API Key 接入。

macOS 13+；Intel / Apple Silicon 通用构建。使用 ad-hoc 签名，未经过 Apple Developer ID 公证。
