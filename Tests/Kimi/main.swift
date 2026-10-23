import Foundation
import Darwin

useTestLanguage()
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func rejected(_ body: () throws -> Void) {
    do { try body(); fatalError("Expected rejection") } catch {}
}
let sample = Data(#"{"usages":{"limit_5h":{"used_ratio":0.3,"reset_time":"2026-10-12T18:00:00Z"},"limit_7d":{"used_ratio":"0.2"},"limit_month_total":{"used_ratio":0.4},"limit_month_code":{"used_ratio":0.25}}}"#.utf8)
let result = try KimiPayload.decode(sample)
check(result.buckets.count == 3, "main and two monthly buckets")
check(result.rateLimitsByLimitId?["kimi"]?.primary?.usedPercent == 30, "ratio must convert to percent")
check(result.rateLimitsByLimitId?["kimi"]?.secondary?.minutes == 10080, "weekly window")
check(result.rateLimitsByLimitId?["kimi-month-total"]?.primary?.minutes == nil, "calendar month must not invent fixed duration")
rejected { _ = try KimiPayload.decode(Data(#"{"usages":{"limit_5h":{"used_ratio":true}}}"#.utf8)) }
rejected { _ = try KimiPayload.decode(Data("{}".utf8)) }
rejected { _ = try KimiPayload.decode(Data(#"{"usages":{"limit_5h":{"used_ratio":-0.1}}}"#.utf8)) }
let overLimit = try KimiPayload.decode(Data(#"{"usages":{"limit_5h":{"used_ratio":1.1}}}"#.utf8))
check(overLimit.remaining == 0, "over-limit usage remains exhausted")
let legacy = try KimiPayload.decode(Data(#"{"usage":{"limit":100,"used":20},"limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":100,"remaining":70,"resetTime":"2026-10-12T18:00:00Z"}}]}"#.utf8))
check(legacy.rateLimitsByLimitId?["kimi"]?.secondary?.usedPercent == 20, "legacy weekly")
check(legacy.rateLimitsByLimitId?["kimi"]?.primary?.usedPercent == 30, "legacy hourly")
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
let client = KimiQuotaClient(home: temp)
rejected { _ = try client.readAccessToken(now: 100) }
let dir = temp.appendingPathComponent(".kimi-code/credentials")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let file = dir.appendingPathComponent("kimi-code.json")
try Data(#"{"access_token":"synthetic","expires_at":99}"#.utf8).write(to: file)
rejected { _ = try client.readAccessToken(now: 100) }
try Data(#"{"access_token":"synthetic"}"#.utf8).write(to: file)
rejected { _ = try client.readAccessToken(now: 100) }
try Data(#"{"access_token":"synthetic\nheader","expires_at":999}"#.utf8).write(to: file)
rejected { _ = try client.readAccessToken(now: 100) }
try Data(#"{"api_key":"synthetic","expires_at":999}"#.utf8).write(to: file)
rejected { _ = try client.readAccessToken(now: 100) }
try Data(#"{"access_token":"synthetic","expires_at":999}"#.utf8).write(to: file)
let validToken = try client.readAccessToken(now: 100)
check(validToken == "synthetic", "valid OAuth")
try Data(repeating: 32, count: 65537).write(to: file)
rejected { _ = try client.readAccessToken(now: 100) }
try FileManager.default.removeItem(at: file)
let legacyDir = temp.appendingPathComponent(".kimi/credentials")
try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
try Data(#"{"access_token":"legacy-synthetic","expires_at":999}"#.utf8).write(to: legacyDir.appendingPathComponent("kimi-code.json"))
let legacyToken = try client.readAccessToken(now: 100)
check(legacyToken == "legacy-synthetic", "legacy official OAuth")
// A FIFO at the credential path must not block opening the file or the UI.
check(mkfifo(file.path, 0o600) == 0, "create synthetic credential FIFO")
let fifoStart = ProcessInfo.processInfo.systemUptime
rejected { _ = try client.readAccessToken(now: 100) }
check(ProcessInfo.processInfo.systemUptime - fifoStart < 1, "nonregular credential must fail promptly")
client.shutdown()
print("Kimi fixture tests passed")

let partial = try KimiPayload.decode(Data(#"{"usages":{"limit_5h":{"used_ratio":0.2},"limit_month_code":{"used_ratio":null}}}"#.utf8))
check(partial.rateLimitsByLimitId?["kimi-month-code"]?.primary != nil,"returned unknown Kimi model must remain selectable")
check(partial.rateLimitsByLimitId?["kimi-month-code"]?.primary?.remaining == nil,"unknown Kimi ratio must not become another model quota")
