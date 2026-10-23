import Foundation
import Security
import LocalAuthentication
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class ClaudeQuotaClient {
    private let queue = DispatchQueue(label: "local.codexquota.claude")
    private let redirectPolicy = NoRedirects()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config, delegate: redirectPolicy, delegateQueue: nil)
    }()
    private func credentials(allowPrompt: Bool) throws -> String {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        var data: Data?
        if FileManager.default.fileExists(atPath: file.path) { data = try Data(contentsOf: file) }
        if data == nil {
            let context = LAContext(); context.interactionNotAllowed = !allowPrompt
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            guard status == errSecSuccess, let payload = value as? Data else {
                if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled { throw QuotaError(message: "钥匙串尚未授权；点击“授权 Claude 登录读取”后重试") }
                throw QuotaError(message: "未找到 Claude 官方登录；请运行 claude auth login")
            }
            data = payload
        }
        guard let data, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let oauth = root["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty else { throw QuotaError(message: "没有可用的 Claude 订阅 OAuth 凭证；请运行 claude auth login") }
        if let expiry = oauth["expiresAt"] as? Double, expiry / 1000 <= Date().timeIntervalSince1970 { throw QuotaError(message: "Claude 登录已过期；请打开 Claude Code 更新登录后刷新") }
        return token
    }
    func fetch(allowPrompt: Bool = false, completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async {
            do {
                let token = try self.credentials(allowPrompt: allowPrompt)
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                self.session.dataTask(with: request) { data, response, error in
                    if let error { completion(.failure(QuotaError(message: "Claude 网络查询失败（%@）",arguments:[String((error as NSError).code)]))); return }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let message = code == 401 ? "Claude 登录失效；请打开 Claude Code 重新登录" : code == 403 ? "Claude 登录缺少额度读取权限；请用官方订阅账号重新登录" : code == 429 ? "Claude 查询过于频繁；等待下次自动刷新" : "Claude 额度接口返回错误（%@）"
                        completion(.failure(QuotaError(message: message,arguments:[String(code)]))); return
                    }
                    completion(Result { try ProviderPayload.claude(data) })
                }.resume()
            } catch { completion(.failure(error)) }
        }
    }
    func shutdown() { queue.sync { session.invalidateAndCancel() } }
}
final class AntigravityQuotaClient {
    private let queue = DispatchQueue(label: "local.codexquota.antigravity")
    private let runner = BoundedCommand()
    func fetch(_ completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async {
            completion(Result {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                guard let executable = [home + "/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw QuotaError(message: "未安装 Antigravity CLI；请安装并登录 agy") }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codexquota-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: directory) }
                for name in ["open", "xdg-open"] { try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent(name).path, withDestinationPath: "/usr/bin/false") }
                let allowed = Set(["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "all_proxy", "no_proxy"])
                var env = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
                env["PATH"] = directory.path + ":" + home + "/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                env["BROWSER"] = "/usr/bin/false"
                let versionData = try self.runner.run(executable, arguments: ["--version"], environment: env, timeout: 5)
                let parts = (String(data: versionData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
                guard parts.count == 3, parts[0] > 1 || (parts[0] == 1 && (parts[1] > 1 || (parts[1] == 1 && parts[2] >= 11))) else { throw QuotaError(message: "请将 Antigravity CLI 升级至 1.1.11 或更新版本") }
                // /usage is an official local command report, not a model prompt.
                // /usr/bin/env -C isolates the workspace without modifying HOME/login storage.
                let data = try self.runner.run("/usr/bin/env", arguments: ["-C", directory.path, executable, "-p", "/usage", "--output-format", "json"], environment: env)
                return try ProviderPayload.antigravity(data)
            })
        }
    }
    func shutdown() { runner.cancel(); queue.sync {} }
}
