import Foundation
enum QuotaProviderID: String, CaseIterable {
    case codex, claude, antigravity
    var title: String { switch self { case .codex: return "Codex"; case .claude: return "Claude Code"; case .antigravity: return "Antigravity" } }
}
struct ProviderReading {
    var snapshot: QuotaSnapshot?
    var lastSuccess: Date?
    var error: String?
    var refreshing = false
    var successes = 0
    func remaining(for provider: QuotaProviderID) -> Double? {
        if provider == .codex { return snapshot?.remaining }
        if provider == .antigravity {
            // Never substitute another model family's quota when Gemini is unavailable.
            return snapshot?.buckets.filter {
                $0.limitName?.range(of: #"\bgemini\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }.compactMap { $0.remaining }.min()
        }
        return snapshot?.buckets.compactMap { $0.remaining }.min()
    }
}
