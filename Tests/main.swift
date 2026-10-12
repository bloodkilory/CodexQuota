import Foundation
func check(_ condition: Bool, _ name: String) { if !condition { fatalError("FAIL: \(name)") }; print("PASS: \(name)") }
func decode(_ s: String) throws -> QuotaSnapshot { try QuotaSnapshot.decode(Data(s.utf8)) }
let single = try decode(#"{"rateLimits":{"primary":{"usedPercent":3,"windowDurationMins":10080,"resetsAt":1792396076}}}"#)
check(single.remaining == 97, "remaining is not used percent")
check(single.buckets.first?.windows.first?.minutes == 10080, "weekly duration retained")
let multi = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99}},"codex":{"primary":{"usedPercent":3},"secondary":{"usedPercent":80}}}}"#)
check(multi.remaining == 20, "select restrictive Codex window, prefer map")
check(try decode(#"{"rateLimits":{"primary":null}}"#).remaining == nil, "missing window is unknown")
check(try decode(#"{"rateLimits":{"primary":{"usedPercent":-4}}}"#).remaining == 100, "clamp low usage")
check(try decode(#"{"rateLimits":{"primary":{"usedPercent":104}}}"#).remaining == 0, "clamp high usage")
check(try decode(#"{"rateLimits":{"primary":{"resetsAt":42}}}"#).remaining == nil, "missing usedPercent is unknown")
check(try decode(#"{"rateLimitsByLimitId":{},"rateLimits":{"primary":{"usedPercent":25}}}"#).remaining == 75, "empty map falls back")
print("All model tests passed")
