import Foundation
import CoreFoundation
import CryptoKit

enum ChinaLoginPayload {
    static func failure(_ message: String, arguments: [String] = []) -> ProviderPayloadError { ProviderPayloadError(message: message,arguments:arguments) }
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_048_576, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("官方额度响应格式无效") }
        return root
    }
    static func header(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 32768, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
    static func matrixObject(_ data: Data) throws -> [String: Any] {
        let root = try object(data)
        for (container, field) in [("statusInfo", "code"), ("base_resp", "status_code")] {
            if let status = root[container] as? [String: Any], let code = number(status[field]), code != 0 {
                throw failure("MiniMax 官方登录或套餐接口拒绝查询；请在客户端检查")
            }
        }
        return root
    }
    static func minimaxGroup(_ body: [String: Any]) -> String? {
        header(body["op_group_id"]) ?? (body["data"] as? [String: Any]).flatMap { header($0["op_group_id"]) }
    }
    static func minimaxPersonalWorkspace(_ body: [String: Any]) throws -> [String: Any] {
        let nested = body["data"] as? [String: Any]
        let rows = body["workspaces"] as? [[String: Any]] ?? nested?["workspaces"] as? [[String: Any]] ?? []
        guard let personal = rows.first(where: { number($0["workspace_type"]) == 0 }) else { throw failure("MiniMax 未提供个人 Token Plan 账户；请在官方客户端检查套餐") }
        return personal
    }
    static func zcodePersonalProject(_ metadata: [String: Any]) throws -> (orgID: String, projectID: String) {
        let organizations = (metadata["organizations"] as? [[String: Any]] ?? []).compactMap { org -> [String: Any]? in
            guard header(org["organizationId"]) != nil else { return nil }
            var result = org
            let projects = (org["projects"] as? [[String: Any]] ?? []).filter {
                String(describing: $0["projectType"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != "2" && header($0["projectId"]) != nil
            }
            guard !projects.isEmpty else { return nil }; result["projects"] = projects; return result
        }
        guard let org = organizations.first(where: { ($0["organizationName"] as? String)?.contains("默认机构") == true }) ?? organizations.first,
              let projects = org["projects"] as? [[String: Any]],
              let project = projects.first(where: { ($0["projectName"] as? String)?.contains("默认项目") == true }) ?? projects.first,
              let orgID = header(org["organizationId"]), let projectID = header(project["projectId"]) else { throw failure("ZCode 没有可用的个人套餐项目；请先在官方客户端连接套餐") }
        return (orgID, projectID)
    }
    static func credential(_ data: Data, dataDirectory: URL, now: Double = Date().timeIntervalSince1970) throws -> String {
        let root = try object(data)
        let authHome = dataDirectory.appendingPathComponent("auth").standardizedFileURL.path
        let hash = Data(SHA256.hash(data: Data((authHome + "\0mcode-public").utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let key = "com.minimax.mcode.oauth.prod.cn\0" + hash
        guard number(root["schemaVersion"]) == 1, let records = root["records"] as? [String: Any], let record = records[key] as? [String: Any], number(record["schemaVersion"]) == 1, record["clientId"] as? String == "mcode-public", record["tokenType"] as? String == "Bearer", record["audience"] as? String == "agent-backend", let scopes = record["scopes"] as? [String], scopes.contains("agent.default"), let token = header(record["accessToken"]), let expiry = number(record["expiresAtMs"]) else { throw failure("未找到 MiniMax Code 国内官方 OAuth 登录；请运行 mcode login") }
        guard expiry / 1000 > now else { throw failure("MiniMax Code 登录已过期；请打开官方客户端更新登录") }
        return token
    }
    static func minimax(_ data: Data) throws -> QuotaSnapshot {
        let root = try object(data)
        if let base = root["base_resp"] as? [String: Any], let status = number(base["status_code"]), status != 0 { throw failure("MiniMax 额度查询失败；请在官方客户端检查登录与套餐") }
        guard let rows = root["model_remains"] as? [[String: Any]], let first = rows.first else { throw failure("MiniMax 未返回可用额度") }
        func window(_ prefix: String, minutes: Int, resetKey: String) -> QuotaWindow? {
            // status=3 means unlimited, not a zero-consumption finite allowance.
            guard number(first[prefix + "_status"]) != 3 else { return nil }
            let total = number(first[prefix + "_total_count"])
            let legacyRemaining = number(first[prefix + "_usage_count"])
            let percent = number(first[prefix + "_remaining_percent"]) ?? ((total ?? 0) > 0 ? legacyRemaining.map { $0 / total! * 100 } : nil)
            guard let percent, (0...100).contains(percent) else { return nil }
            let reset = number(first[resetKey]).flatMap { $0 > 0 ? $0 / 1000 : nil }
            return QuotaWindow(usedPercent: 100 - percent, windowDurationMins: minutes, resetsAt: reset)
        }
        let five = window("current_interval", minutes: 300, resetKey: "end_time")
        let weekly = window("current_weekly", minutes: 10080, resetKey: "weekly_end_time")
        guard five != nil || weekly != nil else { throw failure("MiniMax 未提供有限额度百分比；请在官方客户端查看") }
        return QuotaSnapshot(rateLimits: QuotaBucket(limitId: "minimax", limitName: "MiniMax Token Plan", planType: nil, primary: five, secondary: weekly, credits: nil), rateLimitsByLimitId: nil)
    }
}

extension ChinaLoginPayload {
    static func zcode(_ data: Data) throws -> QuotaSnapshot {
        let payload = try zcodeEnvelope(data) as? [String: Any] ?? [:]
        if payload["balances"] != nil || payload["plans"] != nil { return try zcodeStartPlan(payload) }
        guard let limits = payload["limits"] as? [[String: Any]] else { throw failure("ZCode 未提供套餐额度") }
        var five: QuotaWindow?, weekly: QuotaWindow?, monthly: QuotaWindow?
        for row in limits {
            guard let type = row["type"] as? String, let percent = number(row["percentage"]), (0...100).contains(percent) else { continue }
            let unit = number(row["unit"]), count = number(row["number"])
            let reset = number(row["nextResetTime"]).flatMap { $0 > 0 ? $0 / 1000 : nil }
            if ["TOKENS_LIMIT", "CREDIT_LIMIT"].contains(type) {
                if unit == 3 && count == 5 { five = QuotaWindow(usedPercent: percent, windowDurationMins: 300, resetsAt: reset) }
                if unit == 6 { weekly = QuotaWindow(usedPercent: percent, windowDurationMins: 10080, resetsAt: reset) }
            } else if type == "TIME_LIMIT", unit == 5, count == 1 {
                monthly = QuotaWindow(usedPercent: percent, windowDurationMins: nil, resetsAt: reset, periodLabel: "月工具额度", localizesPeriodLabel:true)
            }
        }
        var buckets: [String: QuotaBucket] = [:]
        if five != nil || weekly != nil { buckets["zcode"] = QuotaBucket(limitId: "zcode", limitName: "GLM Coding Plan", planType: header(payload["level"]), primary: five, secondary: weekly, credits: nil) }
        if let monthly { buckets["zcode-tools"] = QuotaBucket(limitId: "zcode-tools", limitName: "GLM 工具调用", planType: nil, primary: monthly, secondary: nil, credits: nil, nameKey:"GLM 工具调用") }
        guard !buckets.isEmpty else { throw failure("ZCode 未返回支持的额度窗口；请在官方客户端查看") }
        return QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: buckets)
    }
    private static func zcodeStartPlan(_ payload: [String:Any]) throws -> QuotaSnapshot {
        let now = number(payload["server_time"]) ?? Date().timeIntervalSince1970
        let plans = (payload["plans"] as? [[String:Any]] ?? []).filter {
            ($0["status"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == "active"
                && (number($0["starts_at"]) ?? 0) <= now
                && (number($0["ends_at"]).map { $0 <= 0 || $0 > now } ?? true)
        }
        var buckets: [String:QuotaBucket] = [:]
        for (index,row) in (payload["balances"] as? [[String:Any]] ?? []).enumerated() {
            guard let userPlan = header(row["user_plan_id"]), let planID = header(row["plan_id"]),
                  let plan = plans.first(where:{ header($0["user_plan_id"]) == userPlan && header($0["plan_id"]) == planID }),
                  let entitlementID = header(row["entitlement_id"]),
                  let entitlement = (plan["entitlements"] as? [[String:Any]] ?? []).first(where:{ header($0["entitlement_id"]) == entitlementID }),
                  let period = entitlement["period"] as? String, ["daily","one_time"].contains(period),
                  (number(entitlement["effective_at"]) ?? 0) <= now,
                  (number(row["period_start"]) ?? 0) <= now,
                  (number(row["expires_at"]).map { $0 <= 0 || $0 > now } ?? true),
                  (number(row["period_end"]).map { $0 <= 0 || $0 > now } ?? true),
                  let name = header(row["show_name"]) else { continue }
            func units(_ value: Any?) -> Double? {
                let value = number(value) ?? (value as? String).flatMap(Double.init)
                return value.flatMap { $0.isFinite ? $0 : nil }
            }
            let total = units(row["total_units"]), remaining = units(row["remaining_units"])
            let used: Double?
            if let total, total > 0, let remaining, remaining >= 0 && remaining <= total { used = 100 - remaining / total * 100 }
            else { used = nil }
            let expiry = number(row["expires_at"]).flatMap { $0 > 0 ? $0 : nil }
            let window: QuotaWindow
            if period == "daily" {
                window = QuotaWindow(usedPercent:used,windowDurationMins:1440,resetsAt:number(row["period_end"]) ?? expiry)
            } else {
                window = QuotaWindow(usedPercent:used,windowDurationMins:nil,resetsAt:nil,periodLabel:"一次性额度",localizesPeriodLabel:true,expiresAt:expiry ?? number(plan["ends_at"]).flatMap { $0 > 0 ? $0 : nil })
            }
            // Identifiers are only used to join the response; never persist user/plan/bucket IDs.
            let id = "zcode-start-" + String(index)
            let planName = header(plan["name"]) ?? "Start Plan"
            buckets[id] = QuotaBucket(limitId:id,limitName:planName + " · " + name,planType:planName,primary:window,secondary:nil,credits:nil)
        }
        guard !buckets.isEmpty else { throw failure("ZCode Start Plan 暂无生效额度；请在官方客户端查看") }
        return QuotaSnapshot(rateLimits:nil,rateLimitsByLimitId:buckets)
    }
    static func zcodeProjectToken(_ data: Data, now: Double = Date().timeIntervalSince1970) throws -> String {
        let issued = try zcodeEnvelope(data) as? [String: Any] ?? [:]
        guard issued["enable"] as? Bool != false, issued["tokenType"] as? String == "Bearer", let token = header(issued["accessToken"]), let expiry = number(issued["expiresAt"]), expiry > now, (number(issued["expiresIn"]) ?? 0) > 0 else { throw failure("ZCode 套餐会话不可用；请更新官方客户端登录") }
        return token
    }
    static func zcodeEnvelope(_ data: Data) throws -> Any {
        let root = try object(data)
        let validCode = number(root["code"]) == 0 || number(root["code"]) == 200 || root["code"] as? String == "0" || root["code"] as? String == "200"
        guard validCode, root["success"] as? Bool != false, let result = root["data"] else { throw failure("ZCode 登录或套餐接口拒绝查询；请在官方客户端检查") }
        return result
    }
    static func decryptZCode(_ value: String, home: String, username: String, secret: String?) throws -> String {
        guard value.hasPrefix("enc:v1:") else { return value }
        func decode(_ value: Substring) -> Data? {
            let raw = String(value).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            return Data(base64Encoded: raw + String(repeating: "=", count: (4 - raw.count % 4) % 4))
        }
        let pieces = value.dropFirst(7).split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, let iv = decode(pieces[0]), iv.count == 12, let tag = decode(pieces[1]), tag.count == 16, let cipher = decode(pieces[2]) else { throw failure("ZCode 官方登录文件格式无效") }
        let material = secret.flatMap { $0.isEmpty ? nil : $0 } ?? "zcode-credential-fallback:darwin:\(home):\(username)"
        let key = SymmetricKey(data: SHA256.hash(data: Data(material.utf8)))
        guard let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: cipher, tag: tag), let clear = try? AES.GCM.open(box, using: key), let text = String(data: clear, encoding: .utf8) else { throw failure("无法读取 ZCode 官方登录；请确认客户端数据目录与凭据设置") }
        return text
    }
}


extension ChinaLoginPayload {
    // POST is permitted only for short-lived tokens under an already selected key ID.
    static func zcodeRequestAllowed(path: String, hasBody: Bool, bearer: Bool) -> Bool {
        if hasBody {
            return bearer && path.range(of: #"^/api/biz/v1/organization/[^/]+/projects/[^/]+/api_keys/[^/]+/access_tokens$"#, options: .regularExpression) != nil
        }
        return !bearer && (path == "/api/biz/customer/getCustomerInfo" || path == "/api/monitor/usage/quota/limit" || path.range(of: #"^/api/biz/v1/organization/[^/]+/projects/[^/]+/api_keys$"#, options: .regularExpression) != nil)
    }
}
