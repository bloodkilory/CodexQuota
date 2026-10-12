import Foundation
import Darwin
signal(SIGPIPE, SIG_IGN)
func probe(_ mode: String, success: Bool) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = directory.appendingPathComponent("codex")
    let source = """
#!/usr/bin/python3
import sys,json,time,os
time.sleep(float(os.environ.get("QUOTANEST_TEST_STARTUP_DELAY", "0")))
for line in sys.stdin:
 x=json.loads(line)
 if x.get('method')=='initialize':
  print(json.dumps({'id':x['id'],'result':{}}),flush=True)
 elif x.get('method')=='initialized':
  pass
 elif x.get('method')=='account/rateLimits/read':
  if '\(mode)'=='timeout': time.sleep(5)
  elif '\(mode)'=='error': print(json.dumps({'id':x['id'],'error':{'code':-32000,'message':'fixture'}}),flush=True)
  elif '\(mode)'=='exit': sys.exit(1)
  else:
   print(json.dumps({'id':9999,'result':{}}),flush=True)
   print(json.dumps({'id':x['id'],'result':{'rateLimits':{'primary':{'usedPercent':42}}}}),flush=True)
"""
    try! source.write(to: fixture, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    let client = CodexClient(executable: fixture.path, timeout: mode == "timeout" ? 0.5 : 10)
    let sem = DispatchSemaphore(value: 0)
    var passed = false
    client.fetch { result in
        switch result {
        case .success(let snapshot): passed = success && snapshot.remaining == 58
        case .failure(let error):
            print("Protocol \(mode) error: \(error.localizedDescription)")
            let message = error.localizedDescription
            passed = !success && (mode == "timeout" ? message.contains("查询超过") :
                mode == "error" ? message.contains("-32000") : message.contains("Codex 已退出"))
        }
        sem.signal()
    }
    guard sem.wait(timeout: .now()+15) == .success, passed else { fatalError("FAIL protocol \(mode)") }
    client.shutdown()
    print("PASS protocol \(mode)")
}
probe("success", success: true)
probe("error", success: false)
probe("timeout", success: false)
probe("exit", success: false)
// A stalled server must not survive an application shutdown.
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let fixture = dir.appendingPathComponent("codex"), pidFile = dir.appendingPathComponent("pid")
try """
#!/usr/bin/python3
import os,time
open('\(pidFile.path)','w').write(str(os.getpid()))
time.sleep(60)
""".write(to: fixture, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
let stalled = CodexClient(executable: fixture.path)
stalled.fetch { _ in }
let startDeadline = Date().addingTimeInterval(10)
while !FileManager.default.fileExists(atPath: pidFile.path) && Date() < startDeadline { Thread.sleep(forTimeInterval: 0.02) }
let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
let started = Date()
stalled.shutdown()
let reapDeadline = Date().addingTimeInterval(1)
while kill(pid, 0) == 0 && Date() < reapDeadline { Thread.sleep(forTimeInterval: 0.02) }
assert(Date().timeIntervalSince(started) < 2, "shutdown must interrupt pending request")
assert(kill(pid, 0) != 0, "child must be gone after shutdown")
try FileManager.default.removeItem(at: dir)
print("PASS protocol shutdown cancels and cleans stalled child")
