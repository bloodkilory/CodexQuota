import Foundation
import Darwin

enum UpdatePrivilegeLauncher {
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of:"'",with:"'\\''") + "'" }
    static func privilegedCommand(helper: String, request: String, expectedDigest: String) throws -> String {
        guard expectedDigest.count == 64, expectedDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw UpdateError("更新助手校验标识无效") }
        // The directory comes exclusively from root's mktemp, never from a request.
        // The child cannot change its parent's cleanup variable. Only the copied,
        // verified binary is executed with administrator privileges.
        return "set -eu; updateDir=$(/usr/bin/mktemp -d /private/tmp/quotanest-update.XXXXXX); trap '/bin/rm -rf \"$updateDir\"' EXIT; /usr/bin/install -m 700 " + shellQuote(helper) + " \"$updateDir/helper\"; actual=$(/usr/bin/shasum -a 256 \"$updateDir/helper\"); actual=${actual%% *}; [ \"$actual\" = " + shellQuote(expectedDigest) + " ] || exit 65; \"$updateDir/helper\" --request " + shellQuote(request)
    }
    static func launch(_ prepared: PreparedUpdate, completion: @escaping (Result<Void,Error>) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            completion(Result {
                let helper = prepared.directory.appendingPathComponent("helper")
                try UpdatePaths.rejectLinks(helper); try UpdatePaths.rejectLinks(prepared.requestURL)
                let process = Process()
                if prepared.target.isUser {
                    process.executableURL = helper; process.arguments = ["--request",prepared.requestURL.path]
                } else {
                    let command = try privilegedCommand(helper:helper.path,request:prepared.requestURL.path,expectedDigest:prepared.helperDigest)
                    process.executableURL = URL(fileURLWithPath:"/usr/bin/osascript")
                    process.arguments = ["-e", "on run argv\n do shell script (item 1 of argv) with administrator privileges\nend run", command]
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
