import Foundation
import Darwin
useTestLanguage()
signal(SIGPIPE, SIG_IGN)
setbuf(stdout, nil)
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

// Exercise the real RPC transport against deterministic transient failures.
func recoveryProbe(_ mode: String, expectedSuccess: Bool, requests: Int, launches: Int, fetches: Int = 1) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:directory) }
    let fixture = directory.appendingPathComponent("codex")
    let calls = directory.appendingPathComponent("calls"), starts = directory.appendingPathComponent("starts")
    try """
#!/usr/bin/python3
import sys,json,time,os
with open('\(starts.path)','a') as f: f.write('start\\n')
time.sleep(float(os.environ.get('QUOTANEST_TEST_STARTUP_DELAY','0')))
for line in sys.stdin:
 x=json.loads(line)
 if x.get('method')=='initialize':
  print(json.dumps({'id':x['id'],'result':{}}),flush=True)
 elif x.get('method')=='account/rateLimits/read':
  with open('\(calls.path)','a') as f: f.write(json.dumps(x.get('params'))+'\\n')
  with open('\(calls.path)') as f: count=len(f.readlines())
  mode='\(mode)'
  error=None
  if mode=='background' and x.get('params')!={'excludeResetCreditDetails':True}: error=(-32602,'background usage must exclude reset-credit details')
  if mode=='legacy' and x.get('params') is not None: error=(-32602,'only null params supported')
  if mode=='transient' and count==1 or mode=='persistent' or mode=='reuse' and count==2: error=(-32603,'HTTP error while fetching rate limits: request failed; secret-fixture-do-not-log')
  if mode=='auth': error=(-32603,'HTTP 401 Unauthorized secret-fixture-do-not-log')
  if mode=='limited': error=(-32603,'HTTP 429 Too Many Requests secret-fixture-do-not-log')
  if mode=='invalid': error=(-32601,'unsupported method')
  if mode=='proxy' and os.environ.get('HTTPS_PROXY')!='http://127.0.0.1:17897': error=(-32000,'configured app proxy was not propagated')
  if mode=='exit' and count==1: sys.exit(1)
  if error: print(json.dumps({'id':x['id'],'error':{'code':error[0],'message':error[1]}}),flush=True)
  else: print(json.dumps({'id':x['id'],'result':{'rateLimits':{'primary':{'usedPercent':42}}}}),flush=True)
""".write(to:fixture,atomically:true,encoding:.utf8)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:fixture.path)
    let client = CodexClient(executable:fixture.path,timeout:10)
    defer { client.shutdown() }
    for _ in 0..<fetches {
        let done = DispatchSemaphore(value:0)
        var succeeded = false, failure = "", completions = 0
        let start = ProcessInfo.processInfo.systemUptime
        client.fetch { result in
            completions += 1
            switch result {
            case .success(let snapshot): succeeded = snapshot.remaining == 58
            case .failure(let error): failure = error.localizedDescription
            }
            done.signal()
        }
        guard done.wait(timeout:.now()+12) == .success else { fatalError("FAIL recovery deadline \(mode)") }
        guard succeeded == expectedSuccess, completions == 1 else { fatalError("FAIL recovery \(mode): \(failure)") }
        assert(ProcessInfo.processInfo.systemUptime - start < 11, "one total fetch budget")
        assert(!failure.contains("secret-fixture"), "server details must not leak")
        if mode == "auth" { assert(failure.contains("登录"), "auth error must request login") }
        if mode == "limited" { assert(failure.contains("频繁"), "rate limit must explain wait") }
    }
    let callLines = try String(contentsOf:calls,encoding:.utf8).split(separator:"\n")
    let startLines = try String(contentsOf:starts,encoding:.utf8).split(separator:"\n")
    assert(callLines.count == requests, "\(mode): expected \(requests) requests, got \(callLines.count)")
    assert(startLines.count == launches, "\(mode): expected \(launches) process launches, got \(startLines.count)")
    print("PASS protocol \(mode): \(requests) requests, \(launches) launches")
}
try recoveryProbe("transient",expectedSuccess:true,requests:2,launches:2)
try recoveryProbe("persistent",expectedSuccess:false,requests:2,launches:2)
try recoveryProbe("auth",expectedSuccess:false,requests:1,launches:1)
try recoveryProbe("limited",expectedSuccess:false,requests:1,launches:1)
try recoveryProbe("invalid",expectedSuccess:false,requests:1,launches:1)
try recoveryProbe("exit",expectedSuccess:true,requests:2,launches:2)
try recoveryProbe("background",expectedSuccess:true,requests:1,launches:1)
try recoveryProbe("legacy",expectedSuccess:true,requests:3,launches:1,fetches:2)
try recoveryProbe("reuse",expectedSuccess:true,requests:4,launches:2,fetches:3)
func proxyPreferenceProbe() throws {
    let keys = ["HTTPS_PROXY","https_proxy"]
    let inherited = keys.map { ProcessInfo.processInfo.environment[$0] }
    for key in keys { unsetenv(key) }
    defer {
        for (key,value) in zip(keys,inherited) {
            if let value { setenv(key,value,1) } else { unsetenv(key) }
        }
    }
    // Registration is process-local; this test never changes the user's settings.
    UserDefaults.standard.register(defaults:["codexHTTPSProxy":"http://127.0.0.1:17897"])
    try recoveryProbe("proxy",expectedSuccess:true,requests:1,launches:1)
}
try proxyPreferenceProbe()
