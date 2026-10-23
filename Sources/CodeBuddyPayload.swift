import Foundation
import CoreFoundation

enum CodeBuddyPayload {
    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        if let text = value as? String, !text.isEmpty, let n = Double(text), n.isFinite { return n }
        return nil
    }
    static func decode(_ data: Data) throws -> QuotaSnapshot {
        let invalid = QuotaError(message: "CodeBuddy 额度响应不完整或格式已变更；请在官方客户端核对（实验接入）")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["code"] == nil || number(root["code"]) == 0,
              let body = root["data"] as? [String: Any], let response = body["Response"] as? [String: Any],
              response["Error"] == nil, let content = response["Data"] as? [String: Any],
              let accounts = content["Accounts"] as? [[String: Any]] else { throw invalid }
        if let countValue = content["TotalCount"] {
            guard let count = number(countValue), count == Double(accounts.count) else { throw invalid }
        } else if accounts.count >= 200 { throw invalid }
        var remain = 0.0, total = 0.0, count = 0
        for account in accounts {
            guard let status = number(account["Status"]) else { throw invalid }
            guard status == 0 || status == 3 else { continue }
            let left: Double?, size: Double?
            if number(account["CapacityType"]) == 4 {
                // The official UI uses the first requested day's slice, never lifetime credits.
                guard let slices = account["SlicePeriodUsageDetails"] as? [[String: Any]], slices.count == 1, let slice = slices.first else { throw invalid }
                left = number(slice["SlicePeriodCapacityRemainPrecise"])
                size = number(slice["SlicePeriodCapacitySizePrecise"])
            } else if account["CycleCapacityRemainPrecise"] != nil || account["CycleCapacitySizePrecise"] != nil {
                left = number(account["CycleCapacityRemainPrecise"])
                size = number(account["CycleCapacitySizePrecise"])
            } else {
                // Only non-cyclic resource packages can fall back to their lifetime total.
                guard number(account["CapacityType"]) == 1 else { throw invalid }
                left = number(account["CapacityRemainPrecise"])
                size = number(account["CapacitySizePrecise"])
            }
            guard let left, let size, size >= 0, left >= 0, left <= size else { throw invalid }
            remain += left; total += size; count += 1
            guard remain.isFinite, total.isFinite else { throw invalid }
        }
        guard count > 0, total > 0 else { throw QuotaError(message: "CodeBuddy 未返回可用的当前积分额度；请在官方客户端核对") }
        let window = QuotaWindow(usedPercent: (total - remain) / total * 100, windowDurationMins: nil, resetsAt: nil, periodLabel: "当前积分", localizesPeriodLabel:true)
        let bucket = QuotaBucket(limitId: "codebuddy", limitName: "CodeBuddy 当前积分", planType: nil, primary: window, secondary: nil, credits: Credits(balance: String(format: "%.2f", remain), unlimited: false), nameKey:"CodeBuddy 当前积分")
        return QuotaSnapshot(rateLimits: bucket, rateLimitsByLimitId: nil)
    }
}
