import Foundation
import Darwin
struct QuotaError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
private struct CodexRequestFailure: LocalizedError {
    let message: String
    var retryable = false
    var rpcCode: Int? = nil
    var errorDescription: String? { message }
    static func rpc(_ error: [String: Any]) -> Self {
        let code = error["code"] as? Int ?? 0
        let reason = (error["message"] as? String ?? "").lowercased()
        // Classify in memory; never expose response bodies, account IDs or tokens.
        if reason.range(of: #"\b401\b|unauthorized|not logged in|authentication required|token.{0,40}expired"#, options:.regularExpression) != nil {
            return Self(message:"Codex 官方登录已失效；请在官方客户端重新登录",rpcCode:code)
        }
        if reason.range(of:#"\b403\b|forbidden"#,options:.regularExpression) != nil {
            return Self(message:"Codex 账号无法读取套餐额度；请检查官方客户端的订阅权限",rpcCode:code)
        }
        if reason.range(of:#"\b429\b|too many requests"#,options:.regularExpression) != nil {
            return Self(message:"Codex 查询过于频繁；等待下次自动刷新",rpcCode:code)
        }
        return Self(message:code == -32603 ? "Codex 套餐服务暂时不可用（-32603）；稍后自动重试" : "Codex 额度查询失败（\(code)）",retryable:code == -32603,rpcCode:code)
    }
}
final class CodexClient {
    private let queue = DispatchQueue(label: "local.codexquota.rpc")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var backgroundUsageParams = true
    private let cancellationLock = NSLock()
    private var cancelled = false
    private var isCancelled: Bool { cancellationLock.lock(); defer { cancellationLock.unlock() }; return cancelled }
    private let executable: String
    private let timeout: TimeInterval
    init(executable: String? = nil, timeout: TimeInterval = 30) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.executable = executable ?? [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? home + "/.local/bin/codex"
        self.timeout = timeout
    }
    func fetch(_ completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async {
            // Two attempts share one monotonic budget; a retry cannot overlap the
            // next 60-second poll or turn a cancelled fetch into a new process.
            let deadline = ProcessInfo.processInfo.systemUptime + self.timeout
            for attempt in 0..<2 {
                do {
                if self.isCancelled { throw QuotaError(message:"查询已取消") }
                let attemptDeadline = min(deadline,ProcessInfo.processInfo.systemUptime + self.timeout / 2)
                if self.process?.isRunning != true {
                    self.close()
                    let p = Process(), stdin = Pipe(), stdout = Pipe()
                    p.executableURL = URL(fileURLWithPath: self.executable)
                    p.arguments = ["app-server"]
                    p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
                    // LaunchAgent environments have a minimal PATH; include common runtime locations.
                    var env = ProcessInfo.processInfo.environment
                    env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
                    // A TUN route need not behave like its HTTP proxy. Allow a
                    // per-app route without changing system/Clash settings, while
                    // preserving an explicitly supplied proxy environment.
                    if env["HTTPS_PROXY"] == nil, env["https_proxy"] == nil,
                       let proxy = UserDefaults.standard.string(forKey:"codexHTTPSProxy"), !proxy.isEmpty {
                        env["HTTPS_PROXY"] = proxy
                    }
                    p.environment = env
                    try p.run()
                    self.process = p; self.input = stdin.fileHandleForWriting; self.output = stdout.fileHandleForReading
                    self.backgroundUsageParams = true
                    _ = try self.request("initialize", params: ["clientInfo": ["name": "codex_quota", "title": "QuotaNest", "version": "1.5.0"]], deadline: attemptDeadline)
                    try self.send(["method": "initialized"])
                }
                let value: Any
                do {
                    value = try self.request("account/rateLimits/read", params: self.backgroundUsageParams ? ["excludeResetCreditDetails":true] : nil, deadline: attemptDeadline)
                } catch let failure as CodexRequestFailure where self.backgroundUsageParams && [-32600,-32602].contains(failure.rpcCode ?? 0) {
                    // Older official CLIs accept only null params. Remember the
                    // fallback for this connection instead of probing every minute.
                    self.backgroundUsageParams = false
                    value = try self.request("account/rateLimits/read", params:nil, deadline:attemptDeadline)
                }
                let data = try JSONSerialization.data(withJSONObject: value)
                completion(.success(try QuotaSnapshot.decode(data)))
                return
                } catch {
                self.close()
                let failure = error as NSError
                let transient = (error as? CodexRequestFailure)?.retryable == true || (failure.domain == NSPOSIXErrorDomain && [EPIPE,ECONNRESET].contains(Int32(failure.code)))
                guard attempt == 0, transient, !self.isCancelled, ProcessInfo.processInfo.systemUptime + 1 < deadline else { completion(.failure(error)); return }
                let retryAt = ProcessInfo.processInfo.systemUptime + 1
                while !self.isCancelled && ProcessInfo.processInfo.systemUptime < retryAt { Thread.sleep(forTimeInterval:0.05) }
                }
            }
        }
    }
    func stop() { queue.async { self.close() } }
    func shutdown() {
        cancellationLock.lock(); cancelled = true; cancellationLock.unlock()
        queue.sync { self.close() }
    }
    private func close() {
        try? input?.close(); try? output?.close()
        input = nil; output = nil; buffer.removeAll()
        if let p = process, p.isRunning {
            p.terminate()
            let end = ProcessInfo.processInfo.systemUptime + 0.5
            while p.isRunning && ProcessInfo.processInfo.systemUptime < end { Thread.sleep(forTimeInterval: 0.01) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
    }
    private func send(_ value: [String: Any]) throws {
        guard let input else { throw QuotaError(message: "Codex 连接未就绪") }
        var bytes = try JSONSerialization.data(withJSONObject: value); bytes.append(10)
        try input.write(contentsOf: bytes)
    }
    private func request(_ method: String, params: [String: Any]?, deadline: TimeInterval) throws -> Any {
        sequence += 1; let id = sequence
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try send(request)
        while ProcessInfo.processInfo.systemUptime < deadline {
            if isCancelled { throw QuotaError(message: "查询已取消") }
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: 0..<newline); buffer.removeSubrange(0...newline)
                guard let msg = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let serverID = msg["id"], msg["method"] != nil {
                    try send(["id": serverID, "error": ["code": -32601, "message": "Unsupported client method"]]); continue
                }
                guard (msg["id"] as? Int) == id else { continue }
                if let error = msg["error"] as? [String: Any] {
                    throw CodexRequestFailure.rpc(error)
                }
                guard let result = msg["result"] else { throw QuotaError(message: "Codex 返回了无效响应") }
                return result
            }
            guard let output else { throw CodexRequestFailure(message:"Codex 连接已断开",retryable:true) }
            var fd = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&fd, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; throw CodexRequestFailure(message:"Codex 连接读取失败",retryable:true) }
            if ready > 0 {
                var chunk = [UInt8](repeating: 0, count: 65536)
                let count = Darwin.read(output.fileDescriptor, &chunk, chunk.count)
                guard count > 0 else { throw CodexRequestFailure(message:"Codex 已退出；下次刷新将重新连接",retryable:true) }
                buffer.append(contentsOf: chunk.prefix(count))
                guard buffer.count < 4_000_000 else { throw QuotaError(message: "Codex 响应超过大小限制") }
            }
        }
        throw CodexRequestFailure(message:"查询超过 \(Int(timeout)) 秒；请检查网络或 Codex 登录状态",retryable:true)
    }
}
