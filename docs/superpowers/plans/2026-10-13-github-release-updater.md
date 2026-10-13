# GitHub Release Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Let an installed QuotaNest user discover, download, verify, and explicitly install a newer stable GitHub Release from the menu.

**Architecture:** Add pure release-validation models and a bounded network client for the fixed GitHub Release API. An installer validates a staged app bundle and gives a separately compiled helper a narrow request. The helper waits for QuotaNest to exit, backs up and replaces only an Applications target, then relaunches in the original GUI session. AppController only maps updater states to the menu and asks for consent.

**Tech Stack:** Swift 5, Foundation, CryptoKit, AppKit, Darwin, hdiutil, codesign, macOS osascript, shell build scripts.

**Spec:** docs/superpowers/specs/2026-10-13-github-release-updater-design.md

## Global Constraints

## Execution result — 2026-10-13

Implemented on `feat/github-release-updater`, based on `e37c390`. Implementation commits: `b8f7934` and `4649d90`. All six tasks are complete; the checklists below preserve the original plan rather than an exact shell transcript.

- Full existing and updater regression suite passed after final corrections (`scripts/test.sh`, exit 0).
- Production ReleaseUpdateClient live smoke accepted official v1.6.0 metadata, downloaded the actual checksum and DMG, and verified SHA-256. No live install performed.
- Final v1.7.0/build 10 app and helper both compiled for arm64 + x86_64. Actual built app passed the production bundle validator, strict deep signature verification, DMG verification and local SHA-256 manifest verification.
- An independent review found two Important issues: executing a writable helper as root, and accepting non-executable app/helper binaries. Both fixed in one pass with failing-then-passing tests. Root execution now checks a protected helper copy against a SHA-256 identity embedded in the running app.
- Deferred minors: administrator authorization cancellation retains the download stage; failure to move a rejected candidate aside can prevent restoration and require manual use of the retained backup.
- Implementation rulings: local version advanced to 1.7.0/10 (may be changed before publication); elevated installation copies into a protected sibling directory before validation (additional disk space); helper entry is `Helpers/Update/main.swift`, with shared replacement code in `Sources/UpdateReplacement.swift` (additional file); actual administrator prompt and GUI relaunch await a live update to a newer published release (OS integration remains unverified in a real install).
- No source push, tag, public release, main merge or installed-app replacement performed. Final DMG is in this worktree's `dist/QuotaNest-1.7.0-universal.dmg`.

## Global Constraints (implementation)

- Support macOS 13+ and retain universal arm64 + x86_64 builds.
- Request only https://api.github.com/repos/bloodkilory/QuotaNest/releases/latest; reject metadata redirects and do not persist cookies or credentials.
- Download selected assets through their fixed GitHub asset API endpoints, permitting one HTTPS redirect only to release-assets.githubusercontent.com or objects.githubusercontent.com.
- Accept only a newer non-draft, non-prerelease release with exact QuotaNest-version-universal.dmg and SHA256SUMS.txt assets.
- Verify a SHA-256 manifest row before mounting a downloaded DMG.
- Install only user Applications/QuotaNest.app or /Applications/QuotaNest.app, rejecting links and all other launch paths.
- Preserve provider credentials and enabled/disabled local.codexquota login-item state.
- Do not claim Developer ID signing or notarization.
- Tests must not overwrite a real app, request administrator authorization, alter a launch agent, or mount an internet download.

## Review Focus

- A metadata redirect, an asset redirect to an unapproved host, or a non-GitHub asset endpoint must never download.
- Duplicate or wrong-filename checksum rows must make install unavailable.
- A bundle from /Volumes, a build directory, or a symlink must not get an install button.
- A staged app with wrong version, architecture, identifier, resources, or signature must not replace an install.
- Replacement failure after exit must restore the previous app and record a sanitized status.

---

### Task 1: Release metadata and checksum primitives

**Files:**
- Create: Sources/UpdateModels.swift
- Create: Tests/Updates/main.swift
- Modify: scripts/test.sh

**Interfaces:**
- Produces DottedVersion, UpdateRelease, UpdateAvailability, and ReleaseManifest.
- ReleaseManifest.release(from:currentVersion:) throws -> UpdateAvailability.
- ReleaseManifest.digest(for:manifest:) throws -> Data.

- [ ] **Step 1: Write failing parser fixtures**

~~~
let current = DottedVersion("1.6.0")!
check(try ReleaseManifest.release(from: Data(releaseJSON(tag: "v1.7.0").utf8),
                                  currentVersion: current).isAvailable,
      "newer stable release is available")
check(DottedVersion("1.10.0")! > DottedVersion("1.9.9")!, "numeric version order")
checkThrows("draft release rejected") {
    try ReleaseManifest.release(from: Data(releaseJSON(tag: "v1.7.0", draft: true).utf8),
                                 currentVersion: current)
}
checkThrows("duplicate checksum rows rejected") {
    try ReleaseManifest.digest(for: "QuotaNest-1.7.0-universal.dmg", manifest: duplicateRows)
}
~~~

- [ ] **Step 2: Run the test and verify it fails**

Run: swiftc Sources/UpdateModels.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests

Expected: compilation fails because UpdateModels.swift and ReleaseManifest are absent.

- [ ] **Step 3: Implement the smallest parser**

~~~
struct DottedVersion: Comparable, Equatable {
    let components: [Int]
    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ Int($0).map { $0 >= 0 } ?? false }) else { return nil }
        components = parts.map { Int($0)! }
    }
}
~~~

Decode only tag, draft, prerelease, asset names, and asset API URLs. Require one exact DMG asset, one exact manifest asset, one valid 64-hex digest row, an HTTPS `api.github.com/repos/bloodkilory/QuotaNest/releases/assets/<id>` URL for each selected asset, and a version greater than current.

- [ ] **Step 4: Run the test and add it to the suite**

Run: swiftc Sources/UpdateModels.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests

Expected: release, asset, version, and checksum fixtures pass.

Add:

~~~
swiftc Sources/UpdateModels.swift Tests/Updates/main.swift -o .build/update-tests
.build/update-tests
~~~

to scripts/test.sh, then run ./scripts/test.sh and expect exit 0.

- [ ] **Step 5: Commit**

~~~
git add Sources/UpdateModels.swift Tests/Updates/main.swift scripts/test.sh
git commit -m "feat: validate GitHub update releases"
~~~

### Task 2: Bounded Release API and download client

**Files:**
- Create: Sources/ReleaseUpdateClient.swift
- Modify: Sources/UpdateModels.swift
- Modify: Tests/Updates/main.swift

**Interfaces:**
- Consumes Task 1 models.
- Produces ReleaseUpdateClient.check(currentVersion:completion:), download(_:completion:), and cancel().
- Produces VerifiedUpdateDMG with fileURL and release.

- [ ] **Step 1: Write failing transfer fixtures**

~~~
let client = ReleaseUpdateClient(session: fixtureSession(response: .metadataRedirect))
awaitFailure(client.check(currentVersion: DottedVersion("1.6.0")!),
             contains: "更新检查请求被重定向")
awaitFailure(ReleaseUpdateClient(session: fixtureSession(response: .unapprovedAssetRedirect))
             .download(release, completion: recordResult), contains: "更新资产重定向目标不受支持")
awaitFailure(ReleaseUpdateClient(session: fixtureSession(response: .oversized))
             .check(currentVersion: DottedVersion("1.6.0")!),
             contains: "更新信息超过大小限制")
~~~

Use a test-only URLProtocol to record requested URLs. Assert the only metadata request is the fixed Release API URL and that the DMG is not written before manifest parsing succeeds.

- [ ] **Step 2: Run the test and verify it fails**

Run: swiftc Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests

Expected: compilation fails because ReleaseUpdateClient is absent.

- [ ] **Step 3: Implement the bounded transfer client**

~~~
final class ReleaseUpdateClient {
    static let releaseURL = URL(string: "https://api.github.com/repos/bloodkilory/QuotaNest/releases/latest")!
    func check(currentVersion: DottedVersion,
               completion: @escaping (Result<UpdateAvailability, Error>) -> Void) { }
    func download(_ release: UpdateRelease,
                  completion: @escaping (Result<VerifiedUpdateDMG, Error>) -> Void) { }
}
~~~

Use an ephemeral session delegate that rejects all metadata redirects, and for a fixed GitHub asset API request permits one HTTPS redirect only to release-assets.githubusercontent.com or objects.githubusercontent.com. Require status 200, cap JSON and manifest at 128 KiB and DMG at 64 MiB, download checksum before DMG into a 0700 UUID staging directory, use CryptoKit.SHA256, perform constant-time digest comparison, and delete partial or mismatched files.

- [ ] **Step 4: Run transfer and full regression tests**

Run: swiftc Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests && ./scripts/test.sh

Expected: fixed-source, allowed asset redirect, rejected metadata/unknown-host redirect, size-cap, cancellation, checksum-order, and digest mismatch fixtures pass; full suite exits 0.

- [ ] **Step 5: Commit**

~~~
git add Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Tests/Updates/main.swift
git commit -m "feat: download verified update releases"
~~~

### Task 3: Staging, target validation, and helper request contract

**Files:**
- Create: Sources/UpdateInstaller.swift
- Create: Sources/UpdateHelperContract.swift
- Modify: Tests/Updates/main.swift

**Interfaces:**
- Produces UpdateTarget.resolve(runningBundle:home:) throws -> UpdateTarget.
- Produces UpdateInstaller.stage(_:currentVersion:completion:).
- Produces PreparedUpdate with stagedApp, target, and requestURL.
- Produces UpdateHelperRequest Codable with parent PID, staged/target paths, user ID, login state, expected version, and status path.

- [ ] **Step 1: Write failing temporary-directory fixtures**

~~~
check(try UpdateTarget.resolve(runningBundle: home.appendingPathComponent("Applications/QuotaNest.app"),
                               home: home).isUser,
      "user Applications target accepted")
checkThrows("arbitrary path rejected") {
    try UpdateTarget.resolve(runningBundle: temp.appendingPathComponent("QuotaNest.app"), home: home)
}
checkThrows("symlink target rejected") {
    try UpdateTarget.resolve(runningBundle: linkToUserApp, home: home)
}
checkThrows("wrong bundle identifier rejected") {
    try UpdateBundleValidator.validate(at: wrongIdentifierFixture, expectedVersion: DottedVersion("1.7.0")!)
}
~~~

Inject a command-running seam so tests force lipo and codesign success or failure without production binaries.

- [ ] **Step 2: Run the test and verify it fails**

Run: swiftc Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/UpdateInstaller.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests

Expected: compilation fails because target, validator, and request symbols are absent.

- [ ] **Step 3: Implement staging and validation**

~~~
protocol CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> Data
}
enum UpdateBundleValidator {
    static func validate(at app: URL, expectedVersion: DottedVersion,
                         runner: CommandRunning) throws { }
}
~~~

Mount only the verified DMG with hdiutil attach -nobrowse -readonly -mountpoint private-mount verified-dmg, copy exact QuotaNest.app to a new 0700 staging directory, detach in defer, validate metadata/resources/links/architectures/signature, and encode a 0600 helper request. Reject nonregular files and all symlinks in staged content.

- [ ] **Step 4: Run tests and commit**

Run: swiftc Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/UpdateInstaller.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests && ./scripts/test.sh

Expected: target eligibility, bundle rejection, and request round-trip fixtures pass.

~~~
git add Sources/UpdateInstaller.swift Sources/UpdateHelperContract.swift Tests/Updates/main.swift
git commit -m "feat: stage verified update bundles"
~~~

### Task 4: Replacement helper and privilege launcher

**Files:**
- Create: Helpers/QuotaNestUpdateHelper.swift
- Create: Sources/UpdatePrivilegeLauncher.swift
- Modify: Sources/UpdateHelperContract.swift
- Modify: Tests/Updates/main.swift
- Modify: scripts/build.sh
- Modify: scripts/test.sh

**Interfaces:**
- Helper accepts exactly --request absolute-request-json-path.
- Produces UpdatePrivilegeLauncher.launch(helper:request:target:) throws.
- Helper consumes UpdateHelperRequest and writes sanitized status JSON.

- [ ] **Step 1: Write failing helper-recovery fixtures**

~~~
try UpdateHelper.run(request: failingReplacementRequest, operations: failingReplacementOperations)
check(FileManager.default.fileExists(atPath: target.path), "backup restored after replacement failure")
check(readStatus(status).state == "failed", "failure status recorded")
checkThrows("unapproved target rejected") {
    try UpdateHelperRequest.load(requestWithTarget("/tmp/QuotaNest.app"))
}
~~~

Compile helper core in a test target with injected file operations. Do not invoke osascript, /Applications, a live PID, or administrator credentials.

- [ ] **Step 2: Run the helper test and verify it fails**

Run: swiftc Sources/UpdateHelperContract.swift Helpers/QuotaNestUpdateHelper.swift Tests/Updates/main.swift -o /tmp/quotanest-update-helper-tests && /tmp/quotanest-update-helper-tests

Expected: compilation fails because helper symbols do not exist.

- [ ] **Step 3: Implement bounded replacement and launch**

~~~
enum UpdateHelper {
    static func run(request: UpdateHelperRequest,
                    operations: UpdateFileOperations = SystemUpdateFileOperations()) throws {
        try request.validate()
        try operations.waitForExit(request.parentPID, timeout: 30)
        try operations.replaceTargetWithBackup(
            stagedApp: URL(fileURLWithPath: request.stagedAppPath),
            targetApp: URL(fileURLWithPath: request.targetAppPath))
    }
}
~~~

Copy the resource helper to owner-only staging. Start it directly for the user target. For /Applications, use a fixed AppleScript invoking the validated helper and request as separately quoted arguments after the administrator prompt; no user string is interpolated into shell source. The helper revalidates request owner/mode/paths/bundle, restores backups on error, and relaunches with launchctl asuser user-id open target.

- [ ] **Step 4: Compile and package the helper**

Add a separate arm64/x86_64 helper compilation loop in scripts/build.sh, lipo it to Contents/Resources/quotanest-update-helper, and include it in deep signature verification. Add helper fixture compilation to scripts/test.sh.

- [ ] **Step 5: Run validation and commit**

Run: ./scripts/test.sh && ./scripts/build.sh && lipo -archs .build/QuotaNest.app/Contents/Resources/quotanest-update-helper && codesign --verify --deep --strict .build/QuotaNest.app

Expected: helper recovery and all existing tests pass; helper prints x86_64 arm64; signature check exits 0.

~~~
git add Helpers/QuotaNestUpdateHelper.swift Sources/UpdateHelperContract.swift Sources/UpdatePrivilegeLauncher.swift Tests/Updates/main.swift scripts/build.sh scripts/test.sh
git commit -m "feat: install verified updates with recovery"
~~~

### Task 5: Menu integration and documentation

**Files:**
- Modify: Sources/AppController.swift
- Modify: README.md
- Modify: README.en.md
- Modify: RELEASE_NOTES.md
- Modify: Tests/Updates/main.swift

**Interfaces:**
- AppController owns updateClient, updateInstaller, and UpdateMenuState.
- UpdateMenuState maps check/download/stage/install states to a label and button availability.

- [ ] **Step 1: Write failing menu-state fixtures**

~~~
check(UpdateMenuState.available(DottedVersion("1.7.0")!).title == "发现 v1.7.0",
      "available update label")
check(UpdateMenuState.unsupportedLocation.title.contains("Applications"),
      "unsupported location explains install target")
check(!UpdateMenuState.downloading.isActionEnabled, "download disables duplicate action")
~~~

- [ ] **Step 2: Run the test and verify it fails**

Run: swiftc Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Sources/UpdateInstaller.swift Sources/UpdateHelperContract.swift Tests/Updates/main.swift -o /tmp/quotanest-update-tests && /tmp/quotanest-update-tests

Expected: compilation fails because UpdateMenuState is absent.

- [ ] **Step 3: Integrate AppController**

Start checkForUpdate() in applicationDidFinishLaunching. Put an 应用更新 section in buildPopover() with state text, 检查更新, and 更新到 vX.Y.Z. Update UI on the main queue and disable duplicate actions during transfer/staging. Before scheduling the helper, require an NSAlert with 取消 and 下载并更新. Keep quota refresh independent.

- [ ] **Step 4: Update documentation**

Update both READMEs and release notes with launch/manual check behavior, fixed GitHub source, required assets, checksum and staged-bundle validation, supported installation paths, /Applications administrator prompt, backup restore, explicit user install action, and continued ad-hoc/non-notarized status.

- [ ] **Step 5: Run release verification and commit**

Run: ./scripts/test.sh && ./scripts/build.sh && ./scripts/package-dmg.sh && codesign --verify --deep --strict .build/QuotaNest.app && hdiutil verify dist/QuotaNest-*.dmg

Expected: all tests, universal compilation, signature verification, DMG creation, and DMG verification exit 0.

~~~
git add Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Sources/UpdateInstaller.swift Sources/UpdateHelperContract.swift Sources/UpdatePrivilegeLauncher.swift Sources/AppController.swift Tests/Updates/main.swift README.md README.en.md RELEASE_NOTES.md
git commit -m "feat: add menu-driven application updates"
~~~

### Task 6: Release-readiness review

**Files:**
- Review: docs/superpowers/specs/2026-10-13-github-release-updater-design.md
- Review: docs/superpowers/plans/2026-10-13-github-release-updater.md
- Review: updater source, tests, scripts, and documentation

- [ ] **Step 1: Compare implementation with design**

Run: git diff 0aa449e..HEAD --check && git diff 0aa449e..HEAD -- Sources Helpers Tests scripts README.md README.en.md RELEASE_NOTES.md

Expected: no whitespace errors; every specified trust, install, and documentation decision has an implementation.

- [ ] **Step 2: Run fresh package verification**

Run: ./scripts/test.sh && ./scripts/build.sh && ./scripts/package-dmg.sh && codesign --verify --deep --strict .build/QuotaNest.app && hdiutil verify dist/QuotaNest-*.dmg && shasum -a 256 -c dist/SHA256SUMS.txt

Expected: every command exits 0 and SHA256SUMS.txt reports the current DMG as OK.

- [ ] **Step 3: Record the real-install boundary**

State that automated tests do not request real administrator credentials or replace a real /Applications app. Run a real installed-app update only with the user's explicit request and a newer test Release, because it changes the installed application.

- [ ] **Step 4: Commit review-only corrections when needed**

~~~
git add Sources Helpers Tests scripts README.md README.en.md RELEASE_NOTES.md
git commit -m "fix: tighten updater release checks"
~~~

