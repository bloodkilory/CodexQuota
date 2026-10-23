import Foundation
import CoreFoundation

enum QoderPayload {
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func decode(_ data: Data) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw QuotaError(message:"Qoder 额度响应无效") }
        if let reason = root["quotanest_error"] as? String {
            let message: String
            switch reason {
            case "version": message = "Qoder CLI 版本暂不兼容；实验接入已验证 npm 1.1.68 解码格式"
            case "expired": message = "Qoder 登录已过期，请在官方 CLI 重新登录后刷新"
            case "network": message = "Qoder 额度接口查询失败，请稍后刷新"
            case "size": message = "Qoder 登录或额度数据超出大小限制"
            default: message = "请先在官方 Qoder CLI 通过浏览器登录；实验接入不读取 API Key 或 PAT"
            }
            throw QuotaError(message: message)
        }
        var buckets:[String:QuotaBucket] = [:]
        func add(_ id:String, _ name:String, _ row:Any?, _ label:String, organization:Bool = false) {
            guard let row = row as? [String:Any] else { return }
            if organization, row["available"] as? Bool == false { return }
            var percent: Double?
            if let total = number(organization ? row["cap"] ?? row["total"] : row["total"]), total > 0,
               let used = number(row["used"]), used >= 0, (used / total * 100).isFinite { percent = used / total * 100 }
            let window = QuotaWindow(usedPercent:percent,windowDurationMins:nil,resetsAt:nil,periodLabel:label, localizesPeriodLabel:true)
            buckets[id] = QuotaBucket(limitId:id,limitName:name,planType:nil,primary:window,secondary:nil,credits:nil, nameKey:name)
        }
        add("qoder","Qoder 套餐",root["user_quota"] ?? root["userQuota"],"订阅周期额度")
        add("qoder-addon","Qoder 加量包",root["add_on_quota"] ?? root["addOnQuota"],"加量包额度")
        add("qoder-org","Qoder 组织资源包",root["org_resource_package"] ?? root["orgResourcePackage"] ?? root["shared_quota"] ?? root["sharedQuota"],"组织资源包额度",organization:true)
        guard buckets.values.contains(where:{ $0.remaining != nil }) else { throw QuotaError(message:"Qoder 未返回可识别额度；实验接入尚未实测") }
        return QuotaSnapshot(rateLimits:nil,rateLimitsByLimitId:buckets)
    }
}
