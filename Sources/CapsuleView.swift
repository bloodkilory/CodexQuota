import AppKit

final class CapsuleView: NSView {
    var provider: QuotaProviderID = .codex { didSet { needsDisplay = true } }
    var text = "—" { didSet { needsDisplay = true } }
    var remaining: Double? { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
    var action: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { action?() }
    override func accessibilityPerformPress() -> Bool { action?(); return true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = CGRect(x: 2, y: (bounds.height - 18) / 2, width: bounds.width - 4, height: 18)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor.black.setFill()
        shape.fill()

        if let remaining, remaining.isFinite {
            let fraction = min(100, max(0, remaining)) / 100
            let color: NSColor
            if stale { color = NSColor(srgbRed: 0.30, green: 0.32, blue: 0.35, alpha: 1) }
            else if remaining < 10 { color = NSColor(srgbRed: 0.57, green: 0.25, blue: 0.26, alpha: 1) }
            else if remaining < 20 { color = NSColor(srgbRed: 0.50, green: 0.36, blue: 0.19, alpha: 1) }
            else { color = NSColor(srgbRed: 0.25, green: 0.43, blue: 0.38, alpha: 1) }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            color.setFill()
            CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // A subtle edge keeps the black, depleted section visible on dark menu bars.
        NSColor.white.withAlphaComponent(0.20).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 8.75, yRadius: 8.75)
        outline.lineWidth = 0.5
        outline.stroke()
        ProviderMark.draw(provider, in: CGRect(x: rect.minX + 6, y: rect.midY - 6, width: 12, height: 12))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let label = text as NSString
        let size = label.size(withAttributes: attrs)
        let textRect = CGRect(x: rect.minX + 21, y: rect.minY, width: rect.width - 25, height: rect.height)
        label.draw(at: CGPoint(x: textRect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}
