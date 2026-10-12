import AppKit

final class CapsuleView: NSView {
    var provider: QuotaProviderID = .codex { didSet { needsDisplay = true } }
    var text = "—" { didSet { needsDisplay = true } }
    var remaining: Double? { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
    var periodText = "1w" { didSet { needsDisplay = true } }
    var canSwitchPeriod = false { didSet { periodButton.isEnabled = canSwitchPeriod; needsDisplay = true } }
    var periodAction: (() -> Void)?
    let detailButton = NSButton()
    let periodButton = NSButton()
    var dividerX: CGFloat { bounds.width - 16 }
    var action: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        for button in [detailButton, periodButton] {
            button.title = ""; button.isBordered = false; button.isTransparent = true
            button.target = self; addSubview(button)
        }
        detailButton.action = #selector(openDetails)
        periodButton.action = #selector(switchPeriod)
        periodButton.setAccessibilityLabel("切换额度周期")
        periodButton.isEnabled = false
        layoutButtons()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openDetails() { action?() }
    @objc private func switchPeriod() { if canSwitchPeriod { periodAction?() } }
    private func layoutButtons() {
        detailButton.frame = CGRect(x: 0, y: 0, width: dividerX, height: bounds.height)
        periodButton.frame = CGRect(x: dividerX, y: 0, width: 16, height: bounds.height)
    }
    override func layout() { super.layout(); layoutButtons() }
    var accentColor: NSColor {
        switch provider {
        case .codex: return NSColor(srgbRed: 0.20, green: 0.44, blue: 0.39, alpha: 1)
        case .claude: return NSColor(srgbRed: 0.63, green: 0.34, blue: 0.24, alpha: 1)
        case .kimi: return NSColor(srgbRed: 0.26, green: 0.36, blue: 0.69, alpha: 1)
        case .zcode: return NSColor(srgbRed: 0.27, green: 0.39, blue: 0.61, alpha: 1)
        case .minimax: return NSColor(srgbRed: 0.65, green: 0.31, blue: 0.39, alpha: 1)
        case .qoder: return NSColor(srgbRed: 0.38, green: 0.31, blue: 0.63, alpha: 1)
        case .codebuddy: return NSColor(srgbRed: 0.25, green: 0.43, blue: 0.63, alpha: 1)
        case .antigravity: return NSColor(srgbRed: 0.23, green: 0.39, blue: 0.65, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = CGRect(x: 1, y: (bounds.height - 18) / 2, width: bounds.width - 2, height: 18)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor.black.setFill()
        shape.fill()

        if let remaining, remaining.isFinite {
            let fraction = min(100, max(0, remaining)) / 100
            let color: NSColor
            if stale { color = NSColor(srgbRed: 0.30, green: 0.32, blue: 0.35, alpha: 1) }
            else { color = accentColor }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            color.setFill()
            CGRect(x: rect.minX, y: rect.minY, width: (dividerX - rect.minX) * fraction, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // A subtle edge keeps the black, depleted section visible on dark menu bars.
        NSColor.white.withAlphaComponent(0.20).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 8.75, yRadius: 8.75)
        outline.lineWidth = 0.5
        outline.stroke()
        ProviderMark.draw(provider, in: CGRect(x: rect.minX + 3, y: rect.midY - 5, width: 10, height: 10))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let label = text as NSString
        let size = label.size(withAttributes: attrs)
        let textRect = CGRect(x: rect.minX + 15, y: rect.minY, width: dividerX - rect.minX - 16, height: rect.height)
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: dividerX, y: rect.minY + 3))
        separator.line(to: CGPoint(x: dividerX, y: rect.maxY - 3))
        NSColor.white.withAlphaComponent(0.35).setStroke()
        separator.lineWidth = 0.5; separator.stroke()
        let periodAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: periodText.count > 3 ? 6 : 7.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(canSwitchPeriod ? 1 : 0.55)
        ]
        let periodSize = (periodText as NSString).size(withAttributes: periodAttrs)
        (periodText as NSString).draw(at: CGPoint(x: (dividerX + rect.maxX) / 2 - periodSize.width / 2, y: rect.midY - periodSize.height / 2), withAttributes: periodAttrs)
        label.draw(at: CGPoint(x: textRect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}
