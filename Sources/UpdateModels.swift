import Foundation

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String, arguments: [String] = []) { self.message = message; self.arguments = arguments }
    var arguments: [String] = []
    var errorDescription: String? { Localization.shared.text(message,arguments) }
}
struct DottedVersion: Comparable {
    let components: [Int]
    let text: String
    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard text.count <= 64, (1...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) && Int($0) != nil }) else { return nil }
        self.text = text; components = parts.map { Int($0)! }
    }
    static func == (a: Self, b: Self) -> Bool { !(a < b) && !(b < a) }
    static func < (a: Self, b: Self) -> Bool {
        for i in 0..<max(a.components.count,b.components.count) {
            let x = i < a.components.count ? a.components[i] : 0, y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}
struct UpdateRelease {
    let version: DottedVersion
    let dmgURL: URL
    let checksumURL: URL
    var filename: String { "QuotaNest-\(version.text)-universal.dmg" }
}
enum UpdateAvailability { case upToDate, available(UpdateRelease) }
enum UpdateMenuState {
    case busy(String), current(String), available(String), failed(Error)
    var title: String {
        switch self {
        case .busy(let text): return L(text)
        case .failed(let error): return error.localizedDescription
        case .current(let version): return L("当前版本 v%@，已是最新",version)
        case .available(let version): return L("发现 v") + version
        }
    }
    var isActionEnabled: Bool { if case .busy = self { return false }; return true }
}
enum ReleaseManifest {
    private struct Asset: Decodable { let name: String; let url: URL; let size: Int64 }
    private struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool; let assets: [Asset] }
    static func isAssetURL(_ url: URL) -> Bool {
        let prefix = "/repos/bloodkilory/QuotaNest/releases/assets/"
        let id = String(url.path.dropFirst(prefix.count))
        return url.scheme == "https" && url.host == "api.github.com" && url.port == nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil && url.path.hasPrefix(prefix) && !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) }
    }
    static func release(from data: Data, currentVersion: DottedVersion) throws -> UpdateAvailability {
        guard data.count <= 131072, let root = try? JSONDecoder().decode(Release.self, from:data), !root.draft, !root.prerelease, root.tag_name.hasPrefix("v"), let version = DottedVersion(String(root.tag_name.dropFirst())) else { throw UpdateError("GitHub 正式版本信息无效") }
        let name = "QuotaNest-\(version.text)-universal.dmg"
        let dmgs = root.assets.filter { $0.name == name }, sums = root.assets.filter { $0.name == "SHA256SUMS.txt" }
        guard dmgs.count == 1, sums.count == 1, isAssetURL(dmgs[0].url), isAssetURL(sums[0].url), (1...67_108_864).contains(dmgs[0].size), (1...131072).contains(sums[0].size) else { throw UpdateError("正式 Release 缺少有效安装包或校验清单") }
        return version > currentVersion ? .available(UpdateRelease(version:version,dmgURL:dmgs[0].url,checksumURL:sums[0].url)) : .upToDate
    }
    static func digest(for filename: String, manifest: Data) throws -> Data {
        guard manifest.count <= 131072, let text = String(data:manifest,encoding:.utf8) else { throw UpdateError("SHA-256 校验清单无效") }
        var digest: Data?
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let fields = line.split(maxSplits:1,whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2 else { throw UpdateError("SHA-256 校验清单格式无效") }
            let name = fields[1].trimmingCharacters(in:.whitespaces).replacingOccurrences(of:"^\\*",with:"",options:.regularExpression)
            guard name == filename else { continue }
            let chars = Array(fields[0].utf8)
            guard digest == nil, chars.count == 64, chars.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw UpdateError("安装包校验行重复或无效") }
            digest = Data(stride(from:0,to:64,by:2).map { UInt8(String(decoding:chars[$0..<$0+2],as:UTF8.self),radix:16)! })
        }
        guard let digest else { throw UpdateError("校验清单未包含此安装包") }; return digest
    }
    static func matches(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x,y) in zip(a,b) { difference |= x ^ y }; return difference == 0
    }
}
