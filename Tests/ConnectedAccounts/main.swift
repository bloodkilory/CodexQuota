import Foundation
import SQLite3

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
