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

enum QuotaPeriod: String, CaseIterable {
    case short, weekly
    func includes(_ window: QuotaWindow) -> Bool {
        guard let minutes = window.minutes else { return false }
        return self == .weekly ? minutes == 10080 : minutes > 0 && minutes < 1440
    }
}
extension ProviderReading {
    func windows(for provider: QuotaProviderID) -> [QuotaWindow] {
        let buckets: [QuotaBucket]
        switch provider {
        case .codex: buckets = snapshot?.selected.map { [$0.1] } ?? []
        case .claude: buckets = snapshot?.buckets ?? []
        case .antigravity:
            buckets = snapshot?.buckets.filter {
                $0.limitName?.range(of: #"\bgemini\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            } ?? []
        }
        return buckets.flatMap { $0.windows }.filter { $0.remaining != nil }
    }
    func periods(for provider: QuotaProviderID) -> [QuotaPeriod] {
        QuotaPeriod.allCases.filter { period in windows(for: provider).contains(where: period.includes) }
    }
    func period(for provider: QuotaProviderID, preferred: QuotaPeriod) -> QuotaPeriod? {
        let available = periods(for: provider)
        return available.contains(preferred) ? preferred : available.first
    }
    func window(for provider: QuotaProviderID, period: QuotaPeriod?) -> QuotaWindow? {
        guard let period else { return nil }
        return windows(for: provider).filter(period.includes).min { ($0.remaining ?? 100) < ($1.remaining ?? 100) }
    }
    func periodLabel(for provider: QuotaProviderID, period: QuotaPeriod?) -> String {
        guard let period, let minutes = window(for: provider, period: period)?.minutes else { return "—" }
        if period == .weekly { return "1w" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
    }
}
