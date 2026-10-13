import Foundation
import Darwin

struct PreparedUpdate { let directory: URL; let target: UpdateTarget; let requestURL: URL }
final class UpdateInstaller {
    private let queue = DispatchQueue(label:"local.quotanest.update-install")
    func stage(_ update: VerifiedUpdateDMG, currentVersion: DottedVersion, completion: @escaping (Result<PreparedUpdate,Error>) -> Void) {
        queue.async { completion(Result {
            let directory = update.fileURL.deletingLastPathComponent()
            do {
                guard update.release.version > currentVersion else { throw UpdateError("更新版本不高于当前版本") }
                let target = try UpdateTarget.resolve(runningBundle:Bundle.main.bundleURL)
                let mount = directory.appendingPathComponent("mount",isDirectory:true)
                try FileManager.default.createDirectory(at:mount,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                let runner = UpdateCommandRunner()
                // Detach also runs if hdiutil reports an error after mounting.
                defer { _ = try? runner.run("/usr/bin/hdiutil",arguments:["detach",mount.path],timeout:20) }
                _ = try runner.run("/usr/bin/hdiutil",arguments:["attach","-nobrowse","-readonly","-noautoopen","-mountpoint",mount.path,update.fileURL.path],timeout:45)
                let source = mount.appendingPathComponent("QuotaNest.app")
                try UpdateBundleValidator.validate(at:source,expectedVersion:update.release.version)
                let staged = directory.appendingPathComponent("QuotaNest.app")
                try FileManager.default.copyItem(at:source,to:staged)
                try UpdateBundleValidator.validate(at:staged,expectedVersion:update.release.version)
                guard let resource = Bundle.main.resourceURL?.appendingPathComponent("quotanest-update-helper") else { throw UpdateError("当前应用缺少更新助手") }
                let helper = directory.appendingPathComponent("helper")
                try FileManager.default.copyItem(at:resource,to:helper)
                try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:helper.path)
                let request = UpdateHelperRequest(parentPID:getpid(),userID:getuid(),homePath:FileManager.default.homeDirectoryForCurrentUser.path,stagePath:directory.path,targetPath:target.url.path,version:update.release.version.text,loginEnabled:LoginItemManager.enabled)
                let url = directory.appendingPathComponent("request.json")
                try JSONEncoder().encode(request).write(to:url,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                return PreparedUpdate(directory:directory,target:target,requestURL:url)
            } catch { UpdatePaths.clean(directory); throw error }
        }) }
    }
}
