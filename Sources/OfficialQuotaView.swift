import AppKit

enum OfficialQuotaView {
    static func build(provider: QuotaProviderID, reading: ProviderReading, displayedPeriod: QuotaPeriod?, refresh: @escaping () -> Void, authorize: @escaping () -> Void) -> NSStackView {
        let selectedProvider = provider
        let snapshot = reading.snapshot, errorMessage = reading.error, refreshing = reading.refreshing
        let lastSuccess = reading.lastSuccess
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 11, bottom: 6, right: 11)
        stack.addArrangedSubview(label(selectedProvider.title, size: 16, bold: true))
        if selectedProvider.experimental {
            stack.addArrangedSubview(label(L("实验性接入 · 尚未用真实账号验证"), size: 11, color: .systemOrange))
        }
        stack.addArrangedSubview(label(selectedProvider.loginHelp, size: 11, color: .secondaryLabelColor))
        if let selected = snapshot?.selected {
            let source = selectedProvider == .codex ? (selected.1.planType ?? L("Codex 登录账号")) : L("本机 ") + selectedProvider.title + L(" 官方登录")
            stack.addArrangedSubview(label(source + L(" · 胶囊：") + (selectedProvider == .antigravity ? "Gemini " : "") + reading.periodLabel(for: selectedProvider, period: displayedPeriod), color: .secondaryLabelColor))
        }
        if let errorMessage { stack.addArrangedSubview(label("⚠ \(errorMessage)" + (snapshot == nil ? "" : L("\n当前百分比为上次成功查询结果。")), color: .systemOrange)) }
        if let snapshot {
            for (key, bucket) in snapshot.namedBuckets {
                let heading = bucket.nameKey == nil && bucket.limitName == nil && bucket.limitId == nil ? key : bucket.displayName
                stack.addArrangedSubview(label(heading, bold: true))
                if bucket.windows.isEmpty { stack.addArrangedSubview(label(L("暂无可用额度窗口"), color: .secondaryLabelColor)) }
                for window in bucket.windows {
                    let value = window.remaining.map { String(format: "%.1f%%", $0) } ?? L("未知")
                    stack.addArrangedSubview(label(L("%@    剩余 %@",window.title,value), size: 14, bold: true))
                    stack.addArrangedSubview(label(resetText(window.resetsAt), color: .secondaryLabelColor))
                    let bar = NSProgressIndicator(); bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = window.remaining ?? 0
                    bar.widthAnchor.constraint(equalToConstant: 322).isActive = true
                    if window.remaining != nil { stack.addArrangedSubview(bar) }
                }
                if let credits = bucket.credits {
                    stack.addArrangedSubview(label(L("Credits 余额：%@",credits.unlimited == true ? L("无限") : credits.balance ?? L("未提供")), color: .secondaryLabelColor))
                }
            }
        } else { stack.addArrangedSubview(label(refreshing ? L("正在读取官方套餐…") : L("尚未取得额度"), color: .secondaryLabelColor)) }
        let time = lastSuccess.map { dateString($0) } ?? L("尚未成功")
        stack.addArrangedSubview(label(L("更新：%@\n每 1 分钟刷新 · %@",time,TimeZone.current.identifier), size: 11, color: .secondaryLabelColor))
        let refreshButton = AccountActionButton(L(refreshing ? "正在刷新…" : "立即刷新"),id:"refresh-official",handler:refresh); refreshButton.isEnabled = !refreshing
        stack.addArrangedSubview(refreshButton)
        if selectedProvider == .claude && errorMessage != nil {
            let authorize = AccountActionButton(L("授权 Claude 登录读取"),handler:authorize)
            authorize.isEnabled = !refreshing; stack.addArrangedSubview(authorize)
        }
        if selectedProvider == .codebuddy && errorMessage != nil {
            let authorize = AccountActionButton(L("授权 CodeBuddy 登录读取"),handler:authorize)
            authorize.isEnabled = !refreshing; stack.addArrangedSubview(authorize)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant:344).isActive = true
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
    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Localization.shared.locale; formatter.dateFormat = "MM-dd HH:mm:ss"; return formatter.string(from: date)
    }
    private static func resetText(_ timestamp: Double?) -> String {
        guard let timestamp, timestamp.isFinite, timestamp > 0, timestamp <= 253402300799 else { return L("重置时间：未提供") }
        let date = Date(timeIntervalSince1970: timestamp), seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return L("重置：%@ · 等待服务更新",dateString(date)) }
        let hours = Int(seconds / 3600), minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return L("重置：%@\n还有 %@ 天 %@ 小时 %@ 分钟",dateString(date),String(hours / 24),String(hours % 24),String(minutes))
    }
}
