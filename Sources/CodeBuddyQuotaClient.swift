import Foundation
import Security
import LocalAuthentication
import SQLite3
import CommonCrypto

enum CodeBuddyLogin {
    static let secretKey = #"secret://{"extensionId":"tencent-cloud.coding-copilot","key":"Tencent-Cloud.coding-copilot.new.accessToken"}"#
    private static var invalid: QuotaError { QuotaError(message: "CodeBuddy 官方登录格式无效；请在 VS Code 的 CodeBuddy 扩展中重新登录") }

    static func encryptedSecret(database: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: database.path) else { throw QuotaError(message: "未找到 VS Code 的 CodeBuddy 官方登录；请安装官方扩展并登录") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; throw invalid }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 262144)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1", -1, &statement, nil) == SQLITE_OK else { throw invalid }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, secretKey, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { throw QuotaError(message: "未找到 VS Code 的 CodeBuddy 官方登录；请在扩展中重新登录") }
        let size = Int(sqlite3_column_bytes(statement, 0))
        guard size > 0, size <= 262144, let bytes = sqlite3_column_blob(statement, 0) else { throw invalid }
        let raw = Data(bytes: bytes, count: size)
        guard let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              root["type"] as? String == "Buffer", let values = root["data"] as? [Any], values.count <= 65536 else { throw invalid }
        var encrypted = Data()
        for value in values {
            guard let number = CodeBuddyPayload.number(value), number >= 0, number <= 255, number.rounded(.towardZero) == number else { throw invalid }
            encrypted.append(UInt8(number))
        }
        guard encrypted.prefix(3) == Data("v10".utf8), encrypted.count > 3, (encrypted.count - 3) % 16 == 0 else { throw invalid }
        return encrypted
    }

    static func decrypt(_ encrypted: Data, password: Data) throws -> Data {
        guard encrypted.prefix(3) == Data("v10".utf8), encrypted.count > 3, encrypted.count <= 65536, (encrypted.count - 3) % 16 == 0, !password.isEmpty, password.count <= 4096 else { throw invalid }
        var key = [UInt8](repeating: 0, count: 16)
        defer { _ = key.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let salt = Array("saltysalt".utf8)
        let derived = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        guard derived == kCCSuccess else { throw invalid }
        let cipher = Data(encrypted.dropFirst(3)), iv = [UInt8](repeating: 32, count: 16)
        var clear = [UInt8](repeating: 0, count: cipher.count + 16), written = 0
        let capacity = clear.count
        let result = cipher.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key, key.count, iv, bytes.baseAddress, cipher.count, &clear, capacity, &written)
        }
        defer { _ = clear.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard result == kCCSuccess else { throw invalid }
        return Data(clear.prefix(written))
    }

    static func accessToken(_ clear: Data, now: TimeInterval = Date().timeIntervalSince1970) throws -> String {
        guard clear.count <= 65536, let root = try? JSONSerialization.jsonObject(with: clear) as? [String: Any],
              let auth = root["auth"] as? [String: Any], let token = auth["accessToken"] as? String,
              !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              let domain = auth["domain"] as? String,
              ["https://www.codebuddy.cn", "https://copilot.tencent.com", "www.codebuddy.cn", "copilot.tencent.com"].contains(domain.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { throw invalid }
        if let account = root["account"] as? [String: Any], let type = account["type"] as? String, type != "personal" { throw QuotaError(message: "CodeBuddy 实验接入仅支持国内个人账号") }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw invalid }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let payload = Data(base64Encoded: encoded),
              let jwt = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], let expires = CodeBuddyPayload.number(jwt["exp"]) else { throw invalid }
        guard expires > now else { throw QuotaError(message: "CodeBuddy 登录已过期；请打开官方扩展更新登录后刷新") }
        return token
    }

    static func keychainPassword(allowPrompt: Bool) throws -> Data {
        let context = LAContext(); context.interactionNotAllowed = !allowPrompt
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Code Safe Storage", kSecAttrAccount as String: "Code Key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, !data.isEmpty, data.count <= 4096 else {
            throw QuotaError(message: "CodeBuddy 登录读取尚未获钥匙串授权；点击“授权 CodeBuddy 登录读取”后重试")
        }
        return data
    }
}

final class CodeBuddyQuotaClient: ChinaSessionOwner {
    private let queue = DispatchQueue(label: "local.quotanest.codebuddy")
    private let lock = NSLock()
    private var active: URLSession?
    private var stopped = false
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    func activate(_ session: URLSession) -> Bool { lock.lock(); defer { lock.unlock() }; if stopped { return false }; active = session; return true }
    func deactivate(_ session: URLSession) { lock.lock(); defer { lock.unlock() }; if active === session { active = nil } }
    func shutdown() { lock.lock(); stopped = true; let session = active; lock.unlock(); session?.invalidateAndCancel() }
    func fetch(allowPrompt: Bool = false, completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async { completion(Result {
            self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
            guard !stopped else { throw QuotaError(message: "CodeBuddy 查询已停止") }
            let database = self.home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/state.vscdb")
            let encrypted = try CodeBuddyLogin.encryptedSecret(database: database)
            let password = try CodeBuddyLogin.keychainPassword(allowPrompt: allowPrompt)
            let token = try CodeBuddyLogin.accessToken(CodeBuddyLogin.decrypt(encrypted, password: password))
            var request = URLRequest(url: URL(string: "https://www.codebuddy.cn/billing/meter/get-user-resource")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("web", forHTTPHeaderField: "X-Client-Platform")
            request.setValue("https://www.codebuddy.cn", forHTTPHeaderField: "Origin")
            request.setValue("https://www.codebuddy.cn/profile/plans-usage", forHTTPHeaderField: "Referer")
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
            let day = formatter.string(from: Date())
            request.httpBody = try JSONSerialization.data(withJSONObject: ["PageNumber": 1, "PageSize": 200, "ProductCode": "p_tcaca", "Status": [0, 3], "OnlyValidPeriod": true, "NeedInUsage": true, "SlicePeriodStartTime": day + " 00:00:00", "SlicePeriodEndTime": day + " 23:59:59"])
            return try CodeBuddyPayload.decode(ChinaQuotaTransport().run(request, owner: self))
        }) }
    }
}
