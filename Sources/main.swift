import AppKit
import Darwin
signal(SIGPIPE, SIG_IGN)
if CommandLine.arguments.contains("--check-all") {
    let group = DispatchGroup()
    let codex = CodexClient(), claude = ClaudeQuotaClient(), antigravity = AntigravityQuotaClient()
    let report: (String, Result<QuotaSnapshot, Error>) -> Void = { name, result in
        switch result {
        case .success(let snapshot):
            let rows = snapshot.namedBuckets.map { name, bucket in
                name + ": " + (bucket.remaining.map { String(format: "%.1f%%", $0) } ?? "unknown")
            }.joined(separator: ", ")
            print(name + " OK " + rows)
        case .failure(let error): print(name + " UNAVAILABLE " + error.localizedDescription)
        }
        group.leave()
    }
    group.enter(); codex.fetch { report("Codex", $0) }
    group.enter(); claude.fetch { report("Claude", $0) }
    group.enter(); antigravity.fetch { report("Antigravity", $0) }
    let completed = group.wait(timeout: .now() + 50) == .success
    codex.shutdown(); claude.shutdown(); antigravity.shutdown()
    exit(completed ? 0 : 1)
}
if CommandLine.arguments.contains("--check") {
    let client = CodexClient()
    let done = DispatchSemaphore(value: 0)
    var ok = false
    client.fetch { result in
        switch result {
        case .success(let snapshot):
            print("Remaining: \(snapshot.remaining.map { String(format: "%.1f%%", $0) } ?? "unknown"); buckets: \(snapshot.buckets.count)"); ok = true
        case .failure(let error): print(error.localizedDescription)
        }
        client.stop(); done.signal()
    }
    _ = done.wait(timeout: .now() + 35)
    // Let queued process cleanup finish before exiting.
    Thread.sleep(forTimeInterval: 0.2)
    exit(ok ? 0 : 1)
}
let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
