# QuotaNest 1.8.0

- 新增账户 / 工具视图，只读连接 CC Switch 已有 Claude Code / Codex 服务；不提供 Key 输入、另存、创建或自动切换。
- 支持 DeepSeek 官方 API 可用余额与充值/赠送明细；同凭据共享正在执行的请求，固定金额到菜单栏时不伪造百分比。
- 胶囊与弹窗采用玻璃风格，保留 64 点占用、深浅外观与减少透明度。macOS 15 兼容外观已验证；新 SDK 构建在 macOS 26+ 使用原生弹窗玻璃 API，该分支尚未实机验收。
- 保留一分钟刷新、原有八个平台、应用更新与登录启动设置；来源变更丢弃旧结果，持续查询失败保留过期提示。
- CC Switch 自定义脚本及其他新 API 余额适配尚不支持；GLM、Kimi API、Kilo、Kiro、Grok 仍在后续设计范围。
- 国内五项仍是实验适配，尚未真实账号验证；继续仅复用官方登录，不增加 API Key 接入。

macOS 13+；Intel / Apple Silicon 通用构建。使用 ad-hoc 签名，未经过 Apple Developer ID 公证。
