import Foundation

/// Experimental global Qoder npm build integration. The helper invokes only the
/// official bundled credential WASM and a fixed read-only quota endpoint.
final class QoderQuotaClient {
    private let home:URL
    private let runner = BoundedCommand()
    init(home:URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    private func installation() throws -> (URL,URL) {
        let fm = FileManager.default
        var dirs = ["/opt/homebrew/bin","/usr/local/bin",home.appendingPathComponent(".local/bin").path]
        dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator:":").map(String.init).filter { $0.hasPrefix("/") }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(at:nvm,includingPropertiesForKeys:nil) {
            dirs += versions.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(20).map { $0.appendingPathComponent("bin").path }
        }
        let nodes = dirs.map { URL(fileURLWithPath:$0).appendingPathComponent("node") }.filter { fm.isExecutableFile(atPath:$0.path) }
        var bundles = ["/opt/homebrew/lib/node_modules/@qoder-ai/qodercli/bundle/qodercli.js","/usr/local/lib/node_modules/@qoder-ai/qodercli/bundle/qodercli.js"].map { URL(fileURLWithPath:$0) }
        for dir in dirs {
            let command = URL(fileURLWithPath:dir).appendingPathComponent("qoder").resolvingSymlinksInPath()
            let folder = command.deletingLastPathComponent()
            bundles.append(folder.appendingPathComponent("qodercli.js"))
            bundles.append(folder.appendingPathComponent("bundle/qodercli.js"))
            bundles.append(URL(fileURLWithPath:dir).deletingLastPathComponent().appendingPathComponent("lib/node_modules/@qoder-ai/qodercli/bundle/qodercli.js"))
        }
        guard let node = nodes.first, let bundle = bundles.first(where: { fm.fileExists(atPath:$0.path) }) else {
            throw QuotaError(message:"Qoder 实验接入需要官方 npm 版 Qoder CLI 与 Node.js；原生安装暂不支持")
        }
        return (node,bundle)
    }
    func fetch(_ completion:@escaping (Result<QuotaSnapshot,Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async { [self] in
            do {
                let (node,bundle) = try installation()
                guard let helper = Bundle.main.url(forResource:"qoder-usage",withExtension:"cjs") else { throw QuotaError(message:"Qoder 查询组件缺失，请重新安装余度") }
                // A JS timer cannot interrupt synchronous WASM or filesystem calls.
                // The parent owns a monotonic deadline, bounded stdout and process-group cleanup.
                let data = try runner.run("/usr/bin/env", arguments: ["-C", "/private/tmp", node.path, helper.path, bundle.path, home.path], environment: ["HOME":home.path,"PATH":"/usr/bin:/bin","LANG":"en_US.UTF-8"], timeout: 30)
                completion(Result { try QoderPayload.decode(data) })
            } catch let error as QuotaError { completion(.failure(error)) }
            catch { completion(.failure(QuotaError(message:"Qoder 实验额度查询失败"))) }
        }
    }
    func shutdown() { runner.cancel() }
}
