import Foundation
import Darwin
struct QuotaError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
final class CodexClient {
    private let queue = DispatchQueue(label: "local.codexquota.rpc")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence = 0
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
            do {
                let deadline = Date().addingTimeInterval(self.timeout)
                if self.process?.isRunning != true {
                    self.close()
                    let p = Process(), stdin = Pipe(), stdout = Pipe()
                    p.executableURL = URL(fileURLWithPath: self.executable)
                    p.arguments = ["app-server"]
                    p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
                    // LaunchAgent environments have a minimal PATH; include common runtime locations.
                    var env = ProcessInfo.processInfo.environment
                    env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
                    p.environment = env
                    try p.run()
                    self.process = p; self.input = stdin.fileHandleForWriting; self.output = stdout.fileHandleForReading
                    _ = try self.request("initialize", params: ["clientInfo": ["name": "codex_quota", "title": "QuotaNest", "version": "1.5.0"]], deadline: deadline)
                    try self.send(["method": "initialized"])
                }
                let value = try self.request("account/rateLimits/read", params: nil, deadline: deadline)
                let data = try JSONSerialization.data(withJSONObject: value)
                completion(.success(try QuotaSnapshot.decode(data)))
            } catch {
                self.close()
                completion(.failure(error))
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
            let end = Date().addingTimeInterval(0.5)
            while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.01) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
    }
    private func send(_ value: [String: Any]) throws {
        guard let input else { throw QuotaError(message: "Codex 连接未就绪") }
        var bytes = try JSONSerialization.data(withJSONObject: value); bytes.append(10)
        try input.write(contentsOf: bytes)
    }
    private func request(_ method: String, params: [String: Any]?, deadline: Date) throws -> Any {
        sequence += 1; let id = sequence
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try send(request)
        while Date() < deadline {
            if isCancelled { throw QuotaError(message: "查询已取消") }
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: 0..<newline); buffer.removeSubrange(0...newline)
                guard let msg = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let serverID = msg["id"], msg["method"] != nil {
                    try send(["id": serverID, "error": ["code": -32601, "message": "Unsupported client method"]]); continue
                }
                guard (msg["id"] as? Int) == id else { continue }
                if let error = msg["error"] as? [String: Any] {
                    let code = error["code"] as? Int ?? 0
                    throw QuotaError(message: "额度查询失败（\(code)）；请确认 Codex 已登录且网络可用")
                }
                guard let result = msg["result"] else { throw QuotaError(message: "Codex 返回了无效响应") }
                return result
            }
            guard let output else { throw QuotaError(message: "Codex 连接已断开") }
            var fd = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&fd, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; throw QuotaError(message: "Codex 连接读取失败") }
            if ready > 0 {
                var chunk = [UInt8](repeating: 0, count: 65536)
                let count = Darwin.read(output.fileDescriptor, &chunk, chunk.count)
                guard count > 0 else { throw QuotaError(message: "Codex 已退出；下次刷新将重新连接") }
                buffer.append(contentsOf: chunk.prefix(count))
                guard buffer.count < 4_000_000 else { throw QuotaError(message: "Codex 响应超过大小限制") }
            }
        }
        throw QuotaError(message: "查询超过 \(Int(timeout)) 秒；请检查网络或 Codex 登录状态")
    }
}
