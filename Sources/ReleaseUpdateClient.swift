import Foundation
import CryptoKit

enum UpdateRedirectPolicy {
    static func allows(_ url: URL, asset: Bool, count: Int) -> Bool {
        asset && count == 0 && url.scheme == "https" && ["release-assets.githubusercontent.com","objects.githubusercontent.com"].contains(url.host ?? "") && url.port == nil && url.user == nil && url.password == nil && url.fragment == nil
    }
}
private final class UpdateTransferDelegate: NSObject, URLSessionDataDelegate {
    let asset: Bool, limit: Int
    var redirects = 0
    var data = Data()
    var failure: Error?
    let done = DispatchSemaphore(value:0)
    init(asset: Bool, limit: Int) { self.asset = asset; self.limit = limit }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, UpdateRedirectPolicy.allows(url,asset:asset,count:redirects) else {
            failure = UpdateError("更新请求被重定向到不受支持的地址"); completionHandler(nil); return
        }
        redirects += 1
        var next = URLRequest(url:url); next.setValue("application/octet-stream",forHTTPHeaderField:"Accept")
        completionHandler(next)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { failure = UpdateError(status == 403 || status == 429 ? "GitHub 请求受限，请稍后重试" : "GitHub 更新请求失败（%@）",arguments:[String(status)]) }
        else if response.expectedContentLength > Int64(limit) { failure = UpdateError("更新下载超过大小限制") }
        completionHandler(failure == nil ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= limit - data.count else { failure = UpdateError("更新下载超过大小限制"); dataTask.cancel(); return }
        data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil, error != nil { failure = UpdateError("更新下载中断，请检查网络后重试") }; done.signal()
    }
}
final class UpdateTransfer {
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession?
    private var cancelled = false
    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 180
    }
    func fetch(_ url: URL, asset: Bool, limit: Int) throws -> Data {
        guard asset ? ReleaseManifest.isAssetURL(url) : url == ReleaseUpdateClient.releaseURL else { throw UpdateError("更新来源无效") }
        let delegate = UpdateTransferDelegate(asset:asset,limit:limit)
        let current = URLSession(configuration:configuration,delegate:delegate,delegateQueue:nil)
        lock.lock()
        if cancelled { lock.unlock(); current.invalidateAndCancel(); throw UpdateError("更新已取消") }
        session = current; lock.unlock()
        defer { current.invalidateAndCancel(); lock.lock(); session = nil; lock.unlock() }
        var request = URLRequest(url:url)
        request.setValue(asset ? "application/octet-stream" : "application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("2022-11-28",forHTTPHeaderField:"X-GitHub-Api-Version")
        request.setValue("QuotaNest-Updater",forHTTPHeaderField:"User-Agent")
        current.dataTask(with:request).resume()
        guard delegate.done.wait(timeout:.now()+185) == .success else { throw UpdateError("更新下载超时") }
        if let failure = delegate.failure { throw failure }; return delegate.data
    }
    func cancel() { lock.lock(); cancelled = true; let current = session; lock.unlock(); current?.invalidateAndCancel() }
}
struct VerifiedUpdateDMG { let fileURL: URL; let release: UpdateRelease }
final class ReleaseUpdateClient {
    static let releaseURL = URL(string:"https://api.github.com/repos/bloodkilory/QuotaNest/releases/latest")!
    private let queue = DispatchQueue(label:"local.quotanest.updates")
    private let transfer: UpdateTransfer
    init(transfer: UpdateTransfer = UpdateTransfer()) { self.transfer = transfer }
    func check(currentVersion: DottedVersion, completion: @escaping (Result<UpdateAvailability,Error>) -> Void) {
        queue.async { completion(Result { try ReleaseManifest.release(from:self.transfer.fetch(Self.releaseURL,asset:false,limit:131072),currentVersion:currentVersion) }) }
    }
    func download(_ release: UpdateRelease, completion: @escaping (Result<VerifiedUpdateDMG,Error>) -> Void) {
        queue.async {
            completion(Result {
                let manifest = try self.transfer.fetch(release.checksumURL,asset:true,limit:131072)
                let expected = try ReleaseManifest.digest(for:release.filename,manifest:manifest)
                let data = try self.transfer.fetch(release.dmgURL,asset:true,limit:67_108_864)
                guard ReleaseManifest.matches(Data(SHA256.hash(data:data)),expected) else { throw UpdateError("安装包 SHA-256 校验失败，已拒绝安装") }
                let directory = try UpdatePaths.createStage()
                let file = directory.appendingPathComponent(release.filename)
                do { try data.write(to:file,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path) }
                catch { try? FileManager.default.removeItem(at:directory); throw UpdateError("无法保存更新安装包") }
                return VerifiedUpdateDMG(fileURL:file,release:release)
            })
        }
    }
    func cancel() { transfer.cancel() }
}
