import Foundation
import SQLite3

useTestLanguage()
func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL " + message) }
    print("PASS " + message)
}
func fails(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError("FAIL " + message) } catch { check(!error.localizedDescription.contains("fixture-secret"),message) }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:directory) }
let database = directory.appendingPathComponent("cc-switch.db")
var db: OpaquePointer?
check(sqlite3_open(database.path,&db) == SQLITE_OK,"fixture database opens")
defer { sqlite3_close(db) }
func sql(_ text: String) { check(sqlite3_exec(db,text,nil,nil,nil) == SQLITE_OK,"fixture statement") }
sql("PRAGMA user_version=20; CREATE TABLE providers(id TEXT,app_type TEXT,name TEXT,settings_config TEXT,meta TEXT DEFAULT '{}',is_current INTEGER DEFAULT 0,PRIMARY KEY(id,app_type));")
func insert(_ id: String, _ app: String, _ name: String, _ config: [String:Any], current: Bool = false) throws {
    let json = String(data:try JSONSerialization.data(withJSONObject:config),encoding:.utf8)!
    func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of:"'",with:"''") + "'" }
    sql("INSERT OR REPLACE INTO providers(id,app_type,name,settings_config,is_current) VALUES (\(quote(id)),\(quote(app)),\(quote(name)),\(quote(json)),\(current ? 1 : 0));")
}
try insert("ds","claude","DeepSeek",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-original"]])
try insert("old","claude","Old default",["env":["ANTHROPIC_BASE_URL":"https://relay.example/v1","ANTHROPIC_AUTH_TOKEN":"fixture-secret-relay"]],current:true)
try insert("codex-ds","codex","DeepSeek in Codex",["auth":["OPENAI_API_KEY":"fixture-secret-codex"],"config":"model_provider = \"ds\"\n[model_providers.ds]\nbase_url = \"https://api.deepseek.com/v1\"\n"])
try insert("lookalike","claude","DeepSeek relay",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com.attacker.example/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-wrong"]])
try insert("port","claude","DeepSeek custom port",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com:8443/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-port"]])
try JSONSerialization.data(withJSONObject:["apps":["claude":["mode":"proxy","proxy_route":"ds"]]]).write(to:directory.appendingPathComponent("live-state.json"))
let original = try Data(contentsOf:database)
let store = CCSwitchStore(directory:directory)
let connections = try store.discover()
check(connections.count == 5,"discovers Claude and Codex connections without starting a client")
let deepseek = connections.first { $0.providerID == "ds" }!
check(deepseek.supportsBalance && deepseek.origin == "https://api.deepseek.com","official DeepSeek recognized from endpoint")
check(deepseek.configurationRole == "路由配置" && connections.first { $0.providerID == "old" }!.configurationRole != "路由配置","live routing and old default remain distinct")
check(!connections.first { $0.providerID == "lookalike" }!.supportsBalance && !connections.first { $0.providerID == "port" }!.supportsBalance,"lookalike and custom port never receive DeepSeek credentials")
check(connections.first { $0.harness == "codex" }!.supportsBalance,"Codex named provider endpoint parsed")
let credential = try store.credential(for:deepseek.id)
check(credential.token == "fixture-secret-original","reuses existing Claude credential")
check(!(try JSONEncoder().encode(connections)).contains(Data("fixture-secret".utf8)),"discovery is serializable without credentials")
check(try Data(contentsOf:database) == original,"source database remains unchanged")
try insert("ds","claude","DeepSeek",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-rotated"]])
check(try store.credential(for:deepseek.id).generation != credential.generation,"credential change changes generation")
sql("PRAGMA user_version=999;")
fails("future schema rejected without migration") { _ = try store.discover() }
check(sqlite3_exec(db,"PRAGMA user_version=20",nil,nil,nil) == SQLITE_OK,"restore fixture schema")
fails("missing database is not created") { _ = try CCSwitchStore(directory:directory.appendingPathComponent("missing")).discover() }
check(!FileManager.default.fileExists(atPath:directory.appendingPathComponent("missing/cc-switch.db").path),"missing source never created")
sql("BEGIN EXCLUSIVE;")
let lockStart = ProcessInfo.processInfo.systemUptime
fails("busy source fails without waiting indefinitely") { _ = try store.discover() }
check(ProcessInfo.processInfo.systemUptime - lockStart < 1,"SQLite busy wait is bounded")
sql("ROLLBACK;")

let sample = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"12.50","granted_balance":"2.50","topped_up_balance":"10.00"}]}"#.utf8)
let balance = try DeepSeekBalance.decode(sample)
check(balance.wallets.count == 1 && balance.wallets[0].total == Decimal(string:"12.50"),"exact Decimal total decoded")
check(balance.wallets[0].granted == Decimal(string:"2.50") && balance.wallets[0].toppedUp == 10,"components remain separate from reported total")
check(balance.wallets[0].displayAmount == "CNY 12.50","full currency amount displayed")
for bad in [#"{"is_available":true,"balance_infos":[]}"#,#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"NaN","granted_balance":"0","topped_up_balance":"0"}]}"#,#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1"}]}"#] {
    fails("unknown or incomplete balance is not zero") { _ = try DeepSeekBalance.decode(Data(bad.utf8)) }
}
let zero = try DeepSeekBalance.decode(Data(#"{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}]}"#.utf8))
check(!zero.isAvailable && zero.wallets[0].total == 0,"zero balance is a successful reading")

final class BalanceFixture: URLProtocol {
    static var handler: (URLRequest, BalanceFixture) -> Void = { _,_ in }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler(request,self) }
    override func stopLoading() {}
    func reply(_ status: Int, data: Data = sample, headers: [String:String] = [:]) {
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:headers)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [BalanceFixture.self]
func query(_ client: DeepSeekBalanceClient, id: String = deepseek.id) -> Result<DeepSeekBalance,Error> {
    let done = DispatchSemaphore(value:0)
    var value: Result<DeepSeekBalance,Error> = .failure(ConnectedAccountError(message:"no callback"))
    client.fetch(connectionID:id) { value = $0; done.signal() }
    check(done.wait(timeout:.now()+8) == .success,"balance fetch completes within budget")
    return value
}
var requests = 0
BalanceFixture.handler = { request, fixture in
    requests += 1
    check(request.url?.absoluteString == "https://api.deepseek.com/user/balance" && request.httpMethod == "GET","only fixed official balance endpoint requested")
    check(request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-secret-rotated","existing credential attached only to official balance request")
    fixture.reply(200)
}
let client = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
check((try? query(client).get()) == balance,"production transfer reads exact balance")
client.shutdown()
for status in [401,403,429,500] {
    requests = 0
    BalanceFixture.handler = { _,fixture in requests += 1; fixture.reply(status,data:Data("fixture-secret-server-body".utf8),headers:status == 429 ? ["Retry-After":"60"] : [:]) }
    let client = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
    fails("HTTP \(status) fails without leaking body") { _ = try query(client).get() }
    check(requests == (status == 500 ? 2 : 1),"HTTP \(status) retry classification")
    if status == 429 {
        fails("Retry-After blocks next poll") { _ = try query(client).get() }
        check(requests == 1,"rate-limited poll does not send another request")
    }
    client.shutdown()
}
BalanceFixture.handler = { _,fixture in fixture.reply(200,data:Data(repeating:65,count:1_048_577)) }
let largeClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
fails("streamed response size is capped") { _ = try query(largeClient).get() }
largeClient.shutdown()

BalanceFixture.handler = { _,fixture in
    try! insert("ds","claude","DeepSeek",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-new-generation"]])
    fixture.reply(200)
}
let changedClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
fails("credential change discards old balance result") { _ = try query(changedClient).get() }
changedClient.shutdown()
let stoppedClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
stoppedClient.shutdown()
requests = 0; BalanceFixture.handler = { _,fixture in requests += 1; fixture.reply(200) }
fails("shutdown prevents new network request") { _ = try query(stoppedClient).get() }
check(requests == 0,"no request after shutdown")

requests = 0
BalanceFixture.handler = { _,fixture in requests += 1; fixture.reply(302,headers:["Location":"https://attacker.example/balance"]) }
let redirectClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
fails("redirect rejected without forwarding credentials") { _ = try query(redirectClient).get() }
check(requests == 1,"redirect does not start a second request")
redirectClient.shutdown()

try insert("codex-ds","codex","DeepSeek in Codex",["auth":["OPENAI_API_KEY":"fixture-secret-new-generation"],"config":"model_provider = \"ds\"\n[model_providers.ds]\nbase_url = \"https://api.deepseek.com/v1\"\n"])
let countLock = NSLock(), pairDone = DispatchSemaphore(value:0)
requests = 0
BalanceFixture.handler = { _,fixture in countLock.lock(); requests += 1; countLock.unlock(); Thread.sleep(forTimeInterval:0.15); fixture.reply(200) }
let sharedClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
for id in [deepseek.id,"codex|codex-ds"] { sharedClient.fetch(connectionID:id) { value in check((try? value.get()) == balance,"shared wallet callback receives balance"); pairDone.signal() } }
check(pairDone.wait(timeout:.now()+5) == .success && pairDone.wait(timeout:.now()+5) == .success,"both tool callbacks complete")
check(requests == 1,"same official token across tools gets one transfer")
sharedClient.shutdown()

let started = DispatchSemaphore(value:0), cancelled = DispatchSemaphore(value:0)
BalanceFixture.handler = { _,_ in started.signal() }
let cancellationClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
cancellationClient.fetch(connectionID:deepseek.id) { result in if case .failure = result { cancelled.signal() } }
check(started.wait(timeout:.now()+3) == .success,"stalled transfer starts")
cancellationClient.shutdown()
check(cancelled.wait(timeout:.now()+3) == .success,"shutdown cancels active transfer and completes")

BalanceFixture.handler = { _,_ in }
let timeoutClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:0.4)
let queryStart = ProcessInfo.processInfo.systemUptime
fails("stalled query has one bounded deadline") { _ = try query(timeoutClient).get() }
check(ProcessInfo.processInfo.systemUptime - queryStart < 1,"timeout never waits until next minute")
timeoutClient.shutdown()

var reading = ConnectedAccountReading()
let first = reading.begin()
check(first != nil && reading.begin() == nil,"refresh coalesces duplicate in-flight actions")
check(reading.complete(.success(balance),generation:first!),"current generation applies")
let second = reading.begin()!
_ = reading.complete(.failure(DeepSeekQueryError(message:"network")),generation:second)
check(reading.balance == balance && reading.error != nil,"network failure keeps explicitly stale balance")
let third = reading.begin()!
_ = reading.complete(.failure(DeepSeekQueryError(message:"changed",sourceChanged:true)),generation:third)
check(reading.balance == nil && reading.lastSuccess == nil,"source change clears wrongly attributed old balance")
let fourth = reading.begin()!
reading.invalidate()
check(!reading.complete(.success(balance),generation:fourth) && reading.balance == nil,"late result after disconnect is ignored")

BalanceFixture.handler = { _,fixture in fixture.reply(200) }
let rotationClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
_ = query(rotationClient)
try insert("ds","claude","DeepSeek",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-next-account"]])
let rotationDone = DispatchSemaphore(value:0)
var observedRotation = false
rotationClient.fetch(connectionID:deepseek.id,onSourceChange:{ observedRotation = true }) { _ in rotationDone.signal() }
check(rotationDone.wait(timeout:.now()+5) == .success && observedRotation,"rotation clears previous reading before replacement query finishes")
rotationClient.shutdown()

var replacedReading = ConnectedAccountReading()
let replacedGeneration = replacedReading.begin()!
_ = replacedReading.complete(.success(balance),generation:replacedGeneration)
try insert("ds","claude","Changed service",["env":["ANTHROPIC_BASE_URL":"https://third-party.example/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-secret-other"]])
let replacedConnection = try store.discover().first { $0.id == deepseek.id }
replacedReading.reconcile(with:replacedConnection)
check(replacedReading.balance == nil && replacedReading.lastSuccess == nil,"same profile changed to unsupported origin clears old balance")
check(!replacedReading.complete(.success(balance),generation:replacedGeneration),"obsolete result cannot restore unsupported-origin balance")

var busyReading = ConnectedAccountReading()
let busyGeneration = busyReading.begin()!
_ = busyReading.complete(.success(balance),generation:busyGeneration)
sql("BEGIN EXCLUSIVE;")
do { _ = try store.discover(); fatalError("FAIL source should be busy") }
catch { busyReading.discoveryFailed(error) }
sql("ROLLBACK;")
check(busyReading.balance == balance && busyReading.lastSuccess != nil && busyReading.error != nil,"busy source preserves explicitly stale successful balance")
busyReading.discoveryFailed(ConnectedAccountError(message:"missing"))
check(busyReading.balance == nil,"unreadable source clears account attribution")

try insert("ds","claude","DeepSeek A",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-token-A"]])
try insert("second","claude","DeepSeek B",["env":["ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"fixture-token-B"]])
try insert("codex-ds","codex","DeepSeek A in Codex",["auth":["OPENAI_API_KEY":"fixture-token-A"],"config":"model_provider = \"ds\"\n[model_providers.ds]\nbase_url = \"https://api.deepseek.com/v1\"\n"])
let occupied = DispatchSemaphore(value:0), releaseTransfers = DispatchSemaphore(value:0), tripleDone = DispatchSemaphore(value:0)
requests = 0
BalanceFixture.handler = { _,fixture in
    DispatchQueue.global().async {
        countLock.lock(); requests += 1; countLock.unlock(); occupied.signal()
        _ = releaseTransfers.wait(timeout:.now()+3); fixture.reply(200)
    }
}
let queuedSharedClient = DeepSeekBalanceClient(store:store,configuration:configuration,timeout:4)
for id in [deepseek.id,"claude|second"] {
    queuedSharedClient.fetch(connectionID:id) { result in check((try? result.get()) == balance,"occupied worker query succeeds"); tripleDone.signal() }
}
check(occupied.wait(timeout:.now()+3) == .success && occupied.wait(timeout:.now()+3) == .success,"two distinct wallets occupy both transfer workers")
queuedSharedClient.fetch(connectionID:"codex|codex-ds") { result in check((try? result.get()) == balance,"queued shared wallet callback succeeds"); tripleDone.signal() }
Thread.sleep(forTimeInterval:0.2)
for _ in 0..<3 { releaseTransfers.signal() }
for _ in 0..<3 { check(tripleDone.wait(timeout:.now()+5) == .success,"all queued wallet callbacks complete") }
check(requests == 2,"shared wallet joins active transfer even when both workers are occupied")
queuedSharedClient.shutdown()
