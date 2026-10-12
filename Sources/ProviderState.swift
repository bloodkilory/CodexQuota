import Foundation
enum QuotaProviderID: String, CaseIterable {
    case codex, claude, antigravity
    var title: String { switch self { case .codex: return "Codex"; case .claude: return "Claude Code"; case .antigravity: return "Antigravity" } }
    var shortTitle: String { switch self { case .codex: return "CX"; case .claude: return "CL"; case .antigravity: return "AG" } }
}
struct ProviderReading {
    var snapshot: QuotaSnapshot?
    var lastSuccess: Date?
    var error: String?
    var refreshing = false
    var successes = 0
    func remaining(for provider: QuotaProviderID) -> Double? {
        if provider == .codex { return snapshot?.remaining }
        return snapshot?.buckets.compactMap { $0.remaining }.min()
    }
}
