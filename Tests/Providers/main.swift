import Foundation
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
