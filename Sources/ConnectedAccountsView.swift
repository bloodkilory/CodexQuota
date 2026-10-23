import AppKit

final class AccountActionButton: NSButton {
    private let handler: () -> Void
    init(_ title: String, id: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame:.zero)
        self.title = title; bezelStyle = .rounded; target = self; action = #selector(invoke)
        if let id { identifier = NSUserInterfaceItemIdentifier(id) }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler() }
}

struct ConnectedAccountsPresentation {
    var connections: [CCSwitchConnection]
    var enabled: Set<String>
    var readings: [String:ConnectedAccountReading]
    var selectedID: String?
    var pinnedID: String?
    var currency: String?
    var sourceError: String?
    var discovering: Bool
    var tools: Bool
}

struct ConnectedAccountsActions {
    let changeTab: (Bool) -> Void
    let select: (String) -> Void
    let pin: (String) -> Void
    let refresh: (String) -> Void
    let connect: () -> Void
    let legacy: () -> Void
}

enum ConnectedAccountsView {
    static let width: CGFloat = 380
    static func text(_ value: String, size: CGFloat = 12, secondary: Bool = false, bold: Bool = false, width: CGFloat = 344) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:value)
        field.font = .systemFont(ofSize:size,weight:bold ? .semibold : .regular)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.widthAnchor.constraint(equalToConstant:width).isActive = true
        field.setContentCompressionResistancePriority(.required,for:.vertical)
        return field
    }
    static func stack(width: CGFloat = 344, spacing: CGFloat = 9) -> NSStackView {
        let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = spacing
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant:width).isActive = true
        return view
    }
    static func build(_ model: ConnectedAccountsPresentation, actions: ConnectedAccountsActions) -> NSStackView {
        let root = stack(width:width,spacing:13)
        root.edgeInsets = NSEdgeInsets(top:20,left:18,bottom:16,right:18)
        root.addArrangedSubview(text("余度 QuotaNest",size:18,bold:true))
        let tabs = NSSegmentedControl(labels:["账户","工具"],trackingMode:.selectOne,target:nil,action:nil)
        tabs.selectedSegment = model.tools ? 1 : 0
        tabs.widthAnchor.constraint(equalToConstant:344).isActive = true
        // The target owns its closure; NSSegmentedControl's target is weak.
        let tabView = AccountTabs(control:tabs,change:actions.changeTab)
        root.addArrangedSubview(tabView)
        if let error = model.sourceError { root.addArrangedSubview(text(error,size:11,secondary:true)) }
        let selected = model.connections.filter { model.enabled.contains($0.id) }
        if selected.isEmpty {
            root.addArrangedSubview(text(model.discovering ? "正在读取 CC Switch 连接…" : "连接 CC Switch 已有服务，无需重新填写 Key。",size:13))
            root.addArrangedSubview(text("本版可查询 DeepSeek 官方 API 余额。其他服务仅识别配置；原有八个平台仍在官方套餐入口。",size:11,secondary:true))
        } else if model.tools {
            for connection in selected {
                root.addArrangedSubview(text((connection.harness == "claude" ? "Claude Code" : "Codex") + " → " + connection.name,size:13,bold:true))
                root.addArrangedSubview(text(connection.configurationRole + " · " + connection.origin,size:11,secondary:true))
                root.addArrangedSubview(text(connection.supportsBalance ? "DeepSeek 官方账户余额 · 来自 CC Switch" : "已识别配置 · 暂不支持查询此服务余额",size:11,secondary:true))
            }
            root.addArrangedSubview(text("这里显示保存/路由配置；会话环境覆盖和故障切换未被观测时，不代表所有运行中会话的实际服务。",size:11,secondary:true))
        } else {
            let connection = selected.first { $0.id == model.selectedID } ?? selected.first!
            let reading = model.readings[connection.id] ?? ConnectedAccountReading()
            let card = stack(width:316,spacing:9)
            card.addArrangedSubview(text(connection.supportsBalance ? "DeepSeek · API 钱包" : connection.name,size:14,bold:true,width:316))
            card.addArrangedSubview(text("来自 CC Switch · " + (connection.harness == "claude" ? "Claude Code" : "Codex"),size:11,secondary:true,width:316))
            let wallets = reading.balance?.wallets ?? []
            let wallet = wallets.first { $0.currency == model.currency } ?? wallets.first
            if let wallet {
                card.addArrangedSubview(text(wallet.displayAmount,size:28,bold:true,width:316))
                card.addArrangedSubview(text(reading.error == nil ? "可用余额" : "上次成功余额 · 当前数据已过期",size:11,secondary:true,width:316))
                card.addArrangedSubview(text("充值余额    " + wallet.currency + " " + DeepSeekWallet.amount(wallet.toppedUp),width:316))
                card.addArrangedSubview(text("赠送余额    " + wallet.currency + " " + DeepSeekWallet.amount(wallet.granted),width:316))
                for other in wallets where other.currency != wallet.currency { card.addArrangedSubview(text("另一币种    " + other.displayAmount,size:11,secondary:true,width:316)) }
                if reading.balance?.isAvailable == false { card.addArrangedSubview(text("官方接口标记当前余额不足以调用 API",size:11,secondary:true,width:316)) }
            } else {
                card.addArrangedSubview(text(connection.supportsBalance ? (reading.refreshing ? "正在查询…" : "—") : "暂不支持查余额",size:24,bold:true,width:316))
            }
            if let error = reading.error { card.addArrangedSubview(text(error,size:11,secondary:true,width:316)) }
            let time = reading.lastSuccess.map { DateFormatter.localizedString(from:$0,dateStyle:.none,timeStyle:.medium) } ?? "尚未成功"
            card.addArrangedSubview(text("更新：" + time + " · 每 1 分钟检查",size:11,secondary:true,width:316))
            if connection.supportsBalance {
                let pin = AccountActionButton(model.pinnedID == connection.id ? "已固定 · 点击恢复官方套餐" : "固定到菜单栏",id:"pin-account") { actions.pin(connection.id) }
                card.addArrangedSubview(pin)
                let refresh = AccountActionButton(reading.refreshing ? "正在刷新…" : "立即刷新",id:"refresh-account") { actions.refresh(connection.id) }
                refresh.isEnabled = !reading.refreshing; card.addArrangedSubview(refresh)
            }
            card.layoutSubtreeIfNeeded()
            root.addArrangedSubview(GlassAppearance.card(card,width:344,height:card.fittingSize.height))
            if selected.count > 1 {
                root.addArrangedSubview(text("已连接的服务",size:11,secondary:true))
                for entry in selected {
                    let item = AccountActionButton(entry.name + " · " + (entry.harness == "claude" ? "Claude Code" : "Codex"),id:"account-" + entry.id) { actions.select(entry.id) }
                    item.bezelStyle = .inline; item.alignment = .left
                    item.lineBreakMode = .byTruncatingTail; item.toolTip = item.title
                    item.widthAnchor.constraint(lessThanOrEqualToConstant:344).isActive = true
                    root.addArrangedSubview(item)
                }
            }
        }
        root.addArrangedSubview(AccountActionButton(model.discovering ? "正在读取来源…" : "连接已有工具…",id:"connect-source",handler:actions.connect))
        root.addArrangedSubview(AccountActionButton("官方套餐与应用设置",id:"legacy-settings",handler:actions.legacy))
        return root
    }
}

private final class AccountTabs: NSView {
    private let control: NSSegmentedControl
    private let change: (Bool) -> Void
    init(control: NSSegmentedControl, change: @escaping (Bool) -> Void) {
        self.control = control; self.change = change
        super.init(frame:NSRect(x:0,y:0,width:344,height:28))
        addSubview(control); control.frame = bounds; control.autoresizingMask = [.width,.height]
        control.target = self; control.action = #selector(selected)
        control.identifier = NSUserInterfaceItemIdentifier("account-tabs")
        widthAnchor.constraint(equalToConstant:344).isActive = true
        heightAnchor.constraint(equalToConstant:28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func selected() { change(control.selectedSegment == 1) }
}
