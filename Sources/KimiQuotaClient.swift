import Foundation
import CoreFoundation

/// Only reads the official mainland OAuth slot. Never reads configured API keys or refreshes tokens.
final class KimiQuotaClient {
    private let home: URL
    private let queue = DispatchQueue(label: "local.quotanest.kimi-credentials")
    private let lock = NSLock()
    private var sessions: [UUID: URLSession] = [:]
    private var stopped = false
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func readAccessToken(now: TimeInterval = Date().timeIntervalSince1970) throws -> String {
        let paths = [".kimi-code/credentials/kimi-code.json", ".kimi/credentials/kimi-code.json"]
        for path in paths {
            let file = home.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw QuotaError(message: "Kimi 官方登录文件类型无效") }
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 65537) ?? Data()
                guard data.count <= 65536,
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = root["access_token"] as? String, !token.isEmpty,
                      token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
                      let expiry = root["expires_at"] as? NSNumber,
                      CFGetTypeID(expiry) != CFBooleanGetTypeID(), expiry.doubleValue.isFinite else {
                    throw QuotaError(message: "Kimi 官方 OAuth 登录文件无效；请在 Kimi Code 中重新登录")
                }
                guard expiry.doubleValue > now else { throw QuotaError(message: "Kimi 登录已过期；请打开 Kimi Code 更新登录后刷新") }
                return token
            } catch let error as QuotaError { throw error }
            catch { throw QuotaError(message: "无法读取 Kimi 官方登录；请在 Kimi Code 中确认登录") }
        }
        throw QuotaError(message: "未找到 Kimi 官方登录；请先在 Kimi Code 中执行 /login（实验接入）")
    }

    func fetch(_ completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async { [self] in
        do {
            let token = try readAccessToken()
            let id = UUID()
            let delegate = KimiUsageTransfer { [weak self] result in
                if let self {
                    self.lock.lock()
                    let session = self.sessions.removeValue(forKey: id)
                    self.lock.unlock()
                    session?.finishTasksAndInvalidate()
                }
                completion(result)
            }
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 25
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            lock.lock()
            if stopped { lock.unlock(); session.invalidateAndCancel(); completion(.failure(QuotaError(message: "Kimi 查询已停止"))); return }
            sessions[id] = session
            lock.unlock()
            var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            session.dataTask(with: request).resume()
        } catch { completion(.failure(error)) }
        }
    }
    func shutdown() {
        lock.lock(); stopped = true; let active = Array(sessions.values); sessions.removeAll(); lock.unlock()
        active.forEach { $0.invalidateAndCancel() }
    }
}

/// Streaming cap also applies when Content-Length is absent or false.
private final class KimiUsageTransfer: NSObject, URLSessionDataDelegate {
    private let completion: (Result<QuotaSnapshot, Error>) -> Void
    private var data = Data()
    private var failure: QuotaError?
    private let limit = 1_048_576
    init(completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) { self.completion = completion }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            failure = QuotaError(message: status == 401 ? "Kimi 登录失效；请在官方客户端重新登录" : status == 429 ? "Kimi 查询过于频繁；请稍后刷新" : "Kimi 额度接口返回错误（%@）",arguments:[String(status)])
        } else if response.expectedContentLength > Int64(limit) { failure = QuotaError(message: "Kimi 额度响应超出大小限制") }
        completionHandler(failure == nil ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count <= limit - chunk.count else { failure = QuotaError(message: "Kimi 额度响应超出大小限制"); dataTask.cancel(); return }
        data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let failure { completion(.failure(failure)) }
        else if let error { completion(.failure(QuotaError(message: "Kimi 网络查询失败（%@）",arguments:[String((error as NSError).code)]))) }
        else { completion(Result { try KimiPayload.decode(data) }) }
    }
}
