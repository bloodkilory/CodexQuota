import Foundation
import Darwin

enum UpdatePrivilegeLauncher {
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of:"'",with:"'\\''") + "'" }
    static func launch(_ prepared: PreparedUpdate, completion: @escaping (Result<Void,Error>) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            completion(Result {
                let helper = prepared.directory.appendingPathComponent("helper")
                try UpdatePaths.rejectLinks(helper); try UpdatePaths.rejectLinks(prepared.requestURL)
                let process = Process()
                if prepared.target.isUser {
                    process.executableURL = helper; process.arguments = ["--request",prepared.requestURL.path]
                } else {
                    // Source is fixed. All paths travel as argv and AppleScript's
                    // quoted form escapes them before its mandatory shell bridge.
                    process.executableURL = URL(fileURLWithPath:"/usr/bin/osascript")
                    process.arguments = ["-e", "on run argv\n do shell script ((quoted form of item 1 of argv) & \" --request \" & (quoted form of item 2 of argv)) with administrator privileges\nend run", helper.path, prepared.requestURL.path]
                }
                process.environment = ["PATH":"/usr/bin:/bin:/usr/sbin:/sbin"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
                try process.run()
                let deadline = ProcessInfo.processInfo.systemUptime + 180
                while ProcessInfo.processInfo.systemUptime < deadline {
                    if let data = try? Data(contentsOf:prepared.directory.appendingPathComponent("status.json")), data.count <= 16384,
                       let status = try? JSONDecoder().decode(UpdateInstallStatus.self,from:data) {
                        if status.state == "ready" { return }
                        if status.state == "failed" { throw UpdateError(status.message) }
                    }
                    guard process.isRunning else { throw UpdateError("更新未启动；管理员授权可能已取消") }
                    Thread.sleep(forTimeInterval:0.1)
                }
                if process.isRunning { process.terminate() }
                throw UpdateError("等待更新授权超时，原应用仍可使用")
            })
        }
    }
}
