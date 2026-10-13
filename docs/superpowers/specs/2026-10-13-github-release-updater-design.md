# GitHub Release Updater Design

## Goal

Let an installed QuotaNest user check for the latest stable GitHub Release at launch or from the menu, then explicitly download, verify, install, and restart into that release.

## Scope and decisions

- The only update source is `https://api.github.com/repos/bloodkilory/QuotaNest/releases/latest`.
- Only a non-draft, non-prerelease GitHub Release is eligible. There is no beta channel, custom feed, or user-configurable source.
- QuotaNest checks once after launch and again whenever the user presses **检查更新**. There is no settings switch for automatic checking.
- An update is downloaded and installed only after the user explicitly presses **更新到 vX.Y.Z**.
- Supported targets are exactly `~/Applications/QuotaNest.app` and `/Applications/QuotaNest.app`. A build-tree, DMG, or other arbitrary bundle path can check for updates but cannot self-install.
- Replacing `/Applications/QuotaNest.app` uses the normal macOS administrator authorization prompt. Replacing the current user's Applications copy does not need elevation.
- Existing provider login data and the `local.codexquota` launch-at-login preference remain untouched.
- Current ad-hoc signing and non-notarized distribution status remain accurately documented. This change does not imply a Developer ID or notarization claim.

## Release contract

Each eligible release must include both assets below:

1. `QuotaNest-<version>-universal.dmg`
2. `SHA256SUMS.txt`

The updater downloads the GitHub Release API JSON without redirects and decodes only the fields required for its version and assets. It ignores release notes and all other URLs. It downloads each selected asset through its fixed GitHub asset API URL using GitHub's binary asset protocol: that request may follow one HTTPS redirect only to `release-assets.githubusercontent.com` or `objects.githubusercontent.com`, and all other redirects fail. It accepts the DMG only if:

- the DMG asset name exactly matches the release tag version after the leading `v` is removed;
- `SHA256SUMS.txt` has exactly one SHA-256 row for that exact DMG filename;
- the downloaded DMG SHA-256 equals that row, using a constant-time digest comparison;
- the candidate version is strictly greater than `CFBundleShortVersionString` using numeric dotted-version comparison.

Missing, duplicate, malformed, oversize, or mismatched assets fail safely, as do metadata redirects and asset redirects outside the constrained GitHub path. No unverified archive is mounted or installed.

## Components

### `ReleaseUpdateClient`

Owns the fixed Release API request, stable-release validation, semantic version comparison, bounded asset downloads, and SHA-256 manifest parsing. It uses an ephemeral `URLSession`, no cookies or credential storage, explicit timeout, and response-size limits. It rejects all metadata redirects and permits only the constrained GitHub asset redirect described above. Its public result is one of:

- `.upToDate(currentVersion)`
- `.available(UpdateRelease)` with version, DMG URL, checksum URL, and expected digest
- `.failed(UpdateError)` with sanitized user-facing text

It never performs an installation and never trusts a URL supplied by a release body or local preference.

### `UpdateInstaller`

Receives only an already-verified DMG and an `UpdateRelease`. It determines whether `Bundle.main.bundleURL` resolves to one of the two supported Applications targets. It mounts the DMG privately, copies the contained `QuotaNest.app` into a private staging directory, then validates the staged bundle before scheduling installation:

- `CFBundleIdentifier == local.codexquota`;
- executable and expected resources are present;
- bundle version equals the verified release version and is greater than the running version;
- executable has both `arm64` and `x86_64` slices;
- `codesign --verify --deep --strict` succeeds;
- no stage or bundle component is a symbolic link.

The installer writes no authentication credentials and leaves diagnostic quota data unchanged.

### Bundled update helper

The application copies a small, independently runnable helper to its private staging directory before quitting. The helper has no networking code and accepts a narrow request: the current process ID, an already-validated staged app, one of the two fixed target paths, the original user ID, and whether the login item was enabled.

It waits for the main process to exit, creates a timestamped sibling backup, replaces the target, re-verifies the new app, and restores the backup on any replacement or validation failure. For a user target, it runs directly. For `/Applications`, the app starts the same helper through macOS administrator authorization; parameters are validated rather than interpolated into a shell command.

After a successful replacement, the helper starts the updated app in the original user's GUI session. If the login item was enabled, the app's normal launch behavior refreshes its executable path; the helper does not alter its enabled/disabled choice.

## Menu behavior

The popover contains an **应用更新** section below the refresh controls and above the launch-at-login and quit controls.

| State | Display | Enabled action |
| --- | --- | --- |
| idle / launch check | `正在检查更新…` | none while request is active |
| current | `当前版本 vX.Y.Z，已是最新` | `检查更新` |
| release available | `发现 vX.Y.Z` | `更新到 vX.Y.Z` and `检查更新` |
| downloading or verifying | progress text describing the current phase | none while a download or install is active |
| unsupported bundle location | explanatory text | `检查更新`; no install button |
| failure | sanitized error text | `检查更新` |

The initial check must not steal focus, show an alert, or interrupt quota refreshes. A manual install confirmation explains that the app will quit and restart. The macOS authorization prompt appears only when the user accepts installation to `/Applications`.

## Installation flow

1. Launch schedules one background latest-release check. The menu button can start the same check later.
2. If a newer stable release is available, the user selects **更新到 vX.Y.Z**.
3. The app downloads `SHA256SUMS.txt` and the exact DMG to a private, owner-only update staging directory. It verifies the digest before mounting.
4. The app copies and validates the staged app bundle, then displays an explicit final confirmation.
5. On confirmation, it prepares the helper, passes only validated paths and state, and terminates.
6. The helper waits for termination, backs up and replaces the target, validates the replacement, restores a backup after failure, and launches the new application.

If the download, mount, validation, authorization, copy, or restart fails, the currently running app remains usable until it exits. A failed post-exit replacement restores the prior bundle and reports the failure through a durable, non-sensitive status file that the next launch can show.

## Test strategy

New pure Swift fixture tests cover:

- stable release acceptance and draft/prerelease rejection;
- absent, duplicate, wrong-version, or wrong-filename assets;
- numeric dotted version equality, ordering, and malformed components;
- checksum parsing, duplicate rows, invalid hex, and digest mismatch;
- redirect, oversized response, malformed JSON, and cancellation errors;
- only the two supported target paths, including resolved-symlink rejection;
- bundle metadata, version, architecture, resource, code-signing, and symbolic-link validation;
- helper request validation, wait/backup/replace/restore sequence, and relaunch request construction.

Integration tests use temporary user-owned directories and fixture app bundles. They never mount an untrusted internet download, overwrite a real installation, modify a launch agent, or request administrator privileges.

The complete existing `./scripts/test.sh` suite, universal build, and packaging checks remain required before release.

## Documentation changes

Both README files describe the startup and manual check behavior, the exact GitHub source, required release assets, supported install locations, the `/Applications` administrator prompt, checksum and bundle validation, backup/restore behavior, and current ad-hoc/non-notarized status. Release notes mention the updater and its explicit-install behavior.
