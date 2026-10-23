import Foundation
import CryptoKit
import Darwin

func readChinaCredentialFile(_ file: URL, message: String) throws -> Data {
    // Nonblocking open then fstat closes the FIFO race between a path check and open.
    let fd = open(file.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw ChinaLoginPayload.failure(message) }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var metadata = stat()
    guard fstat(fd, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_size <= 1_048_576,
          let data = try? handle.read(upToCount: 1_048_577), data.count <= 1_048_576 else { throw ChinaLoginPayload.failure(message) }
    return data
}

// Bounded streaming accumulation: completion-handler dataTask would buffer unbounded bodies.
protocol ChinaSessionOwner: AnyObject {
    func activate(_ session: URLSession) -> Bool
    func deactivate(_ session: URLSession)
}
final class ChinaQuotaTransport: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var failed = false
    private let done = DispatchSemaphore(value: 0)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); self.response = response as? HTTPURLResponse; let oversized = response.expectedContentLength > 1_048_576; failed = oversized; lock.unlock()
        completionHandler(oversized ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); let oversized = self.data.count + data.count > 1_048_576
        if oversized { failed = true } else { self.data.append(data) }; lock.unlock()
        if oversized { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { lock.lock(); failed = failed || error != nil; lock.unlock(); done.signal() }
    func run(_ request: URLRequest, owner: ChinaSessionOwner) throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        guard owner.activate(session) else { session.invalidateAndCancel(); throw ChinaLoginPayload.failure("官方额度查询已停止") }
        defer { session.invalidateAndCancel(); owner.deactivate(session) }
        session.dataTask(with: request).resume()
        guard done.wait(timeout: .now() + 27) == .success else { throw ChinaLoginPayload.failure("官方额度查询超时") }
        lock.lock(); defer { lock.unlock() }
        guard !failed else { throw ChinaLoginPayload.failure("官方额度网络查询失败") }
        guard response?.statusCode == 200 else {
            let status = response?.statusCode ?? 0
            throw ChinaLoginPayload.failure(status == 401 || status == 403 ? "官方登录失效或无权限；请打开对应客户端重新登录" : "官方额度接口返回错误（%@）",arguments:[String(status)])
        }
        return data
    }
}

final class MiniMaxQuotaClient: ChinaSessionOwner {
    private let queue = DispatchQueue(label: "local.quotanest.minimax")
    private let lock = NSLock()
    private var active: URLSession?
    private var stopped = false
    func activate(_ session: URLSession) -> Bool { lock.lock(); defer { lock.unlock() }; if stopped { return false }; active = session; return true }
    func deactivate(_ session: URLSession) { lock.lock(); defer { lock.unlock() }; if active === session { active = nil } }
    func shutdown() { lock.lock(); stopped = true; let session = active; lock.unlock(); session?.invalidateAndCancel() }
    private func readCredential() throws -> String {
        let env = ProcessInfo.processInfo.environment
        let override = [env["MINIMAX_DATA_DIR"], env["MAVIS_DATA_DIR"]].compactMap { $0 }.first { !$0.isEmpty }
        let directory = override.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".minimax")
        let file = directory.appendingPathComponent("auth/prod/cn/mcode-public/auth.json")
        let data = try readChinaCredentialFile(file, message: "未找到有效的 MiniMax Code 国内官方登录；请运行 mcode login")
        return try ChinaLoginPayload.credential(data, dataDirectory: directory)
    }
    private func request(_ url: URL, token: String, body: Data? = nil) throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if url.host == "agent.minimaxi.com" {
            if let body { request.httpMethod = "POST"; request.httpBody = body }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("MiniMaxCode", forHTTPHeaderField: "User-Agent")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let millis = query.queryItems!.first { $0.name == "unix" }!.value!
            let second = String(Int64(millis)! / 1000)
            let path = query.percentEncodedPath + "?" + query.percentEncodedQuery!
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
            let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed)!
            let bodyText = body.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            func md5(_ text: String) -> String { Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
            request.setValue(md5(encoded + "_" + bodyText + md5(millis) + "ooui"), forHTTPHeaderField: "yy")
            request.setValue(second, forHTTPHeaderField: "x-timestamp")
            request.setValue(md5(second + "I*7Cf%WZ#S&%1RlZJ&C2" + (body == nil ? "" : bodyText)), forHTTPHeaderField: "x-signature")
        }
        return try ChinaQuotaTransport().run(request, owner: self)
    }
    func fetch(completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async { completion(Result {
            let token = try self.readCredential()
            // The personal workspace supplies X-Group-Id; never select an arbitrary team.
            let millis = String(Int64(Date().timeIntervalSince1970 * 1000))
            var url = URLComponents(string: "https://agent.minimaxi.com/matrix/api/v1/user/get_user_extra_info")!
            url.queryItems = [("device_platform", "mcode"), ("biz_id", "3"), ("app_id", "3001"), ("version_code", "22201"), ("unix", millis), ("timezone_offset", String(TimeZone.current.secondsFromGMT())), ("sys_language", "zh"), ("lang", "zh"), ("device_id", "0"), ("os_name", "darwin"), ("browser_name", "mcode"), ("user_id", "0"), ("client", "mcode")].map { URLQueryItem(name: $0.0, value: $0.1) }
            var identityURL = url
            identityURL.path = "/v1/api/user/info"
            let identityRoot = try ChinaLoginPayload.matrixObject(self.request(identityURL.url!, token: token))
            let identityData = identityRoot["data"] as? [String: Any] ?? identityRoot
            let info = identityData["userInfo"] as? [String: Any] ?? identityData["user_info"] as? [String: Any] ?? [:]
            guard let userID = ChinaLoginPayload.header(info["realUserID"] ?? info["real_user_id"]) else { throw ChinaLoginPayload.failure("MiniMax 官方登录身份无效；请重新登录") }
            url.queryItems = url.queryItems?.map { $0.name == "user_id" ? URLQueryItem(name: "user_id", value: userID) : $0 }
            let root = try ChinaLoginPayload.matrixObject(self.request(url.url!, token: token, body: Data("{}".utf8)))
            let personal = try ChinaLoginPayload.minimaxPersonalWorkspace(root)
            var group = ChinaLoginPayload.minimaxGroup(personal)
            if group == nil {
                // Match the official client's scoped membership lookup; never fall back to a team.
                let workspaceID: Any?
                if let text = ChinaLoginPayload.header(personal["workspace_id"]) { workspaceID = text }
                else if let number = ChinaLoginPayload.number(personal["workspace_id"]), number >= 0 { workspaceID = number }
                else { workspaceID = nil }
                guard let workspaceID else { throw ChinaLoginPayload.failure("MiniMax 个人工作区信息不完整；请在官方客户端检查") }
                var membershipURL = url
                membershipURL.path = "/matrix/api/v1/commerce/get_membership_info"
                let body = try JSONSerialization.data(withJSONObject: ["workspace_id": workspaceID])
                let membership = try ChinaLoginPayload.matrixObject(self.request(membershipURL.url!, token: token, body: body))
                group = ChinaLoginPayload.minimaxGroup(membership)
            }
            guard let group else { throw ChinaLoginPayload.failure("MiniMax 未提供个人 Token Plan 额度账户；请在官方客户端检查套餐") }
            var quota = URLRequest(url: URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!)
            quota.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            quota.setValue(group, forHTTPHeaderField: "X-Group-Id")
            quota.setValue("application/json", forHTTPHeaderField: "Accept")
            return try ChinaLoginPayload.minimax(ChinaQuotaTransport().run(quota, owner: self))
        }) }
    }
}

final class ZCodeQuotaClient: ChinaSessionOwner {
    private let queue = DispatchQueue(label: "local.quotanest.zcode")
    private let lock = NSLock()
    private var active: URLSession?
    private var stopped = false
    func activate(_ session: URLSession) -> Bool { lock.lock(); defer { lock.unlock() }; if stopped { return false }; active = session; return true }
    func deactivate(_ session: URLSession) { lock.lock(); defer { lock.unlock() }; if active === session { active = nil } }
    func shutdown() { lock.lock(); stopped = true; let session = active; lock.unlock(); session?.invalidateAndCancel() }
    private func login() throws -> String {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = env["ZCODE_DATA_BASE_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home
        let file = URL(fileURLWithPath: base).appendingPathComponent(".zcode/v2/credentials.json")
        let data = try readChinaCredentialFile(file, message: "未找到有效的 ZCode 官方登录；请在 ZCode 连接 BigModel 账号")
        let root = try ChinaLoginPayload.object(data)
        guard let value = root["oauth:bigmodel:access_token"] as? String else { throw ChinaLoginPayload.failure("请在 ZCode 使用 BigModel 账号登录") }
        let token = try ChinaLoginPayload.decryptZCode(value, home: home, username: NSUserName(), secret: env["ZCODE_CREDENTIAL_SECRET"])
        guard let valid = ChinaLoginPayload.header(token) else { throw ChinaLoginPayload.failure("ZCode 官方登录凭据无效") }
        return valid.replacingOccurrences(of: "^Bearer\\s+", with: "", options: [.regularExpression, .caseInsensitive])
    }
    private func call(_ path: String, token: String, bearer: Bool = false, body: [String: String]? = nil) throws -> Data {
        guard ChinaLoginPayload.zcodeRequestAllowed(path: path, hasBody: body != nil, bearer: bearer), let url = URL(string: "https://bigmodel.cn" + path), url.host == "bigmodel.cn" else { throw ChinaLoginPayload.failure("ZCode 请求地址无效") }
        var request = URLRequest(url: url)
        request.setValue((bearer ? "Bearer " : "") + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return try ChinaQuotaTransport().run(request, owner: self)
    }
    func fetch(completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async { completion(Result {
            let login = try self.login()
            let metadata = try ChinaLoginPayload.zcodeEnvelope(self.call("/api/biz/customer/getCustomerInfo", token: login)) as? [String: Any] ?? [:]
            let (orgID, projectID) = try ChinaLoginPayload.zcodePersonalProject(metadata)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
            func escaped(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed)! }
            let path = "/api/biz/v1/organization/\(escaped(orgID))/projects/\(escaped(projectID))/api_keys"
            let keys = try ChinaLoginPayload.zcodeEnvelope(self.call(path, token: login)) as? [[String: Any]] ?? []
            // Reuse the official client's existing identifier only. Never create a key.
            guard let existing = keys.first(where: { $0["name"] as? String == "zcode-api-key" }), let keyID = ChinaLoginPayload.header(existing["apiKey"]) else { throw ChinaLoginPayload.failure("请先在 ZCode 连接并使用个人 Coding Plan，完成官方账号初始化") }
            guard try self.login() == login else { throw ChinaLoginPayload.failure("ZCode 登录已变化，请刷新后重试") }
            let token = try ChinaLoginPayload.zcodeProjectToken(self.call(path + "/" + escaped(keyID) + "/access_tokens", token: login, bearer: true, body: ["clientType": "zcode", "clientVersion": "3.15.1"]))
            guard try self.login() == login else { throw ChinaLoginPayload.failure("ZCode 登录已变化，请刷新后重试") }
            return try ChinaLoginPayload.zcode(self.call("/api/monitor/usage/quota/limit", token: token))
        }) }
    }
}
