import Foundation
useTestLanguage()
let valid = Data(#"{"user_id":"test","user_type":"personal","user_quota":{"total":1000,"used":250,"remaining":750},"add_on_quota":{"total":100,"used":10},"org_resource_package":{"cap":500,"used":100,"available":true}}"#.utf8)
let snapshot = try QoderPayload.decode(valid)
assert(snapshot.buckets.count == 3)
assert(snapshot.rateLimitsByLimitId?["qoder"]?.remaining == 75)
assert(snapshot.rateLimitsByLimitId?["qoder"]?.primary?.minutes == nil)
assert(snapshot.rateLimitsByLimitId?["qoder"]?.primary?.title == "订阅周期额度")
for bad in [#"{}"#, #"{"user_quota":{"total":100,"used":true}}"#, #"{"user_quota":{"total":0,"used":0}}"#, #"{"user_quota":{"total":100,"used":-1}}"#] {
 do { _ = try QoderPayload.decode(Data(bad.utf8)); fatalError("accepted invalid quota") } catch {}
}
print("Qoder payload tests passed")

for reason in ["version", "expired", "network", "size", "a-secret-token"] {
    let errorPayload = try JSONSerialization.data(withJSONObject: ["quotanest_error": reason])
    do { _ = try QoderPayload.decode(errorPayload); fatalError("accepted helper error") }
    catch { assert(!error.localizedDescription.contains("a-secret-token")) }
}
// stderr floods and synchronous subprocess hangs are bounded by the parent,
// independently of the helper's JS event loop and timer.
let started = ProcessInfo.processInfo.systemUptime
let runner = BoundedCommand()
do {
    _ = try runner.run("/bin/sh", arguments: ["-c", "while :; do printf 'diagnostic\n' >&2; done"], environment: ["PATH": "/usr/bin:/bin"], timeout: 0.15)
    fatalError("unbounded helper succeeded")
} catch {}
assert(ProcessInfo.processInfo.systemUptime - started < 3)
let cancelled = BoundedCommand(); cancelled.cancel()
do { _ = try cancelled.run("/bin/sh", arguments: ["-c", "exit 0"], environment: [:]); fatalError("cancelled runner started") } catch {}
print("Qoder bounded-process and sanitized-status tests passed")

let partial = try QoderPayload.decode(Data(#"{"user_quota":{"total":100,"used":20},"add_on_quota":{"total":100,"used":null}}"#.utf8))
assert(partial.rateLimitsByLimitId?["qoder-addon"]?.primary != nil,"returned unknown Qoder resource must remain selectable")
assert(partial.rateLimitsByLimitId?["qoder-addon"]?.primary?.remaining == nil,"unknown resource must not become subscription balance")
