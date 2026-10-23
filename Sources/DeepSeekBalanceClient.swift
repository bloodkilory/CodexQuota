import Foundation
import CryptoKit

struct DeepSeekQueryError: LocalizedError {
    let message: String
    var retryable = false
    var retryAt: Date? = nil
    var sourceChanged = false
    var errorDescription: String? { message }
}

final class DeepSeekBalanceClient {
    private struct Listener {
        let id: String, generation: String
        let completion: (Result<DeepSeekBalance,Error>) -> Void
    }
    private let store: CCSwitchStore
    private let configuration: URLSessionConfiguration
    private let timeout: TimeInterval
    private let operations = OperationQueue()
    private let resolutionQueue = DispatchQueue(label:"local.quotanest.deepseek.resolve")
    private let lock = NSLock()
    private var stopped = false
    private var sessions: [UUID:URLSession] = [:]
    private var pending: [String:[Listener]] = [:]
    private var limited: [String:Date] = [:]
    private var revisions: [String:String] = [:]
    init(store: CCSwitchStore = CCSwitchStore(), configuration: URLSessionConfiguration = .ephemeral, timeout: TimeInterval = 30) {
        self.store = store; self.configuration = configuration; self.timeout = min(30,max(0.1,timeout))
        operations.maxConcurrentOperationCount = 2
        operations.qualityOfService = .utility
    }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    fileprivate func attach(_ session: URLSession) -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return nil }
        let id = UUID(); sessions[id] = session; return id
    }
    fileprivate func detach(_ id: UUID) { lock.lock(); sessions.removeValue(forKey:id); lock.unlock() }
    func fetch(connectionID: String, onSourceChange: @escaping () -> Void = {}, completion: @escaping (Result<DeepSeekBalance,Error>) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        resolutionQueue.async {
            do {
                guard !self.isStopped else { throw DeepSeekQueryError(message:"余额查询已停止") }
                let credential = try self.store.credential(for:connectionID)
                self.lock.lock()
                let changed = self.revisions[connectionID].map { $0 != credential.generation } ?? false
                self.revisions[connectionID] = credential.generation
                self.lock.unlock()
                if changed { onSourceChange() }
                // This adapter has one fixed account-balance scope: the same
                // official token gets one transfer even when two tools use it.
                let key = SHA256.hash(data:Data(credential.token.utf8)).map { String(format:"%02x",$0) }.joined()
                let listener = Listener(id:connectionID,generation:credential.generation,completion:completion)
                self.lock.lock()
                if let next = self.limited[key], next > Date() {
                    self.lock.unlock()
                    throw DeepSeekQueryError(message:"DeepSeek 查询受限；等待服务允许后自动检查",retryAt:next)
                }
                if self.pending[key] != nil {
                    self.pending[key]?.append(listener); self.lock.unlock(); return
                }
                self.pending[key] = [listener]; self.lock.unlock()
                self.operations.addOperation {
                    let result = Result { try self.read(token:credential.token,deadline:deadline) }
                    self.lock.lock()
                    let listeners = self.pending.removeValue(forKey:key) ?? []
                    if case .failure(let error) = result, let retry = (error as? DeepSeekQueryError)?.retryAt { self.limited[key] = retry }
                    self.lock.unlock()
                    for listener in listeners {
                        do {
                            guard !self.isStopped else { throw DeepSeekQueryError(message:"余额查询已停止") }
                            let current = try self.store.credential(for:listener.id)
                            guard current.generation == listener.generation else { throw DeepSeekQueryError(message:"CC Switch 连接已变化；已丢弃旧余额，请刷新",sourceChanged:true) }
                            listener.completion(result)
                        } catch {
                            let busy = (error as? ConnectedAccountError)?.isTransient == true
                            listener.completion(.failure(DeepSeekQueryError(message:busy ? error.localizedDescription : "CC Switch 来源已变化或不可读；已丢弃旧余额，请重新检查连接",sourceChanged:!busy)))
                        }
                    }
                }
            } catch {
                if let sourceError = error as? ConnectedAccountError {
                    completion(.failure(DeepSeekQueryError(message:error.localizedDescription,sourceChanged:!sourceError.isTransient)))
                } else { completion(.failure(error)) }
            }
        }
    }
    private func read(token: String, deadline: TimeInterval) throws -> DeepSeekBalance {
        for attempt in 0..<2 {
            guard !isStopped else { throw DeepSeekQueryError(message:"余额查询已停止") }
            let attemptEnd = min(deadline,ProcessInfo.processInfo.systemUptime + timeout / 2)
            do {
                guard attemptEnd > ProcessInfo.processInfo.systemUptime else { throw DeepSeekQueryError(message:"DeepSeek 余额查询超时") }
                var request = URLRequest(url:URL(string:"https://api.deepseek.com/user/balance")!)
                request.httpMethod = "GET"
                request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
                request.setValue("application/json",forHTTPHeaderField:"Accept")
                request.setValue("QuotaNest",forHTTPHeaderField:"User-Agent")
                let data = try DeepSeekBalanceTransfer().run(request,configuration:configuration,owner:self,deadline:attemptEnd)
                return try DeepSeekBalance.decode(data)
            } catch {
                guard attempt == 0, (error as? DeepSeekQueryError)?.retryable == true,
                      !isStopped, ProcessInfo.processInfo.systemUptime + 1 < deadline else { throw error }
                let next = ProcessInfo.processInfo.systemUptime + 1
                while !isStopped && ProcessInfo.processInfo.systemUptime < next { Thread.sleep(forTimeInterval:0.05) }
            }
        }
        throw DeepSeekQueryError(message:"DeepSeek 余额查询失败")
    }
    func shutdown() {
        lock.lock(); stopped = true; let active = Array(sessions.values); lock.unlock()
        active.forEach { $0.invalidateAndCancel() }
    }
}

private final class DeepSeekBalanceTransfer: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var failure: DeepSeekQueryError?
    private let done = DispatchSemaphore(value:0)
    private let limit = 1_048_576
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        failure = DeepSeekQueryError(message:"DeepSeek 余额请求发生重定向；已拒绝转发凭据")
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse, status = http?.statusCode ?? 0
        if status != 200 {
            let text = status == 401 ? "DeepSeek 凭据失效；请在 CC Switch 检查" : status == 403 ? "DeepSeek 没有余额查询权限；请在原平台检查" : status == 429 ? "DeepSeek 查询受限；等待下次自动检查" : "DeepSeek 余额接口暂不可用（\(status)）"
            var retryAt: Date?
            if status == 429 {
                let value = http?.value(forHTTPHeaderField:"Retry-After") ?? ""
                if let seconds = Double(value), seconds.isFinite, seconds >= 0 { retryAt = Date().addingTimeInterval(seconds) }
                else {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0)
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    retryAt = formatter.date(from:value) ?? Date().addingTimeInterval(60)
                }
            }
            failure = DeepSeekQueryError(message:text,retryable:(500...599).contains(status),retryAt:retryAt)
        } else if response.expectedContentLength > Int64(limit) { failure = DeepSeekQueryError(message:"DeepSeek 余额响应超出大小限制") }
        completionHandler(failure == nil ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= limit - data.count else { failure = DeepSeekQueryError(message:"DeepSeek 余额响应超出大小限制"); dataTask.cancel(); return }
        data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil, error != nil { failure = DeepSeekQueryError(message:"DeepSeek 余额网络查询失败；稍后自动重试",retryable:true) }
        done.signal()
    }
    func run(_ request: URLRequest, configuration: URLSessionConfiguration, owner: DeepSeekBalanceClient, deadline: TimeInterval) throws -> Data {
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        let budget = max(0.01,deadline - ProcessInfo.processInfo.systemUptime)
        config.timeoutIntervalForRequest = budget; config.timeoutIntervalForResource = budget
        let session = URLSession(configuration:config,delegate:self,delegateQueue:nil)
        guard let id = owner.attach(session) else { session.invalidateAndCancel(); throw DeepSeekQueryError(message:"余额查询已停止") }
        defer { session.invalidateAndCancel(); owner.detach(id) }
        session.dataTask(with:request).resume()
        guard done.wait(timeout:.now() + budget) == .success else { throw DeepSeekQueryError(message:"DeepSeek 余额查询超时",retryable:true) }
        if let failure { throw failure }
        return data
    }
}
