import Foundation
import SQLite3

useTestLanguage()
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
func rejects(line: UInt = #line, _ body: () throws -> Void) { do { try body(); fatalError("Expected rejection at test line \(line)") } catch {} }
func fixture(_ accounts: String, _ total: Int = 2) -> Data {
    Data("{\"code\":0,\"data\":{\"Response\":{\"Data\":{\"TotalCount\":\(total),\"Accounts\":\(accounts)}}}}".utf8)
}
let sample = fixture(#"[{"Status":0,"CapacityType":2,"CycleCapacityRemainPrecise":"50","CycleCapacitySizePrecise":"100","CapacityRemainPrecise":"950","CapacitySizePrecise":"1000"},{"Status":3,"CapacityType":2,"CycleCapacityRemainPrecise":"0","CycleCapacitySizePrecise":"100"}]"#)
let snapshot = try CodeBuddyPayload.decode(sample)
check(snapshot.remaining == 25, "exhausted packages remain in denominator; current cycle takes precedence")
check(snapshot.buckets.first?.primary?.minutes == nil, "no invented reset duration")
let slice = fixture(#"[{"Status":0,"CapacityType":4,"CapacityRemainPrecise":"1000","CapacitySizePrecise":"1000","SlicePeriodUsageDetails":[{"SlicePeriodCapacityRemainPrecise":"20","SlicePeriodCapacitySizePrecise":"40"}]}]"#, 1)
let sliceSnapshot = try CodeBuddyPayload.decode(slice)
check(sliceSnapshot.remaining == 50, "slice current allowance")
rejects { _ = try CodeBuddyPayload.decode(fixture("[]", 201)) }
rejects { _ = try CodeBuddyPayload.decode(fixture(#"[{"Status":0,"CapacityType":4,"CapacityRemainPrecise":"1000","CapacitySizePrecise":"1000"}]"#, 1)) }
rejects { _ = try CodeBuddyPayload.decode(Data(#"{"code":401,"message":"secret"}"#.utf8)) }
let valid = "e30." + Data(#"{"exp":9999}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") + ".synthetic"
let plain = try JSONSerialization.data(withJSONObject: ["auth": ["accessToken": valid, "domain": "https://www.codebuddy.cn"]])
let accessToken = try CodeBuddyLogin.accessToken(plain, now: 100)
check(accessToken == valid, "official auth object")
rejects { _ = try CodeBuddyLogin.accessToken(plain, now: 10000) }
rejects { _ = try CodeBuddyLogin.accessToken(Data(#"{"api_key":"fake"}"#.utf8), now: 0) }
rejects { _ = try CodeBuddyLogin.accessToken(try JSONSerialization.data(withJSONObject: ["auth": ["accessToken": valid, "domain": "https://www.codebuddy.ai"]]), now: 100) }
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let dbURL = directory.appendingPathComponent("state.vscdb")
var db: OpaquePointer?
check(sqlite3_open(dbURL.path, &db) == SQLITE_OK, "fixture DB")
check(sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT UNIQUE, value BLOB)", nil, nil, nil) == SQLITE_OK, "fixture schema")
check(sqlite3_exec(db, "INSERT INTO ItemTable VALUES ('unrelated-secret', 'never-read')", nil, nil, nil) == SQLITE_OK, "unrelated row")
sqlite3_close(db)
rejects { _ = try CodeBuddyLogin.encryptedSecret(database: dbURL) }
// Generated independently with Python hashlib.pbkdf2_hmac + OpenSSL AES-128-CBC.
let cipherHex = "76313011ba2cd7ec6c04e3c61bee729e617a1f85c2c9d1e274f0be3fa373729060d0ac1a5bd9ac525e60a2c208df383e952e32d8370c7ff51da7c9ed0f871945a09133622f5dbe8eb05ea3c5f8c4ef662c42a4"
let chars = Array(cipherHex)
let cipher = Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0+1]), radix: 16)! })
let decrypted = try CodeBuddyLogin.decrypt(cipher, password: Data("synthetic-password".utf8))
check(String(data: decrypted, encoding: .utf8) == #"{"auth":{"accessToken":"synthetic","domain":"https://www.codebuddy.cn"}}"#, "full Chromium CBC plaintext including first block")
rejects { _ = try CodeBuddyLogin.accessToken(CodeBuddyLogin.decrypt(cipher, password: Data("incorrect-password".utf8)), now: 100) }
check(sqlite3_open(dbURL.path, &db) == SQLITE_OK, "reopen fixture DB")
var statement: OpaquePointer?
check(sqlite3_prepare_v2(db, "INSERT INTO ItemTable VALUES (?1, ?2)", -1, &statement, nil) == SQLITE_OK, "prepare synthetic row")
let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
let bufferJSON = String(data: try JSONSerialization.data(withJSONObject: ["type": "Buffer", "data": Array(cipher)]), encoding: .utf8)!
sqlite3_bind_text(statement, 1, CodeBuddyLogin.secretKey, -1, transient)
sqlite3_bind_text(statement, 2, bufferJSON, -1, transient)
check(sqlite3_step(statement) == SQLITE_DONE, "insert synthetic ciphertext")
sqlite3_finalize(statement); sqlite3_close(db)
let selectedCipher = try CodeBuddyLogin.encryptedSecret(database: dbURL)
check(selectedCipher == cipher, "reads only exact CodeBuddy row")
print("CodeBuddy fixture tests passed")
