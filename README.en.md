<p align="center"><img src="assets/quotanest.png" width="120" alt="QuotaNest"></p>
<h1 align="center">QuotaNest · 余度</h1>
<p align="center">AI subscription quotas, right in your Mac menu bar.<br><a href="README.md">中文文档</a></p>

A native Swift/AppKit menu bar utility for **Codex, Claude Code, and Google Antigravity**, plus five experimental domestic-provider adapters. A small capsule shows your remaining quota and refreshes every minute. Click it for individual limits and reset times. The current app interface is Chinese.

![Menu bar rendering, enlarged 3× with sample data](assets/capsule-preview.png)

<p align="center"><sub>Actual rendering, enlarged 3× · Sample quotas · Colored = remaining, black = used</sub></p>

## Experimental domestic-provider adapters

Five adapters have been added: **Kimi Code, Zhipu ZCode, MiniMax Code, Qoder and Tencent CodeBuddy**. They reuse official logins only: no API-key entry, storage or creation. These are feasibility-based choices, not a popularity ranking. **Official-source and synthetic-fixture verification only; none has been tested with a real account.** The app labels them experimental.

| Adapter | Supported login | Quota |
| --- | --- | --- |
| Kimi Code | Mainland official-client login cache | 5-hour, weekly, monthly |
| ZCode / GLM | Mainland personal login and an already initialized project | 5-hour, weekly, monthly tools when returned |
| MiniMax Code | Mainland personal official OAuth | 5-hour and weekly |
| Qoder | Compatible global npm CLI + Node.js, browser login; reviewed 1.1.68 | Plan, add-on and organization credits; no guessed reset |
| CodeBuddy | Mainland personal login in the official VS Code extension, default profile | Active-cycle credits; explicit Keychain authorization |

Qoder native-only/CN builds and standalone CodeBuddy CLI logins are not supported. ZCode exchanges an existing official project identifier for a short-lived token; it does not create a persistent API key. Expired sessions must be renewed in official clients. The capsule remains 64 points wide; its right button cycles available periods, with `额` for billing/monthly quota. Missing logins show unknown, never fake usage.

See evidence and limitations: [Kimi](docs/providers/kimi.md), [ZCode/MiniMax](docs/providers/china-login.md), [Qoder](docs/providers/qoder-codebuddy.md), [CodeBuddy](docs/providers/codebuddy.md).

## Install

Requires macOS 13+. Download the universal DMG from this repository’s **[Releases](https://github.com/bloodkilory/QuotaNest/releases/latest)**, drag the app into **Applications**, eject the image, then open the installed app. Intel and Apple Silicon binaries are included. Provider CLIs are separate prerequisites.

The current community build is ad-hoc signed and **not Apple-notarized**. If blocked after first launch, allow this app in **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper globally. Managed Macs may disallow this.

## Upgrade from CodexQuota

Quit CodexQuota, install and open QuotaNest, then move the old app to Trash. Provider selection and launch-at-login preference are retained; enabled login entries update to the new executable path on launch. The internal `local.codexquota` identifier and `Application Support/CodexQuota` directory remain for compatibility.

## Connect

- **Codex:** install the [official CLI](https://github.com/openai/codex), then run `codex login` with your subscription account.
- **Claude Code:** install the [official CLI](https://code.claude.com/docs/en/setup), then run `claude auth login`. The app reads the default subscription OAuth credential file or the `Claude Code-credentials` Keychain item. Use the in-app authorization button if Keychain access is needed. API keys and proxy tokens are not subscription OAuth credentials.
- **Antigravity:** install and sign in to the [official CLI](https://antigravity.google/docs/cli), version 1.1.11+. Usage is read with `agy -p /usage --output-format json`.

Codex and Antigravity are discovered in `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`. Providers work independently. Custom credential profiles and third-party API balances are not supported.

For an unreliable Clash TUN route, the app preference `codexHTTPSProxy` can point at Clash's current local HTTP port. It is passed only to the official Codex subprocess when `HTTPS_PROXY`/`https_proxy` is absent; system proxy settings, Clash rules and login data are unchanged. Update the preference if the port changes, or remove it to restore the default route.

## Use

### Existing CC Switch connections and DeepSeek balances

Choose **连接已有工具…** in the Accounts view to select existing Claude Code / Codex connections from CC Switch (database schema 18–20). Reads are local and read-only; the data directory can be selected without entering a key. This version queries balances only for official DeepSeek endpoints, using existing credentials and the fixed HTTPS balance API. It does not change routing, execute usage scripts/helpers, store another key, or send inference requests. Other services are identified with an unsupported-query label. New GLM, Kimi API, Kilo, Kiro and Grok adapters are outside this release's implementation.

Pin a wallet amount to the 64-point menu bar capsule, or unpin it to restore the previous official subscription. Paid and granted balances are components of the reported total, not additional balances to sum again. Accounts and Tools views show configuration provenance; saved routing is not proof of every running session's actual provider. Original platforms, application updates and login startup remain under **官方套餐与应用设置**.

The glass-style interface supports light/dark appearances and reduced transparency. The macOS 15 compatibility appearance is locally verified; builds made with a suitable SDK use native Liquid Glass for the popover on macOS 26+, which has not been tested on a physical newer-system device.

Select a provider in the popover: **Codex**, **Claude Code**, or **Antigravity**. The capsule reports the lowest remaining value among the selected period’s applicable windows (Codex uses its main bucket; Antigravity uses Gemini groups only). If Gemini quota is unavailable, Antigravity shows `—` rather than substituting another model. All model groups remain available in the popover. It is not an average across models. Reset times use your system time zone.

Provider accents are teal for Codex, terracotta for Claude and blue for Antigravity. `!` means refresh failed and the value is stale; `—` means no valid data yet. The app also refreshes on launch and wake. Choose **登录时启动** to launch at login, **立即刷新** to refresh, and **退出** to quit. After moving the installed app, toggle launch at login off and on to update its path.

## Application updates

Starting with v1.7.0, QuotaNest silently checks this repository's latest stable GitHub Release once at launch. **检查更新** checks again manually; there is no periodic check or settings switch. **更新到 vX.Y.Z** downloads the exact universal DMG and SHA256SUMS.txt, verifies SHA-256, bundle identity/version/resources, universal architecture and signature integrity, then asks to install and restart.

Self-installation supports only `~/Applications/QuotaNest.app` and `/Applications/QuotaNest.app`. The system Applications target requests macOS administrator authorization. Provider settings, official logins and the launch-at-login choice are retained. The previous app remains beside the installation as `QuotaNest.app.previous.*`; replacement/validation failures attempt to restore it. If relaunch fails, open the app manually to see its recorded installation status. DMG or build-directory launches can check but cannot install.

Only stable releases from `bloodkilory/QuotaNest` are used. Checksums verify release asset integrity; current builds remain ad-hoc signed and not notarized.

## Privacy and limitations

No app-owned server, analytics, model conversations or automatic credit purchases. Update checks and user-triggered downloads contact GitHub's official release services without provider credentials. Codex and Antigravity manage their own credentials. Claude OAuth is used only in memory for the official usage endpoint, without redirects or credential rewrites; expired credentials require signing in again. That endpoint may change upstream.

Local diagnostics live at `~/Library/Application Support/CodexQuota/status.json` and contain usage/status but no tokens or account IDs. Review diagnostics before sharing. Independent community project, unaffiliated with OpenAI, Anthropic, or Google.

## Build and contribute

Install Xcode Command Line Tools, then run:

```sh
./scripts/test.sh
./scripts/package-dmg.sh
```

The DMG and SHA-256 file appear in `dist/`. `./scripts/install.sh` optionally installs to `~/Applications`, enabling login launch on a new source installation. `SIGNING_IDENTITY` enables Developer ID signing; notarization is a separate maintainer step. Apple Silicon is cross-compiled; local runtime verification was performed on Intel, not every supported OS/hardware combination.

To uninstall a DMG installation, disable launch at login, quit, and move the app to Trash. Optionally remove the application-support directory. For source-script installations use `./scripts/uninstall.sh`.

Issues and pull requests are welcome. Include OS/app/CLI versions and redacted reproduction details. Never upload tokens or credential files. If useful, consider starring the repository.

[MIT License](LICENSE). Original app icon generated with AI assistance; third-party trademarks belong to their owners.

The compact capsule uses provider marks instead of letter abbreviations. Its colored width tracks the remaining percentage over a translucent base. Wallet amounts have no percentage fill. A failed refresh preserves the last known reading with `!`. Updates follow real quota readings every 60 seconds. Codex transient service/connection failures get one reconnect and retry within a shared 30-second budget; authentication, permission and rate-limit errors do not retry immediately. Exhausted retries still show stale data explicitly.

The 64-point capsule has a narrow period button after a vertical separator. Click `5h` / `1w` / `额` to switch available cached hourly, weekly or billing quotas instantly. Each provider remembers its selection; hours are preferred initially. With only one valid period the switch is disabled. Click the left portion for details. The progress fill applies only to the left portion; the period button stays black.
