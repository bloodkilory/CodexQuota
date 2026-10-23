import Foundation
import Darwin

/// File transaction shared by the standalone helper and temporary-directory tests.
enum UpdateReplacement {
    static func install(staged: URL, target: URL, validate: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        try UpdatePaths.rejectLinks(target.deletingLastPathComponent())
        let workspace = target.deletingLastPathComponent().appendingPathComponent(".QuotaNest-update-" + UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:workspace,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:workspace) }
        let candidate = workspace.appendingPathComponent("QuotaNest.app")
        // Copy first, then validate inside the protected workspace: no root install
        // from a user-writable bundle that could change after verification.
        try fm.copyItem(at:staged,to:candidate)
        try validate(candidate)
        try UpdatePaths.rejectLinks(target)
        let backup = target.deletingLastPathComponent().appendingPathComponent("QuotaNest.app.previous." + ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-") + "." + UUID().uuidString)
        try fm.moveItem(at:target,to:backup)
        do {
            try fm.moveItem(at:candidate,to:target)
            try validate(target)
        } catch {
            // Move the failed candidate out of the destination before restoring.
            if fm.fileExists(atPath:target.path) { try fm.moveItem(at:target,to:workspace.appendingPathComponent("failed.app")) }
            do { try fm.moveItem(at:backup,to:target) }
            catch { throw UpdateError("更新失败且无法恢复原应用；备份仍保留在 Applications 目录") }
            throw UpdateError("更新失败，已恢复原应用")
        }
        return backup
    }
}

enum UpdateHelper {
    static func writeStatus(_ status: UpdateInstallStatus, request: UpdateHelperRequest) throws {
        // A root helper never writes a status path with root privileges.
        let elevated = geteuid() == 0
        let oldGroup = getegid()
        if elevated {
            guard let user = getpwuid(request.userID), setegid(user.pointee.pw_gid) == 0, seteuid(request.userID) == 0 else { throw UpdateError("无法记录更新状态") }
        }
        defer { if elevated { _ = seteuid(0); _ = setegid(oldGroup) } }
        try JSONEncoder().encode(status).write(to:request.statusURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:request.statusURL.path)
    }
    static func run(requestURL: URL) throws {
        let request = try UpdateHelperRequest.load(requestURL)
        let runner = UpdateCommandRunner()
        let version = DottedVersion(request.version)!
        try UpdateBundleValidator.validate(at:request.stagedApp,expectedVersion:version)
        try writeStatus(UpdateInstallStatus(state:"ready",message:""),request:request)
        let deadline = ProcessInfo.processInfo.systemUptime + 45
        while kill(request.parentPID,0) == 0 || errno == EPERM {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw UpdateError("原应用尚未退出，更新已停止") }
            Thread.sleep(forTimeInterval:0.1)
        }
        do {
            try request.validate()
            let target = URL(fileURLWithPath:request.targetPath)
            let plist = try PropertyListSerialization.propertyList(from:Data(contentsOf:target.appendingPathComponent("Contents/Info.plist")),options:[],format:nil) as? [String:Any]
            guard plist?["CFBundleIdentifier"] as? String == "local.codexquota", let old = plist?["CFBundleShortVersionString"] as? String, let oldVersion = DottedVersion(old), version > oldVersion else { throw UpdateError("目标应用版本或身份已经变化，已停止更新") }
            _ = try UpdateReplacement.install(staged:request.stagedApp,target:target) { try UpdateBundleValidator.validate(at:$0,expectedVersion:version) }
            try writeStatus(UpdateInstallStatus(state:"installed",message:"已更新到 v%@",arguments:[version.text]),request:request)
        } catch {
            try? writeStatus(UpdateInstallStatus(state:"failed",message:(error as? UpdateError)?.message ?? "更新安装失败；请重新打开应用并重试",arguments:(error as? UpdateError)?.arguments),request:request)
            try? relaunch(request,runner:runner)
            throw error
        }
        do { try relaunch(request,runner:runner) }
        catch { try? writeStatus(UpdateInstallStatus(state:"failed",message:"应用已更新，请从 Applications 手动打开"),request:request); throw error }
    }
    private static func relaunch(_ request: UpdateHelperRequest, runner: UpdateCommandRunning) throws {
        if geteuid() == 0 {
            _ = try runner.run("/bin/launchctl",arguments:["asuser",String(request.userID),"/usr/bin/sudo","-u","#" + String(request.userID),"/usr/bin/open",request.targetPath],timeout:20)
        } else { _ = try runner.run("/usr/bin/open",arguments:[request.targetPath],timeout:20) }
    }
}
