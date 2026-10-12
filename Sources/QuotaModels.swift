import Foundation
struct QuotaWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double? { usedPercent.flatMap { $0.isFinite ? min(100, max(0, 100 - $0)) : nil } }
    var minutes: Int? { windowDurationMins }
    var title: String {
        guard let n = minutes else { return "额度窗口" }
        if n % 1440 == 0 { return "\(n / 1440) 天额度" }
        if n % 60 == 0 { return "\(n / 60) 小时额度" }
        return "\(n) 分钟额度"
    }
}
struct Credits: Decodable { let balance: String?; let unlimited: Bool? }
struct QuotaBucket: Decodable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let credits: Credits?
    var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
    var remaining: Double? { windows.compactMap { $0.remaining }.min() }
}
struct QuotaSnapshot: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    var namedBuckets: [(String, QuotaBucket)] {
        if let map = rateLimitsByLimitId, !map.isEmpty { return map.keys.sorted().map { ($0, map[$0]!) } }
        return rateLimits.map { [($0.limitId ?? "codex", $0)] } ?? []
    }
    var buckets: [QuotaBucket] { namedBuckets.map { $0.1 } }
    var selected: (String, QuotaBucket)? { namedBuckets.first { $0.0 == "codex" } ?? namedBuckets.first { $0.1.remaining != nil } ?? namedBuckets.first }
    var remaining: Double? { selected?.1.remaining }
    static func decode(_ data: Data) throws -> QuotaSnapshot { try JSONDecoder().decode(Self.self, from: data) }
}
