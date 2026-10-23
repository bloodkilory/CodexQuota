import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let domain = "local.quotanest.source-ui." + UUID().uuidString
let defaults = UserDefaults(suiteName:domain)!
defer { defaults.removePersistentDomain(forName:domain) }
let selection = DisplaySelection(defaults:defaults)
let fixture = CCSwitchConnection(id:"claude|fixture",providerID:"fixture",harness:"claude",name:"账户 · 路由配置 · My production connection with a long name",origin:"https://api.deepseek.com",configurationRole:"路由配置",supportsBalance:true)
let other = CCSwitchConnection(id:"codex|other",providerID:"other",harness:"codex",name:"Other",origin:"https://other.example",configurationRole:"默认配置",supportsBalance:false)
let payload = try DeepSeekBalance.decode(Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"18.60","granted_balance":"3.60","topped_up_balance":"15.00"},{"currency":"USD","total_balance":"2.01","granted_balance":"0.01","topped_up_balance":"2.00"}]}"#.utf8))
var reading = ConnectedAccountReading()
_ = reading.complete(.success(payload),generation:reading.begin()!)
_ = reading.complete(.failure(DeepSeekQueryError(message:"DeepSeek 凭据失效；请在 CC Switch 检查")),generation:reading.begin()!)
let officialWindow = QuotaWindow(usedPercent:24,windowDurationMins:300,resetsAt:Date().timeIntervalSince1970 + 900)
let officialBucket = QuotaBucket(limitId:"codex",limitName:"Codex",planType:"fixture",primary:officialWindow,secondary:nil,credits:Credits(balance:"5.50",unlimited:false))
var officialReading = ProviderReading(snapshot:QuotaSnapshot(rateLimits:officialBucket,rateLimitsByLimitId:nil))
officialReading.lastSuccess = Date()
for language in [InterfaceLanguage.chinese,.english] {
    useTestLanguage(language)
    var settingsOpened = false, refreshes = 0
    var connections = [fixture,other]
    let actions = ConnectedAccountsActions(select:{ selection.select($0) },refresh:{ _ in refreshes += 1 },settings:{ settingsOpened = true })
    func view() -> NSStackView {
        let model = ConnectedAccountsPresentation(connections:connections,enabled:Set(connections.map(\.id)),readings:[fixture.id:reading],source:selection.source,currency:"CNY",sourceError:nil)
        return ConnectedAccountsView.build(model,officialDetails:OfficialQuotaView.build(provider:selection.provider,reading:officialReading,displayedPeriod:.short,refresh:{ refreshes += 1 },authorize:{}),actions:actions)
    }
    func picker(_ view: NSView) -> DisplaySourcePicker { descendants(view).compactMap { $0 as? DisplaySourcePicker }.first! }
    let first = view()
    let expectedSettings = language == .english ? "Settings" : "设置"
    assert(descendants(first).compactMap { $0 as? NSButton }.contains { $0.title == expectedSettings })
    assert(descendants(first).compactMap { ($0 as? NSTextField)?.stringValue }.contains(language == .english ? "Menu bar shows" : "菜单栏显示"))
    assert(first.arrangedSubviews.firstIndex(of:picker(first)) == 2)
    assert(descendants(first).filter { $0 is NSPopUpButton }.count == 1)
    assert(picker(first).numberOfItems == 9,"8 official sources and only supported connected API sources")
    assert(picker(first).itemTitles.last!.hasSuffix(fixture.name),"user names must not be translated")
    assert(!descendants(first).contains { $0.identifier?.rawValue == "pin-account" })
    func choose(_ index: Int) {
        let control = picker(view()); control.selectItem(at:index)
        control.sendAction(control.action,to:control.target)
    }
    choose(0); assert(selection.source == .official(.codex) && selection.accountID == nil)
    choose(8); assert(selection.source == .api(fixture.id) && selection.accountID == fixture.id)
    let api = view()
    let strings = descendants(api).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(strings.contains(fixture.name) && strings.contains("CNY 18.60"))
    assert(strings.contains(L("DeepSeek 凭据失效；请在 CC Switch 检查")))
    let refresh = descendants(api).first { $0.identifier?.rawValue == "refresh-account" } as! NSButton
    refresh.performClick(nil); assert(refreshes == 1)
    (descendants(api).first { $0.identifier?.rawValue == "settings" } as! NSButton).performClick(nil)
    assert(settingsOpened && selection.source == .api(fixture.id))
    connections.append(CCSwitchConnection(id:"codex|new",providerID:"new",harness:"codex",name:"New",origin:fixture.origin,configurationRole:"默认配置",supportsBalance:true))
    assert(picker(view()).numberOfItems == 10 && selection.source == .api(fixture.id))
    connections = []
    let missing = view()
    assert(!descendants(missing).compactMap { ($0 as? NSTextField)?.stringValue }.contains("CNY 18.60"))
    choose(1); assert(selection.source == .official(.claude) && selection.accountID == nil)
    assert(defaults.string(forKey:"pinnedCCSwitchConnection") == nil)
    assert(DisplaySelection(defaults:defaults).source == .official(.claude))
    // Real AppKit layout, including long English error text and untouched long user names.
    connections = [fixture]; selection.select(.api(fixture.id))
    for source in [DisplaySource.api(fixture.id),.official(.codex),.official(.codebuddy)] {
    selection.select(source)
    let content = view(); content.layoutSubtreeIfNeeded()
    let height = content.fittingSize.height
    content.frame = NSRect(x:0,y:0,width:380,height:height)
    let surface = GlassAppearance.wrap(content,size:content.frame.size)
    let window = NSWindow(contentRect:surface.bounds,styleMask:.borderless,backing:.buffered,defer:false)
    window.appearance = NSAppearance(named:.aqua); window.contentView = surface
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    for child in descendants(content) where child is NSControl {
        let bounds = child.convert(child.bounds,to:content)
        assert(bounds.minX >= -1 && bounds.maxX <= 381,"controls must fit the 380-point popover")
    }
    assert(picker(content).convert(picker(content).bounds,to:content).maxY > height - 130)
    if case .official = source {
        let labels = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }
        assert(labels.contains(L("%@    剩余 %@",L("%@ 小时额度","5"),"76.0%")))
        assert(descendants(content).compactMap { $0 as? NSButton }.filter { $0.title == L("立即刷新") }.count == 1)
    }
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds)!
        surface.cacheDisplay(in:surface.bounds,to:bitmap)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/bilingual-" + language.rawValue + "-" + (selection.accountID == nil ? selection.provider.rawValue : "api") + ".png"))
    }
    }
}
print("PASS bilingual native source picker, Codex→API→Claude, settings/new-source stability, removed-source recovery and 380-point rendering")
for language in [InterfaceLanguage.chinese,.english] {
    useTestLanguage(language)
    let original = selection.source
    var wentBack = false, connected = false, checked = false, installed = false, login: Bool?, quit = false
    let actions = SettingsActions(back:{ wentBack = true },language:{ Localization.shared.preference = $0 },connect:{ connected = true },checkUpdate:{ checked = true },installUpdate:{ installed = true },login:{ login = $0 },quit:{ quit = true })
    let model = SettingsPresentation(connections:[fixture,other],enabled:[fixture.id,other.id],sourceError:nil,discovering:false,language:language,version:"1.8.0",updateState:.available("1.9.0"),previousStatus:UpdateInstallStatus(state:"installed",message:"已更新到 v%@",arguments:["1.8.0"]),availableVersion:"1.9.0",canInstall:true,loginEnabled:false)
    let content = SettingsView.build(model,actions:actions)
    let buttons = descendants(content).compactMap { $0 as? NSButton }
    for id in ["back-details","connect-source","check-updates","install-update","launch-at-login","quit"] { buttons.first { $0.identifier?.rawValue == id }!.performClick(nil) }
    assert(wentBack && connected && checked && installed && login == true && quit)
    assert(selection.source == original,"settings actions never mutate the displayed source")
    let expected = language == .english ? ["Back to details","Connect existing tools…","Check for updates","Update to v1.9.0","Launch at login","Quit QuotaNest"] : ["返回详情","连接已有工具…","检查更新","更新到 v1.9.0","登录时启动","退出余度 QuotaNest"]
    for title in expected { assert(buttons.contains { $0.title == title }) }
    let fields = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(fields.contains(fixture.name + " · Claude Code"))
    assert(fields.contains(language == .english ? "Routed configuration · https://api.deepseek.com" : "路由配置 · https://api.deepseek.com"))
    content.layoutSubtreeIfNeeded()
    content.frame = NSRect(x:0,y:0,width:380,height:content.fittingSize.height)
    let surface = GlassAppearance.wrap(content,size:content.frame.size)
    let window = NSWindow(contentRect:surface.bounds,styleMask:.borderless,backing:.buffered,defer:false)
    window.appearance = NSAppearance(named:.aqua); window.contentView = surface
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    for child in descendants(content) where child is NSControl {
        let bounds = child.convert(child.bounds,to:content)
        assert(bounds.minX >= -1 && bounds.maxX <= 381)
    }
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds)!
        surface.cacheDisplay(in:surface.bounds,to:bitmap)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/bilingual-" + language.rawValue + "-settings.png"))
    }
    let languagePicker = descendants(content).compactMap { $0 as? LanguagePicker }.first!
    assert(languagePicker.itemTitles == [language == .english ? "Follow system" : "跟随系统","中文","English"])
    languagePicker.selectItem(at:language == .english ? 1 : 2)
    languagePicker.sendAction(languagePicker.action,to:languagePicker.target)
    assert(Localization.shared.preference == (language == .english ? .chinese : .english))
    assert(selection.source == original)
}
print("PASS bilingual native settings, language change, connection/update/login/quit actions, provenance and 380-point layout")
let sameName = CCSwitchConnection(id:"claude|same-name",providerID:"same-name",harness:fixture.harness,name:fixture.name,origin:fixture.origin,configurationRole:"默认配置",supportsBalance:true)
let duplicates = ConnectedAccountsPresentation(connections:[fixture,sameName],enabled:[fixture.id,sameName.id],readings:[:],source:.api(sameName.id),currency:nil,sourceError:nil)
var pickedDuplicate: DisplaySource?
let duplicateView = ConnectedAccountsView.build(duplicates,actions:ConnectedAccountsActions(select:{ pickedDuplicate = $0 },refresh:{ _ in },settings:{}))
let duplicatePicker = descendants(duplicateView).compactMap { $0 as? DisplaySourcePicker }.first!
assert(duplicatePicker.numberOfItems == 10,"same-named connections must retain separate source items")
duplicatePicker.selectItem(at:9); duplicatePicker.sendAction(duplicatePicker.action,to:duplicatePicker.target)
assert(pickedDuplicate == .api(sameName.id))
print("PASS duplicate user connection names retain independent source identities")
