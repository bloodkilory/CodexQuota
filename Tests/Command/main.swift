import Foundation
import Darwin
func check(_ condition: Bool, _ text: String) { if !condition { fatalError(text) }; print("PASS \(text)") }
let runner = BoundedCommand()
let output = try runner.run("/bin/echo", arguments: ["hello world"], environment: [:])
check(String(data: output, encoding: .utf8) == "hello world\n", "command preserves argv and output")
do { _ = try runner.run("/usr/bin/false", arguments: [], environment: [:]); fatalError("nonzero exit accepted") } catch { print("PASS command rejects nonzero exit") }
let started = Date()
do { _ = try runner.run("/bin/sleep", arguments: ["15"], environment: [:], timeout: 0.2); fatalError("timeout accepted") } catch { check(Date().timeIntervalSince(started) < 2, "command timeout bounded") }
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let pidFile = dir.appendingPathComponent("child.pid")
do { _ = try runner.run("/bin/sh", arguments: ["-c", "sleep 20 & echo $! > \"$1\"; wait", "probe", pidFile.path], environment: [:], timeout: 0.3); fatalError("timeout accepted") } catch { }
let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
let deadline = Date().addingTimeInterval(2)
while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
check(kill(pid, 0) != 0, "command cleans descendant process group")
let cancelled = BoundedCommand(); cancelled.cancel()
do { _ = try cancelled.run("/bin/echo", arguments: [], environment: [:]); fatalError("cancel ignored") } catch { print("PASS command cancellation prevents launch") }
for _ in 0..<100 {
    let data = try runner.run("/bin/echo", arguments: ["final-response"], environment: [:])
    check(data == Data("final-response\n".utf8), "short-lived child stdout fully drained")
}
