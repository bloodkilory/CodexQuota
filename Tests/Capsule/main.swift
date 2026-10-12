import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func bitmap(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func render(_ amount: Double?, stale: Bool = false) -> NSBitmapImageRep {
    let rep = bitmap(128, 48)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)
    let view = CapsuleView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
    view.remaining = amount; view.stale = stale; view.text = ""
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func black(_ image: NSBitmapImageRep, _ x: Int) -> Bool {
    let c = image.colorAt(x: x * 2, y: 24)!.usingColorSpace(.deviceRGB)!
    return max(c.redComponent, c.greenComponent, c.blueComponent) < 0.01
}
// Sample away from the provider mark and rounded edge; validate actual rendered pixels.
assert(black(render(0), 40))
assert(!black(render(100), 40))
assert(!black(render(50), 22) && black(render(50), 28))
assert(!black(render(75), 34) && black(render(75), 40))
assert(black(render(-10), 40) && !black(render(110), 40))
assert(black(render(nil), 40) && black(render(.nan), 40))
assert(!black(render(50, stale: true), 22) && black(render(50, stale: true), 28))
print("PASS capsule: 0/50/75/100%, clamping, unknown, invalid and stale pixel coverage")
let rep = bitmap(900, 440)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.94, green: 0.94, blue: 0.92, alpha: 1).setFill()
CGRect(x: 0, y: 0, width: 900, height: 440).fill()
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .black) {
    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
}
label("QuotaNest · Menu bar", x: 35, y: 388, size: 24)
label("Actual rendering · 3× · sample quotas", x: 35, y: 362, size: 13, color: .darkGray)
let amounts: [Double?] = [100, 50, 8, nil]
for (row, provider) in QuotaProviderID.allCases.enumerated() {
    let y = CGFloat(265 - row * 105)
    label(provider.title, x: 35, y: y + 49, size: 13, color: .darkGray)
    for (col, amount) in amounts.enumerated() {
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: CGFloat(30 + col * 215), y: y - 15)
        ctx.scaleBy(x: 3, y: 3)
        let view = CapsuleView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
        view.provider = provider; view.remaining = amount
        view.periodText = col % 2 == 0 ? "5h" : "1w"; view.canSwitchPeriod = amount != nil
        view.text = amount.map { String(format: "%.0f%%", $0) } ?? "—"
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/capsule-preview.png"))

let interactive = CapsuleView(frame: CGRect(x: 0, y: 0, width: 64, height: 24))
var details = 0, switches = 0
interactive.action = { details += 1 }; interactive.periodAction = { switches += 1 }
interactive.canSwitchPeriod = true
interactive.detailButton.performClick(nil)
interactive.periodButton.performClick(nil)
assert(details == 1 && switches == 1)
interactive.canSwitchPeriod = false
interactive.periodButton.performClick(nil)
assert(switches == 1)
assert(interactive.detailButton.frame.maxX == interactive.periodButton.frame.minX)
assert(interactive.periodButton.frame.maxX == 64)
let colors = QuotaProviderID.allCases.map { provider -> NSColor in interactive.provider = provider; return interactive.accentColor }
assert(colors[0] != colors[1] && colors[1] != colors[2] && colors[0] != colors[2])
print("PASS independent detail/period buttons, disabled switch, 64-point layout and provider accents")
