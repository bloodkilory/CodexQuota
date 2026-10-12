import Foundation
import Darwin
/// Runs only an explicit executable/argument vector; owns and cleans its process group.
final class BoundedCommand {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func run(_ path: String, arguments: [String], environment: [String: String], timeout: TimeInterval = 35) throws -> Data {
        if isCancelled { throw QuotaError(message: "查询已取消") }
        var pipes: [Int32] = [0, 0]
        guard pipe(&pipes) == 0 else { throw QuotaError(message: "无法创建查询进程管道") }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&actions, pipes[0]); posix_spawn_file_actions_addclose(&actions, pipes[1])
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; env.forEach { free($0) } }
        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { args in env.withUnsafeBufferPointer { vars in posix_spawn(&pid, path, &actions, &attributes, args.baseAddress!, vars.baseAddress!) } }
        close(pipes[1])
        guard result == 0 else { close(pipes[0]); throw QuotaError(message: "无法启动官方 CLI，请确认已安装") }
        var reaped = false
        defer {
            close(pipes[0])
            kill(-pid, SIGTERM)
            // Cleanup is limited to the process group created by this invocation.
            let end = ProcessInfo.processInfo.systemUptime + 0.2
            while !reaped && ProcessInfo.processInfo.systemUptime < end {
                var status: Int32 = 0
                reaped = waitpid(pid, &status, WNOHANG) == pid
                if !reaped { Thread.sleep(forTimeInterval: 0.01) }
            }
            kill(-pid, SIGKILL)
            if !reaped { var status: Int32 = 0; _ = waitpid(pid, &status, 0) }
        }
        _ = fcntl(pipes[0], F_SETFL, O_NONBLOCK)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data(), status: Int32 = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            if isCancelled { throw QuotaError(message: "查询已取消") }
            var fd = pollfd(fd: pipes[0], events: Int16(POLLIN), revents: 0)
            _ = poll(&fd, 1, 100)
            var chunk = [UInt8](repeating: 0, count: 16384)
            var count = Darwin.read(pipes[0], &chunk, chunk.count)
            while count > 0 {
                data.append(contentsOf: chunk.prefix(count))
                if data.count > 1_048_576 { throw QuotaError(message: "额度报告超过大小限制") }
                count = Darwin.read(pipes[0], &chunk, chunk.count)
            }
            if !reaped { reaped = waitpid(pid, &status, WNOHANG) == pid }
            // EAGAIN is not EOF: a child can write its last bytes between read and waitpid.
            if reaped && count == 0 {
                guard status == 0 else { throw QuotaError(message: "官方 CLI 查询失败；请在终端确认登录及网络") }
                return data
            }
        }
        throw QuotaError(message: "额度查询超时；请检查网络及官方 CLI 登录")
    }
}
