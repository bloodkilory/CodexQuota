import Foundation
import CoreFoundation

enum KimiPayload {
    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        if let s = value as? String, let n = Double(s), n.isFinite { return n }
        return nil
    }
    private static func timestamp(_ value: Any?) -> Double? {
        guard let value = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let date = f.date(from: value) { return date.timeIntervalSince1970 }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)?.timeIntervalSince1970
    }
    static func decode(_ data: Data) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError(message: "Kimi 额度响应格式无效")
        }
        var buckets: [String: QuotaBucket] = [:]
        func bucket(_ key: String, _ title: String, _ primary: QuotaWindow?, _ secondary: QuotaWindow? = nil) {
            if primary != nil || secondary != nil {
                buckets[key] = QuotaBucket(limitId: key, limitName: title, planType: nil, primary: primary, secondary: secondary, credits: nil, nameKey:title)
            }
        }
        if let usages = root["usages"] as? [String: Any] {
            func window(_ key: String, _ minutes: Int?) -> QuotaWindow? {
                guard let row = usages[key] as? [String: Any] else { return nil }
                let ratio = number(row["used_ratio"]).flatMap { $0 >= 0 && ($0 * 100).isFinite ? $0 : nil }
                return QuotaWindow(usedPercent: ratio.map { $0 * 100 }, windowDurationMins: minutes, resetsAt: timestamp(row["reset_time"]), periodLabel: minutes == nil ? "月度额度" : nil, localizesPeriodLabel:true)
            }
            bucket("kimi", "Kimi Code", window("limit_5h", 300), window("limit_7d", 10080))
            bucket("kimi-month-total", "Kimi 月度总额度", window("limit_month_total", nil))
            bucket("kimi-month-code", "Kimi 月度编程额度", window("limit_month_code", nil))
        } else {
            func legacyWindow(_ row: [String: Any], _ minutes: Int) -> QuotaWindow? {
                guard let limit = number(row["limit"]), limit > 0 else { return nil }
                let used = number(row["used"]) ?? number(row["remaining"]).map { limit - $0 }
                guard let used, used >= 0, (used / limit * 100).isFinite else { return nil }
                let reset = ["reset_at", "resetAt", "reset_time", "resetTime"].compactMap { timestamp(row[$0]) }.first
                return QuotaWindow(usedPercent: used / limit * 100, windowDurationMins: minutes, resetsAt: reset)
            }
            var weekly = (root["usage"] as? [String: Any]).flatMap { legacyWindow($0, 10080) }
            var hourly: QuotaWindow?
            for item in root["limits"] as? [[String: Any]] ?? [] {
                let detail = item["detail"] as? [String: Any] ?? item
                let window = item["window"] as? [String: Any] ?? [:]
                let duration = number(window["duration"] ?? item["duration"] ?? detail["duration"])
                let unit = (window["timeUnit"] ?? item["timeUnit"] ?? detail["timeUnit"]) as? String ?? ""
                let mins = duration.map { $0 * (unit.contains("HOUR") ? 60 : unit.contains("DAY") ? 1440 : unit.contains("MINUTE") ? 1 : 1.0 / 60) }
                if mins == 300 { hourly = legacyWindow(detail, 300) }
                if mins == 10080 { weekly = legacyWindow(detail, 10080) }
            }
            bucket("kimi", "Kimi Code", hourly, weekly)
        }
        guard buckets.values.contains(where:{ $0.remaining != nil }) else { throw QuotaError(message: "Kimi 未返回可识别的额度窗口；实验接入尚未实测") }
        return QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: buckets)
    }
}
