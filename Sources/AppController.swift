import AppKit
final class AppController: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let capsule = CapsuleView(frame: NSRect(x: 0, y: 0, width: 68, height: 24))
    private let popover = NSPopover()
    private let client = CodexClient()
    private var timer: Timer?
    private let claudeClient = ClaudeQuotaClient()
    private let antigravityClient = AntigravityQuotaClient()
    private var readings = Dictionary(uniqueKeysWithValues: QuotaProviderID.allCases.map { ($0, ProviderReading()) })
    private var selectedProvider = QuotaProviderID(rawValue: UserDefaults.standard.string(forKey: "selectedProvider") ?? "") ?? .codex
    private var reading: ProviderReading { readings[selectedProvider]! }
    private var snapshot: QuotaSnapshot? { reading.snapshot }
    private var lastSuccess: Date? { reading.lastSuccess }
    private var errorMessage: String? { reading.error }
    private var refreshing: Bool { reading.refreshing }
    private var lockHandle: FileHandle?
    private let interval: TimeInterval = 180
    private var stateDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexQuota") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // flock survives PID reuse and releases automatically on exit.
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let lockURL = stateDirectory.appendingPathComponent("instance.lock")
        if !FileManager.default.fileExists(atPath: lockURL.path) { FileManager.default.createFile(atPath: lockURL.path, contents: nil) }
        lockHandle = try? FileHandle(forWritingTo: lockURL)
        if !CommandLine.arguments.contains("--preview") {
            guard let lockHandle, flock(lockHandle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        }
        // Keep the existing login preference while updating its executable path after a rename/move.
        if !CommandLine.arguments.contains("--preview"), LoginItemManager.enabled,
           !Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            try? LoginItemManager.setEnabled(true)
        }
        status = NSStatusBar.system.statusItem(withLength: 68)
        if let button = status.button {
            capsule.frame = button.bounds; capsule.autoresizingMask = [.width, .height]
            button.addSubview(capsule)
        }
        capsule.action = { [weak self] in self?.togglePopover() }
        popover.behavior = .transient
        popover.animates = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer; timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); client.shutdown(); claudeClient.shutdown(); antigravityClient.shutdown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    @objc private func woke() { refresh() }
    @objc private func refresh() {
        for provider in QuotaProviderID.allCases { refresh(provider) }
    }
    @objc private func manualRefresh() { refresh(selectedProvider) }
    @objc private func authorizeClaude() { refresh(.claude, allowPrompt: true) }
    private func refresh(_ provider: QuotaProviderID, allowPrompt: Bool = false) {
        guard readings[provider]?.refreshing != true else { return }
        readings[provider]?.refreshing = true
        render()
        let completion: (Result<QuotaSnapshot, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.readings[provider]?.refreshing = false
                switch result {
                case .success(let value):
                    self.readings[provider]?.snapshot = value
                    self.readings[provider]?.lastSuccess = Date()
                    self.readings[provider]?.successes += 1
                    self.readings[provider]?.error = nil
                case .failure(let error): self.readings[provider]?.error = error.localizedDescription
                }
                self.render(); self.writeDiagnostics()
                if CommandLine.arguments.contains("--preview") && !self.readings.values.contains(where: { $0.refreshing }) { self.exportPreview() }
            }
        }
        switch provider {
        case .codex: client.fetch(completion)
        case .claude: claudeClient.fetch(allowPrompt: allowPrompt, completion: completion)
        case .antigravity: antigravityClient.fetch(completion)
        }
    }
    @objc private func selectProvider(_ sender: NSSegmentedControl) {
        selectedProvider = QuotaProviderID.allCases[sender.selectedSegment]
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider")
        render(); writeDiagnostics()
    }
    private func exportPreview() {
        NSApp.appearance = NSAppearance(named: .aqua)
        for provider in QuotaProviderID.allCases {
            selectedProvider = provider
            buildPopover()
            guard let view = popover.contentViewController?.view else { continue }
            view.appearance = NSAppearance(named: .aqua)
            if let scroll = view as? NSScrollView { scroll.drawsBackground = true; scroll.backgroundColor = .white }
            let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua); window.contentView = view
            window.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: stateDirectory.appendingPathComponent("preview-" + provider.rawValue + ".png")) }
                }
            }
            popover.contentViewController = nil
        }
        NSApp.terminate(nil)
    }
    private func writeDiagnostics() {
        guard !CommandLine.arguments.contains("--preview") else { return }
        // Only non-identifying operational state, no account ID or authentication data.
        var providers: [String: Any] = [:]
        for provider in QuotaProviderID.allCases {
            let entry = readings[provider]!
            var value: [String: Any] = ["successfulRefreshes": entry.successes, "refreshing": entry.refreshing]
            if let remaining = entry.remaining(for: provider) { value["remaining"] = remaining }
            if let date = entry.lastSuccess { value["lastSuccess"] = ISO8601DateFormatter().string(from: date) }
            if let error = entry.error { value["error"] = error }
            providers[provider.rawValue] = value
        }
        let value: [String: Any] = ["providers": providers, "selectedProvider": selectedProvider.rawValue, "refreshIntervalSeconds": interval, "loginEnabled": LoginItemManager.enabled, "display": capsule.text, "pid": ProcessInfo.processInfo.processIdentifier]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: stateDirectory.appendingPathComponent("status.json"), options: .atomic) }
    }
    private func render() {
        let remaining = reading.remaining(for: selectedProvider)
        capsule.remaining = remaining; capsule.stale = errorMessage != nil
        let value = remaining.map { String(format: "%.0f%%", floor($0)) + (errorMessage == nil ? "" : "!") } ?? (refreshing ? "···" : "—")
        capsule.provider = selectedProvider
        capsule.text = value
        let title = "\(selectedProvider.title) 剩余额度 \(value)" + (errorMessage == nil ? "" : "，查询失败或数据过期")
        capsule.setAccessibilityLabel(title); capsule.toolTip = title
        if popover.isShown { buildPopover() }
    }
    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        buildPopover()
        if let button = status.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    private func label(_ value: String, size: CGFloat = 12, color: NSColor = .labelColor, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.widthAnchor.constraint(equalToConstant: 322).isActive = true
        return field
    }
    private func buildPopover() {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.addArrangedSubview(label("余度 QuotaNest", size: 18, bold: true))
        let picker = NSSegmentedControl(labels: ["Codex", "Claude", "Antigravity"], trackingMode: .selectOne, target: self, action: #selector(selectProvider(_:)))
        picker.selectedSegment = QuotaProviderID.allCases.firstIndex(of: selectedProvider)!
        picker.widthAnchor.constraint(equalToConstant: 322).isActive = true
        stack.addArrangedSubview(picker)
        stack.addArrangedSubview(label(selectedProvider.title, size: 16, bold: true))
        if let selected = snapshot?.selected {
            let source = selectedProvider == .codex ? (selected.1.planType ?? "Codex 登录账号") : selectedProvider == .claude ? "本机 Claude 官方登录" : "本机 Antigravity CLI 登录"
            stack.addArrangedSubview(label(source + " · 显示最低余量", color: .secondaryLabelColor))
        }
        if let errorMessage { stack.addArrangedSubview(label("⚠ \(errorMessage)" + (snapshot == nil ? "" : "\n当前百分比为上次成功查询结果。"), color: .systemOrange)) }
        if let snapshot {
            for (key, bucket) in snapshot.namedBuckets {
                stack.addArrangedSubview(label(bucket.limitName ?? key, bold: true))
                if bucket.windows.isEmpty { stack.addArrangedSubview(label("暂无可用额度窗口", color: .secondaryLabelColor)) }
                for window in bucket.windows {
                    let value = window.remaining.map { String(format: "%.1f%%", $0) } ?? "未知"
                    stack.addArrangedSubview(label("\(window.title)    剩余 \(value)", size: 14, bold: true))
                    stack.addArrangedSubview(label(resetText(window.resetsAt), color: .secondaryLabelColor))
                    let bar = NSProgressIndicator(); bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = window.remaining ?? 0
                    bar.widthAnchor.constraint(equalToConstant: 322).isActive = true
                    if window.remaining != nil { stack.addArrangedSubview(bar) }
                }
                if let credits = bucket.credits {
                    stack.addArrangedSubview(label("额外 Credits：\(credits.unlimited == true ? "无限" : credits.balance ?? "未提供")", color: .secondaryLabelColor))
                }
            }
        } else { stack.addArrangedSubview(label(refreshing ? "正在读取官方套餐…" : "尚未取得额度", color: .secondaryLabelColor)) }
        let time = lastSuccess.map { dateString($0) } ?? "尚未成功"
        stack.addArrangedSubview(label("更新：\(time)\n每 3 分钟刷新 · \(TimeZone.current.identifier)", size: 11, color: .secondaryLabelColor))
        let refreshButton = NSButton(title: refreshing ? "正在刷新…" : "立即刷新", target: self, action: #selector(manualRefresh)); refreshButton.isEnabled = !refreshing
        stack.addArrangedSubview(refreshButton)
        if selectedProvider == .claude && errorMessage != nil {
            let authorize = NSButton(title: "授权 Claude 登录读取", target: self, action: #selector(authorizeClaude))
            authorize.isEnabled = !refreshing; stack.addArrangedSubview(authorize)
            stack.addArrangedSubview(label("使用 Claude Code 官方订阅登录；若未登录，请在终端运行 claude auth login。", size: 11, color: .secondaryLabelColor))
        }
        let login = NSButton(checkboxWithTitle: "登录时启动", target: self, action: #selector(toggleLogin(_:))); login.state = LoginItemManager.enabled ? .on : .off
        stack.addArrangedSubview(login)
        stack.addArrangedSubview(NSButton(title: "退出余度 QuotaNest", target: self, action: #selector(quit)))
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 358).isActive = true
        stack.layoutSubtreeIfNeeded()
        let height = max(240, stack.fittingSize.height)
        stack.frame = NSRect(x: 0, y: 0, width: 358, height: height)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 358, height: min(height, 650)))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = height > 650; scroll.documentView = stack
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, height - scroll.frame.height)))
        let controller = NSViewController(); controller.view = scroll
        popover.contentViewController = controller; popover.contentSize = scroll.frame.size
    }
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "MM-dd HH:mm:ss"; return formatter.string(from: date)
    }
    private func resetText(_ timestamp: Double?) -> String {
        guard let timestamp, timestamp.isFinite, timestamp > 0 else { return "重置时间：未提供" }
        let date = Date(timeIntervalSince1970: timestamp), seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "重置：\(dateString(date)) · 等待服务更新" }
        let hours = Int(seconds / 3600), minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return "重置：\(dateString(date))\n还有 \(hours / 24) 天 \(hours % 24) 小时 \(minutes) 分钟"
    }
    @objc private func toggleLogin(_ sender: NSButton) {
        do { try LoginItemManager.setEnabled(sender.state == .on); writeDiagnostics() }
        catch { let alert = NSAlert(); alert.messageText = "无法更新登录项"; alert.informativeText = error.localizedDescription; alert.runModal() }
        sender.state = LoginItemManager.enabled ? .on : .off
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
