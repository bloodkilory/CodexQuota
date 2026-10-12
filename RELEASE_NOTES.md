# QuotaNest 1.6.0

- 新增 Kimi Code、智谱 ZCode、MiniMax Code、Qoder、腾讯 CodeBuddy 五个实验性官方登录适配。仅完成官方源码核对及模拟数据测试，尚未真实账号验证。
- 不增加 API Key 输入或保存；过期登录由原官方客户端更新。Qoder 仅兼容已核对的全球 npm 版本；CodeBuddy 仅支持 VS Code 默认配置的国内个人账号官方扩展。
- 平台选择扩展为下拉列表；保留 64 点胶囊和各平台周期偏好，新增订阅/月度额度显示。
- 固定官方接口、拒绝重定向、限制输入响应大小，后台不弹出钥匙串授权。

macOS 13+；Intel / Apple Silicon 通用构建。使用 ad-hoc 签名，未经过 Apple Developer ID 公证。
