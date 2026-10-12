import Foundation
final class LoginItemManager {
    static let label = "local.codexquota"
    static var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: url.path) }
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard let executable = Bundle.main.executablePath else { throw QuotaError(message: "无法找到应用路径") }
            let plist: [String: Any] = ["Label": label, "ProgramArguments": [executable], "RunAtLoad": true, "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url, options: .atomic)
            // The plist is read on next login. Do not bootstrap a duplicate running instance.
        } else if self.enabled {
            try FileManager.default.removeItem(at: url)
            // Loaded job has no KeepAlive, so it will not restart; absent plist prevents next-login launch.
        }
    }
}
