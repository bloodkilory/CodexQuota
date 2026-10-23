import Foundation
import CryptoKit
import Darwin

useTestLanguage()
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
func rejects(_ action: () throws -> Void, _ message: String) { do { try action(); fatalError(message) } catch {} }
let legacy = try ChinaLoginPayload.minimax(data(["base_resp": ["status_code": 0], "model_remains": [["current_interval_total_count": 100, "current_interval_usage_count": 75, "end_time": 2_000_000_000_000, "current_weekly_remaining_percent": 40]]]))
check(legacy.buckets[0].primary?.remaining == 75, "MiniMax misleading usage_count is remaining count")
check(legacy.buckets[0].secondary?.remaining == 40, "weekly remaining percent")
check(legacy.buckets[0].primary?.resetsAt == 2_000_000_000, "MiniMax milliseconds")
rejects({ _ = try ChinaLoginPayload.minimax(data(["model_remains": [["current_interval_remaining_percent": true]]])) }, "boolean is not percentage")
rejects({ _ = try ChinaLoginPayload.minimax(data(["model_remains": [["current_interval_remaining_percent": 0, "current_interval_status": 3]]])) }, "unlimited is not exhausted finite quota")
rejects({ _ = try ChinaLoginPayload.minimax(data(["base_resp": ["status_code": 100], "model_remains": [["current_interval_remaining_percent": 90]]])) }, "failed backend must not become successful quota")
let zcode = try ChinaLoginPayload.zcode(data(["code": 200, "data": ["limits": [["type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 25], ["type": "CREDIT_LIMIT", "unit": 6, "percentage": 40], ["type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 10]]]]))
check(zcode.rateLimitsByLimitId?["zcode"]?.primary?.remaining == 75, "ZCode percentage is used")
check(zcode.rateLimitsByLimitId?["zcode"]?.secondary?.minutes == 10080, "weekly units")
check(zcode.rateLimitsByLimitId?["zcode-tools"]?.primary?.minutes == nil, "calendar month must not invent 30 day duration")
check(zcode.rateLimitsByLimitId?["zcode-tools"]?.primary?.title == "月工具额度", "monthly label")
rejects({ _ = try ChinaLoginPayload.zcodeEnvelope(data(["code": 1e100, "data": [:]])) }, "huge numeric code rejected safely")
let secret = "fixture-only-secret"
let box = try AES.GCM.seal(Data("fixture-session".utf8), using: SymmetricKey(data: SHA256.hash(data: Data(secret.utf8))))
func b64(_ value: Data) -> String { value.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let encrypted = "enc:v1:" + b64(Data(box.nonce)) + "." + b64(box.tag) + "." + b64(box.ciphertext)
let decrypted = try ChinaLoginPayload.decryptZCode(encrypted, home: "/fixture", username: "fixture", secret: secret)
check(decrypted == "fixture-session", "official AES-GCM format")
rejects({ _ = try ChinaLoginPayload.decryptZCode(encrypted, home: "/fixture", username: "fixture", secret: "wrong") }, "wrong secret must fail")
let directory = URL(fileURLWithPath: "/fixture/.minimax")
let hash = b64(Data(SHA256.hash(data: Data("/fixture/.minimax/auth\0mcode-public".utf8))))
let record: [String: Any] = ["schemaVersion": 1, "accessToken": "fixture-only", "tokenType": "Bearer", "clientId": "mcode-public", "audience": "agent-backend", "scopes": ["agent.default"], "expiresAtMs": 200000]
let credential = data(["schemaVersion": 1, "records": ["com.minimax.mcode.oauth.prod.cn\0" + hash: record]])
let loaded = try ChinaLoginPayload.credential(credential, dataDirectory: directory, now: 100)
check(loaded == "fixture-only", "official namespace")
rejects({ _ = try ChinaLoginPayload.credential(credential, dataDirectory: directory, now: 201) }, "expired token rejected")
rejects({ _ = try ChinaLoginPayload.credential(credential, dataDirectory: URL(fileURLWithPath: "/different"), now: 100) }, "wrong data namespace rejected")
check(ChinaLoginPayload.header("secret\r\nInjected: yes") == nil, "header injection blocked")
let personalProject = try ChinaLoginPayload.zcodePersonalProject(["organizations": [["organizationId": "org", "projects": [["projectId": "team", "projectName": "默认项目", "projectType": " 2 "], ["projectId": "personal", "projectType": 1]]]]])
check(personalProject.projectID == "personal", "whitespace-wrapped team type must not be selected as personal")
rejects({ _ = try ChinaLoginPayload.zcodePersonalProject(["organizations": [["organizationId": "org", "projects": [["projectId": "team", "projectType": " 2 "]]]]]) }, "team-only account must not become personal")
let nestedPersonal: [String: Any] = ["data": ["workspaces": [["workspace_type": 0, "workspace_id": "personal", "data": ["op_group_id": "group"]]]]]
let personalWorkspace = try ChinaLoginPayload.minimaxPersonalWorkspace(nestedPersonal)
check(ChinaLoginPayload.minimaxGroup(personalWorkspace) == "group", "official nested personal membership supported")
rejects({ _ = try ChinaLoginPayload.matrixObject(data(["statusInfo": ["code": 1], "data": ["userInfo": ["realUserID": "wrong"]]])) }, "failed identity envelope rejected")
let fileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fileDirectory) }
let fifo = fileDirectory.appendingPathComponent("credentials.json")
check(mkfifo(fifo.path, 0o600) == 0, "synthetic FIFO fixture")
rejects({ _ = try readChinaCredentialFile(fifo, message: "fixture rejection") }, "credential FIFO must fail without blocking")
let transport = ChinaQuotaTransport()
let session = URLSession(configuration: .ephemeral)
let task = session.dataTask(with: URL(string: "https://bigmodel.cn/")!)
var redirectDenied = false
transport.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: URL(string: "https://bigmodel.cn/")!, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: "https://example.invalid/")!)) { redirectDenied = $0 == nil }
check(redirectDenied, "credential-bearing redirects refused")
var oversizedDenied = false
transport.urlSession(session, dataTask: task, didReceive: URLResponse(url: URL(string: "https://bigmodel.cn/")!, mimeType: "application/json", expectedContentLength: 1_048_577, textEncodingName: "utf-8")) { oversizedDenied = $0 == .cancel }
check(oversizedDenied, "oversized response rejected before download")
session.invalidateAndCancel()


check(!ChinaLoginPayload.zcodeRequestAllowed(path: "/api/biz/v1/organization/org/projects/project/api_keys", hasBody: true, bearer: false), "persistent key creation forbidden")
check(!ChinaLoginPayload.zcodeRequestAllowed(path: "/api/biz/v1/organization/org/projects/project/api_keys", hasBody: true, bearer: true), "persistent key creation forbidden even with bearer")
check(ChinaLoginPayload.zcodeRequestAllowed(path: "/api/biz/v1/organization/org/projects/project/api_keys/id/access_tokens", hasBody: true, bearer: true), "existing-key scoped session exchange allowed")

let issuedFixture = data(["code": 200, "data": ["accessToken": "fixture-only", "tokenType": "Bearer", "expiresAt": 200, "expiresIn": 100]])
let issued = try ChinaLoginPayload.zcodeProjectToken(issuedFixture, now: 150)
check(issued == "fixture-only", "project token expiry uses seconds")
rejects({ _ = try ChinaLoginPayload.zcodeProjectToken(issuedFixture, now: 201) }, "expired project token rejected")
rejects({ _ = try ChinaLoginPayload.zcodeProjectToken(data(["code": 200, "data": ["enable": false]]), now: 150) }, "disabled exchange rejected")
print("China login fixture and transport contracts passed")
