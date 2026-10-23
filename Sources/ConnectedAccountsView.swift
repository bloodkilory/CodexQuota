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
    var source: DisplaySource
    var currency: String?
    var sourceError: String?
}

struct ConnectedAccountsActions {
    let select: (DisplaySource) -> Void
    let refresh: (String) -> Void
    let settings: () -> Void
}

final class DisplaySourcePicker: NSPopUpButton {
    private let sources: [DisplaySource]
    private let changed: (DisplaySource) -> Void
    init(sources: [DisplaySource], titles: [String], selected: DisplaySource, changed: @escaping (DisplaySource) -> Void) {
        self.sources = sources; self.changed = changed
        super.init(frame:.zero,pullsDown:false)
        menu = NSMenu()
        for title in titles { menu?.addItem(NSMenuItem(title:title,action:nil,keyEquivalent:"")) }
        selectItem(at:sources.firstIndex(of:selected) ?? 0)
        target = self; action = #selector(selectedSource)
        identifier = NSUserInterfaceItemIdentifier("display-source")
        widthAnchor.constraint(equalToConstant:344).isActive = true
        setAccessibilityLabel(L("菜单栏显示")); toolTip = titleOfSelectedItem
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func selectedSource() { changed(sources[indexOfSelectedItem]) }
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
    static func build(_ model: ConnectedAccountsPresentation, officialDetails: NSView? = nil, actions: ConnectedAccountsActions) -> NSStackView {
        let root = stack(width:width,spacing:12)
        root.edgeInsets = NSEdgeInsets(top:18,left:18,bottom:16,right:18)
        root.addArrangedSubview(text(L("余度 QuotaNest"),size:18,bold:true))
        root.addArrangedSubview(text(L("菜单栏显示"),size:11,secondary:true))
        let accounts = model.connections.filter { model.enabled.contains($0.id) && $0.supportsBalance }
        var sources = QuotaProviderID.allCases.map { DisplaySource.official($0) } + accounts.map { .api($0.id) }
        var titles = QuotaProviderID.allCases.map { $0.title + " · " + L("套餐余量") + ($0.experimental ? L(" · 实验") : "") }
        titles += accounts.map { "DeepSeek · " + L("API 余额") + " · " + ($0.harness == "claude" ? "Claude Code" : "Codex") + " · " + $0.displayName }
        if !sources.contains(model.source) { sources.append(model.source); titles.append(L("API 余额 · 来源不可用")) }
        root.addArrangedSubview(DisplaySourcePicker(sources:sources,titles:titles,selected:model.source,changed:actions.select))
        switch model.source {
        case .official:
            if let officialDetails { root.addArrangedSubview(officialDetails) }
        case .api(let id):
            let connection = accounts.first { $0.id == id }
            let reading = connection == nil ? ConnectedAccountReading() : model.readings[id] ?? ConnectedAccountReading()
            let card = stack(width:316,spacing:9)
            card.addArrangedSubview(text("DeepSeek · " + L("API 余额"),size:14,bold:true,width:316))
            if let connection {
                card.addArrangedSubview(text(connection.displayName,size:12,bold:true,width:316))
                card.addArrangedSubview(text(L("来自 CC Switch · ") + (connection.harness == "claude" ? "Claude Code" : "Codex"),size:11,secondary:true,width:316))
            } else { card.addArrangedSubview(text(L("来源已移除或不再支持，请选择其他显示来源"),size:11,secondary:true,width:316)) }
            let wallets = reading.balance?.wallets ?? []
            let wallet = wallets.first { $0.currency == model.currency } ?? wallets.first
            if let wallet {
                card.addArrangedSubview(text(wallet.displayAmount,size:28,bold:true,width:316))
                card.addArrangedSubview(text(L(reading.error == nil ? "可用余额" : "上次成功余额 · 当前数据已过期"),size:11,secondary:true,width:316))
                card.addArrangedSubview(text(L("充值余额    ") + wallet.currency + " " + DeepSeekWallet.amount(wallet.toppedUp),width:316))
                card.addArrangedSubview(text(L("赠送余额    ") + wallet.currency + " " + DeepSeekWallet.amount(wallet.granted),width:316))
                for other in wallets where other.currency != wallet.currency { card.addArrangedSubview(text(L("另一币种    ") + other.displayAmount,size:11,secondary:true,width:316)) }
                if reading.balance?.isAvailable == false { card.addArrangedSubview(text(L("官方接口标记当前余额不足以调用 API"),size:11,secondary:true,width:316)) }
            } else { card.addArrangedSubview(text(reading.refreshing ? L("正在查询…") : "—",size:28,bold:true,width:316)) }
            if let error = reading.error ?? model.sourceError { card.addArrangedSubview(text(error,size:11,secondary:true,width:316)) }
            let formatter = DateFormatter(); formatter.locale = Localization.shared.locale; formatter.timeStyle = .medium
            let time = reading.lastSuccess.map { formatter.string(from:$0) } ?? L("尚未成功")
            card.addArrangedSubview(text(L("更新：") + time + L(" · 每 1 分钟检查"),size:11,secondary:true,width:316))
            let refresh = AccountActionButton(L(reading.refreshing ? "正在刷新…" : "立即刷新"),id:"refresh-account") { actions.refresh(id) }
            refresh.isEnabled = connection != nil && !reading.refreshing
            card.addArrangedSubview(refresh)
            card.layoutSubtreeIfNeeded()
            root.addArrangedSubview(GlassAppearance.card(card,width:344,height:card.fittingSize.height))
        }
        root.addArrangedSubview(AccountActionButton(L("设置"),id:"settings",handler:actions.settings))
        return root
    }
}
