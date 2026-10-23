import Foundation
import SQLite3
import CryptoKit
import Darwin

struct ConnectedAccountError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct CCSwitchConnection: Codable, Equatable {
    let id: String
    let providerID: String
    let harness: String
    let name: String
    let origin: String
    let configurationRole: String
    let supportsBalance: Bool
}
struct CCSwitchCredential {
    let token: String
    let generation: String
}
struct CCSwitchStore {
    let directory: URL
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-switch")) { self.directory = directory }
    private func failure(_ text: String) -> ConnectedAccountError { ConnectedAccountError(message:text) }
    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let file = directory.appendingPathComponent("cc-switch.db")
        var info = stat()
        guard stat(file.path,&info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw failure("未找到 CC Switch 数据库；请先在 CC Switch 配置服务") }
        var pointer: OpaquePointer?
        let result = sqlite3_open_v2(file.path,&pointer,SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,nil)
        defer { if let pointer { sqlite3_close(pointer) } }
        guard result == SQLITE_OK, let db = pointer else { throw failure("无法只读打开 CC Switch 数据库") }
        sqlite3_busy_timeout(db,200)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,"PRAGMA user_version",-1,&statement,nil) == SQLITE_OK else { throw failure("CC Switch 数据格式不兼容") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, (18...20).contains(Int(sqlite3_column_int(statement,0))) else { throw failure("CC Switch 数据版本不兼容；本版支持 schema 18–20") }
        return try body(db)
    }
    private func rows(db: OpaquePointer, id: String? = nil) throws -> [(String,String,String,String,Bool)] {
        let query = "SELECT id,app_type,name,settings_config,is_current FROM providers WHERE app_type IN ('claude','codex')" + (id == nil ? " ORDER BY app_type,name LIMIT 501" : " AND app_type=? AND id=? LIMIT 1")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,query,-1,&statement,nil) == SQLITE_OK else { throw failure("CC Switch 服务配置格式不兼容") }
        defer { sqlite3_finalize(statement) }
        if let id {
            let parts = id.split(separator:"|",maxSplits:1,omittingEmptySubsequences:false)
            guard parts.count == 2, ["claude","codex"].contains(String(parts[0])) else { throw failure("CC Switch 连接标识无效") }
            let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
            sqlite3_bind_text(statement,1,String(parts[0]),-1,transient)
            sqlite3_bind_text(statement,2,String(parts[1]),-1,transient)
        }
        var result: [(String,String,String,String,Bool)] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw failure(step == SQLITE_BUSY || step == SQLITE_LOCKED ? "CC Switch 正在更新配置；下次自动检查" : "CC Switch 服务配置读取失败") }
            guard result.count < 500 else { throw failure("CC Switch 服务数量超出读取范围") }
            var values: [String] = []
            for column in 0..<4 {
                guard sqlite3_column_bytes(statement,Int32(column)) <= 1_048_576,
                      let text = sqlite3_column_text(statement,Int32(column)) else { throw failure("CC Switch 服务配置无效") }
                values.append(String(cString:text))
            }
            result.append((values[0],values[1],values[2],values[3],sqlite3_column_int(statement,4) != 0))
        }
        return result
    }
    private func object(_ text: String) throws -> [String:Any] {
        guard let data = text.data(using:.utf8), data.count <= 1_048_576,
              let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw failure("CC Switch 服务 JSON 无效") }
        return value
    }
    private func endpoint(_ config: [String:Any], harness: String) -> String {
        if harness == "claude" { return (config["env"] as? [String:Any])?["ANTHROPIC_BASE_URL"] as? String ?? "" }
        guard let toml = config["config"] as? String else { return "" }
        var section = "", values: [String:[String:String]] = [:]
        for raw in toml.split(whereSeparator:\.isNewline) {
            let line = raw.trimmingCharacters(in:.whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
            guard let equal = line.firstIndex(of:"=") else { continue }
            let key = line[..<equal].trimmingCharacters(in:.whitespaces)
            let value = line[line.index(after:equal)...].trimmingCharacters(in:.whitespaces)
            guard ["model_provider","base_url"].contains(key), let quote = value.first, ["\"","'"].contains(quote),
                  let end = value.dropFirst().firstIndex(of:quote) else { continue }
            values[section,default:[:]][key] = String(value[value.index(after:value.startIndex)..<end])
        }
        guard let provider = values[""]?["model_provider"] else { return "" }
        return values["model_providers." + provider]?["base_url"] ?? values["model_providers.\"" + provider + "\""]?["base_url"] ?? ""
    }
    private func origin(_ endpoint: String) -> (String,Bool) {
        guard let url = URLComponents(string:endpoint), let scheme = url.scheme, let host = url.host,
              url.user == nil, url.password == nil else { return ("",false) }
        let origin = scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
        let supported = scheme == "https" && host.lowercased() == "api.deepseek.com" && url.port == nil && url.query == nil && url.fragment == nil
        return (origin,supported)
    }
    private func routes() -> [String:Any] {
        let path = directory.appendingPathComponent("live-state.json")
        let fd = open(path.path,O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return [:] }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd,&info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 1_048_576,
              let data = try? handle.read(upToCount:1_048_577), data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return root["apps"] as? [String:Any] ?? [:]
    }
    func discover() throws -> [CCSwitchConnection] {
        let live = routes()
        return try withDatabase { db in
            try rows(db:db).map { id,harness,name,raw,current in
                let config = try object(raw), (endpointOrigin,supported) = origin(endpoint(config,harness:harness))
                let state = live[harness] as? [String:Any] ?? [:]
                let mode = state["mode"] as? String ?? "unknown"
                let routed = ["proxy","routing"].contains(mode) && state["proxy_route"] as? String == id
                let role = routed ? "路由配置" : mode == "aggregation" ? "已保存 · 聚合模式" : current ? "默认配置" : "已保存配置"
                let title = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80).map(String.init).joined())
                return CCSwitchConnection(id:harness + "|" + id,providerID:id,harness:harness,name:title.isEmpty ? "未命名服务" : title,origin:endpointOrigin,configurationRole:role,supportsBalance:supported)
            }
        }
    }
    func credential(for id: String) throws -> CCSwitchCredential {
        try withDatabase { db in
            guard let row = try rows(db:db,id:id).first else { throw failure("CC Switch 来源已移除；请重新选择连接") }
            let config = try object(row.3)
            guard origin(endpoint(config,harness:row.1)).1 else { throw failure("该连接不是 DeepSeek 官方 API；不会向其他地址发送凭据") }
            let env = config["env"] as? [String:Any] ?? [:], auth = config["auth"] as? [String:Any] ?? [:]
            let value = row.1 == "claude" ? (env["ANTHROPIC_AUTH_TOKEN"] ?? env["ANTHROPIC_API_KEY"]) : auth["OPENAI_API_KEY"]
            guard let token = value as? String, !token.isEmpty, token.utf8.count <= 16_384,
                  !["PROXY_MANAGED","CC_SWITCH_PROXY_MANAGED"].contains(token),
                  !token.unicodeScalars.contains(where:{ CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { throw failure("CC Switch 中没有可用的 DeepSeek 凭据；请在原工具配置") }
            let generation = SHA256.hash(data:Data((id + "\u{0}" + token).utf8)).map { String(format:"%02x",$0) }.joined()
            return CCSwitchCredential(token:token,generation:generation)
        }
    }
}
