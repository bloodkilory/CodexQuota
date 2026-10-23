import AppKit
useTestLanguage()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fixture = CCSwitchConnection(id:"claude|fixture",providerID:"fixture",harness:"claude",name:"DeepSeek",origin:"https://api.deepseek.com",configurationRole:"路由配置",supportsBalance:true)
let payload = try DeepSeekBalance.decode(Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"18.60","granted_balance":"3.60","topped_up_balance":"15.00"}]}"#.utf8))
var reading = ConnectedAccountReading()
_ = reading.complete(.success(payload),generation:reading.begin()!)
var refreshed: String?, settings = false
let actions = ConnectedAccountsActions(select:{ _ in },refresh:{ refreshed = $0 },settings:{ settings = true })
let model = ConnectedAccountsPresentation(connections:[fixture],enabled:[fixture.id],readings:[fixture.id:reading],source:.api(fixture.id),currency:nil,sourceError:nil)
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let root = ConnectedAccountsView.build(model,actions:actions)
for id in ["refresh-account","settings"] {
    let button = descendants(root).first { $0.identifier?.rawValue == id } as! NSButton
    button.performClick(nil)
}
assert(refreshed == fixture.id && settings)
print("PASS native account actions: refresh and settings")
var busy = model; busy.readings[fixture.id]?.refreshing = true
let busyView = ConnectedAccountsView.build(busy,actions:actions)
assert((descendants(busyView).first { $0.identifier?.rawValue == "refresh-account" } as! NSButton).isEnabled == false)
print("PASS native refresh disabled during in-flight query")
for dark in [false,true] {
    app.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
    let content = ConnectedAccountsView.build(model,actions:actions)
    content.layoutSubtreeIfNeeded()
    let height = content.fittingSize.height
    assert(height > 300 && height < 750)
    content.frame = NSRect(x:0,y:0,width:380,height:height)
    let surface = GlassAppearance.wrap(content,size:content.frame.size)
    assert(!(surface is NSVisualEffectView),"NSPopover owns the backdrop; a second effect view produces mismatched corner edges")
    assert(surface.layer?.cornerRadius ?? 0 == 0,"popover content must not draw its own rounded boundary")
    let window = NSWindow(contentRect:surface.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    window.appearance = app.appearance; window.contentView = surface
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    assert(content.frame.width == 380)
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        if let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds) {
            surface.cacheDisplay(in:surface.bounds,to:bitmap)
            let card = descendants(surface).first { $0 is NSBox }!
            let point = card.convert(NSPoint(x:card.bounds.maxX - 8,y:card.bounds.midY),to:surface)
            let scale = CGFloat(bitmap.pixelsWide) / surface.bounds.width
            let color = bitmap.colorAt(x:Int(point.x * scale),y:Int((surface.bounds.height - point.y) * scale))!.usingColorSpace(.deviceRGB)!
            assert(dark ? color.redComponent < 0.45 : color.redComponent > 0.75,"card keeps readable contrast in each appearance")
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/connected-native-" + (dark ? "dark" : "light") + ".png"))
        } else { fatalError("native snapshot unavailable") }
    }
}
print("PASS native account layout: 380-point surface, light/dark snapshots with synthetic balances")
