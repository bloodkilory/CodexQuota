import Foundation
useTestLanguage()
func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) }; print("PASS \(message)") }
let claude = try ProviderPayload.claude(Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-10-12T20:00:00Z"},"seven_day":{"utilization":81,"resets_at":"2026-10-19T20:00:00Z"}}"#.utf8))
expect(claude.remaining == 19, "Claude utilization converted into remaining")
expect(claude.buckets[0].windows[0].resetsAt != nil, "Claude reset ISO date parsed")
let agy = try ProviderPayload.antigravity(Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"weekly","window":"weekly","remaining_fraction":0.31,"reset_time":"2026-10-14T03:25:48Z"},{"id":"5h","disabled":true,"remaining_fraction":0}]},{"name":"Claude and GPT models","buckets":[{"id":"weekly","window":"weekly","remaining_fraction":0}]}]}}}"#.utf8))
expect(agy.buckets.count == 2, "Antigravity keeps separate quota groups")
expect(agy.buckets[0].windows.count == 1, "Disabled Antigravity bucket excluded")
expect(agy.buckets[0].remaining == 31, "Antigravity fraction not treated as used")
expect(agy.buckets[1].remaining == 0, "Exhausted group remains visible")
for source in [#"{"status":"ERROR","command":{"name":"usage","data":{"groups":[]}}}"#, #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"window":"weekly"}]}]}}}"#] {
    do { _ = try ProviderPayload.antigravity(Data(source.utf8)); fatalError("unknown quota accepted") } catch { print("PASS unknown/error quota rejected") }
}
do { _ = try ProviderPayload.claude(Data(#"{"five_hour":null}"#.utf8)); fatalError("missing Claude quota accepted") } catch { print("PASS missing Claude quota rejected") }

expect(ProviderReading(snapshot: agy).remaining(for: .antigravity) == 31, "Antigravity capsule selects Gemini despite exhausted other models")
func group(_ name: String, _ used: Double, _ secondary: Double? = nil) -> QuotaBucket {
    QuotaBucket(limitId: nil, limitName: name, planType: nil,
                primary: QuotaWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: nil),
                secondary: secondary.map { QuotaWindow(usedPercent: $0, windowDurationMins: 300, resetsAt: nil) }, credits: nil)
}
let mixed = QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: ["first": group("Claude and GPT models", 100), "last": group("GEMINI Models", 20, 60), "middle": group("Gemini Pro", 30)])
expect(ProviderReading(snapshot: mixed).remaining(for: .antigravity) == 40, "Gemini matching ignores order and case and takes restrictive Gemini window")
let noGemini = QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: ["other": group("Claude and GPT models", 20)])
expect(ProviderReading(snapshot: noGemini).remaining(for: .antigravity) == nil, "Missing Gemini is unknown instead of another model quota")
expect(ProviderReading(snapshot: mixed).remaining(for: .claude) == 0, "Claude selection retains existing aggregation")

let split = ProviderReading(snapshot: mixed)
expect(split.window(for: .antigravity, period: .short)?.remaining == 40, "Short selection uses Gemini hours only")
expect(split.window(for: .antigravity, period: .weekly)?.remaining == 70, "Weekly selection excludes hour limits and other families")
expect(split.periodLabel(for: .antigravity, period: .short) == "5h", "Period label follows actual window duration")
expect(split.periods(for: .antigravity) == [.short, .weekly], "Two valid periods support switching")
let weeklyOnly = ProviderReading(snapshot: agy)
expect(weeklyOnly.period(for: .antigravity, preferred: .short) == .weekly, "Disabled hours fall back to available weekly period")
expect(weeklyOnly.periods(for: .antigravity) == [.weekly], "Disabled hour window is not switchable")
expect(ProviderReading(snapshot: noGemini).periods(for: .antigravity).isEmpty, "Other families cannot provide Gemini switch periods")

let monthly = QuotaWindow(usedPercent: 25, windowDurationMins: nil, resetsAt: nil, periodLabel: "月度额度")
let billing = QuotaBucket(limitId: "qoder", limitName: "Qoder", planType: nil, primary: monthly, secondary: nil, credits: nil)
let emptyAddon = QuotaBucket(limitId: "qoder-addon", limitName: "Addon", planType: nil, primary: QuotaWindow(usedPercent: 100, windowDurationMins: nil, resetsAt: nil), secondary: nil, credits: nil)
let credits = ProviderReading(snapshot: QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: ["qoder": billing, "qoder-addon": emptyAddon]))
expect(credits.periods(for: .qoder) == [.billing], "Credits use billing period without an invented duration")
expect(credits.window(for: .qoder, period: .billing)?.remaining == 75, "Exhausted optional add-on does not hide remaining subscription")
expect(credits.periodLabel(for: .qoder, period: .billing) == "额", "Billing capsule has compact label")
expect(monthly.title == "月度额度", "Calendar-month title preserved")
expect(QuotaProviderID.allCases.filter { $0.experimental }.count == 5, "Five new adapters explicitly experimental")
