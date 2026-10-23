import Foundation
import CoreFoundation
struct ProviderPayloadError: LocalizedError {
    let message: String
    var arguments: [String] = []
    var errorDescription: String? { Localization.shared.text(message,arguments) }
}
enum ProviderPayload {
    static func timestamp(_ value: Any?) -> Double? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)?.timeIntervalSince1970
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderPayloadError(message: "额度响应格式无效") }
        return object
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    static func claude(_ data: Data) throws -> QuotaSnapshot {
        let object = try object(data)
        func window(_ key: String, _ minutes: Int) -> QuotaWindow? {
            guard let row = object[key] as? [String: Any], let used = number(row["utilization"]) else { return nil }
            return QuotaWindow(usedPercent: used, windowDurationMins: minutes, resetsAt: timestamp(row["resets_at"]))
        }
        var buckets: [String: QuotaBucket] = [:]
        let main = QuotaBucket(limitId: "claude", limitName: "Claude 官方套餐", planType: nil, primary: window("five_hour", 300), secondary: window("seven_day", 10080), credits: nil, nameKey:"Claude 官方套餐")
        if main.remaining != nil { buckets["claude"] = main }
        for (key, title) in [("seven_day_sonnet", "Sonnet 周额度"), ("seven_day_opus", "Opus 周额度")] {
            if let value = window(key, 10080) { buckets[key] = QuotaBucket(limitId: key, limitName: title, planType: nil, primary: value, secondary: nil, credits: nil, nameKey:title) }
        }
        guard !buckets.isEmpty else { throw ProviderPayloadError(message: "Claude 未提供可用额度；请确认官方订阅及登录权限") }
        return QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: buckets)
    }
    static func antigravity(_ data: Data) throws -> QuotaSnapshot {
        let object = try object(data)
        guard object["status"] as? String == "SUCCESS", let command = object["command"] as? [String: Any], command["name"] as? String == "usage", let body = command["data"] as? [String: Any], let groups = body["groups"] as? [[String: Any]] else { throw ProviderPayloadError(message: "Antigravity 额度查询失败；请在 agy 中确认登录和网络") }
        var buckets: [String: QuotaBucket] = [:]
        for (index, group) in groups.enumerated() {
            let name = group["name"] as? String ?? "额度组 \(index + 1)"
            var weekly: QuotaWindow?, session: QuotaWindow?
            for row in group["buckets"] as? [[String: Any]] ?? [] {
                guard row["disabled"] as? Bool != true, let fraction = number(row["remaining_fraction"]), (0...1).contains(fraction) else { continue }
                let kind = row["window"] as? String
                guard kind == "weekly" || kind == "5h" else { continue }
                let window = QuotaWindow(usedPercent: 100 - fraction * 100, windowDurationMins: kind == "weekly" ? 10080 : 300, resetsAt: timestamp(row["reset_time"]))
                if kind == "weekly" { weekly = window } else { session = window }
            }
            if weekly != nil || session != nil {
                let key = "group-\(index)"
                buckets[key] = QuotaBucket(limitId: key, limitName: name, planType: nil, primary: weekly, secondary: session, credits: nil, nameKey:group["name"] == nil ? "额度组 %@" : nil, nameArguments:[String(index + 1)])
            }
        }
        guard !buckets.isEmpty else { throw ProviderPayloadError(message: "Antigravity 未返回可用额度窗口") }
        return QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: buckets)
    }
}
