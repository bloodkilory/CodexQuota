import AppKit

struct SettingsPresentation {
    var connections: [CCSwitchConnection]
    var enabled: Set<String>
    var sourceError: String?
    var discovering: Bool
    var language: InterfaceLanguage
    var version: String?
    var updateState: UpdateMenuState
    var previousStatus: UpdateInstallStatus?
    var availableVersion: String?
    var canInstall: Bool
    var loginEnabled: Bool
}
struct SettingsActions {
    let back: () -> Void
    let language: (InterfaceLanguage) -> Void
    let connect: () -> Void
    let checkUpdate: () -> Void
    let installUpdate: () -> Void
    let login: (Bool) -> Void
    let quit: () -> Void
}
final class LanguagePicker: NSPopUpButton {
    private let changed: (InterfaceLanguage) -> Void
    init(selected: InterfaceLanguage, changed: @escaping (InterfaceLanguage) -> Void) {
        self.changed = changed
        super.init(frame:.zero,pullsDown:false)
        addItems(withTitles:[L("跟随系统"),"中文","English"])
        selectItem(at:InterfaceLanguage.allCases.firstIndex(of:selected)!)
        identifier = NSUserInterfaceItemIdentifier("interface-language")
        setAccessibilityLabel(L("语言")); target = self; action = #selector(selectedLanguage)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func selectedLanguage() { changed(InterfaceLanguage.allCases[indexOfSelectedItem]) }
}
enum SettingsView {
    static func build(_ model: SettingsPresentation, actions: SettingsActions) -> NSStackView {
        let stack = ConnectedAccountsView.stack(width:380)
        stack.edgeInsets = NSEdgeInsets(top:18,left:18,bottom:18,right:18)
        stack.addArrangedSubview(AccountActionButton(L("返回详情"),id:"back-details") { actions.back() })
        stack.addArrangedSubview(label(L("设置"),size:18,bold:true))
        stack.addArrangedSubview(label(L("语言"),bold:true))
        let language = LanguagePicker(selected:model.language,changed:actions.language)
        stack.addArrangedSubview(language)
        stack.addArrangedSubview(label(L("CC Switch 连接"),bold:true))
        if let sourceError = model.sourceError { stack.addArrangedSubview(label(sourceError,color:.systemOrange)) }
        let linked = model.connections.filter { model.enabled.contains($0.id) }
        if linked.isEmpty { stack.addArrangedSubview(label(L("连接 CC Switch 已有服务，无需重新填写 Key。"),color:.secondaryLabelColor)) }
        for entry in linked {
            stack.addArrangedSubview(label(entry.displayName + " · " + (entry.harness == "claude" ? "Claude Code" : "Codex"),bold:true))
            stack.addArrangedSubview(label(L(entry.configurationRole) + " · " + entry.origin,size:11,color:.secondaryLabelColor))
            stack.addArrangedSubview(label(L(entry.supportsBalance ? "DeepSeek 官方账户余额 · 来自 CC Switch" : "已识别配置 · 暂不支持查询此服务余额"),size:11,color:.secondaryLabelColor))
        }
        stack.addArrangedSubview(label(L("这里显示保存/路由配置；会话环境覆盖和故障切换未被观测时，不代表所有运行中会话的实际服务。"),size:11,color:.secondaryLabelColor))
        stack.addArrangedSubview(AccountActionButton(L(model.discovering ? "正在读取来源…" : "连接已有工具…"),id:"connect-source") { actions.connect() })
        stack.addArrangedSubview(label(L("应用更新"), bold:true))
        stack.addArrangedSubview(label(L("当前版本 v") + (model.version ?? L("未知")),size:11,color:.secondaryLabelColor))
        stack.addArrangedSubview(label(model.updateState.title,size:11,color:.secondaryLabelColor))
        if let previousUpdateMessage = model.previousStatus { stack.addArrangedSubview(label(previousUpdateMessage.localizedMessage,size:11,color:.systemOrange)) }
        let checkButton = AccountActionButton(L("检查更新"),id:"check-updates",handler:actions.checkUpdate); checkButton.isEnabled = model.updateState.isActionEnabled
        stack.addArrangedSubview(checkButton)
        if let release = model.availableVersion {
            if model.canInstall {
                let updateButton = AccountActionButton(L("更新到 v") + release,id:"install-update",handler:actions.installUpdate); updateButton.isEnabled = model.updateState.isActionEnabled
                stack.addArrangedSubview(updateButton)
            } else { stack.addArrangedSubview(label(L("请安装至 ~/Applications 或 /Applications 后更新"),size:11,color:.secondaryLabelColor)) }
        }
        let login = AccountActionButton(L("登录时启动"),id:"launch-at-login") { actions.login(!model.loginEnabled) }
        login.setButtonType(.switch); login.state = model.loginEnabled ? .on : .off
        stack.addArrangedSubview(login)
        stack.addArrangedSubview(AccountActionButton(L("退出余度 QuotaNest"),id:"quit",handler:actions.quit))
        return stack
    }
    private static func label(_ value: String, size: CGFloat = 12, color: NSColor = .labelColor, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.widthAnchor.constraint(equalToConstant: 322).isActive = true
        return field
    }
}
