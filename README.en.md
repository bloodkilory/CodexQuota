<p align="center"><img src="assets/quotanest.png" width="120" alt="QuotaNest"></p>
<h1 align="center">QuotaNest · 余度</h1>
<p align="center">AI subscription quotas, right in your Mac menu bar.<br><a href="README.md">中文文档</a></p>

A native Swift/AppKit menu bar utility for **Codex, Claude Code, and Google Antigravity**. A small capsule shows your remaining quota and refreshes every three minutes. Click it for individual limits and reset times. The current app interface is Chinese.

![Menu bar rendering, enlarged 3× with sample data](assets/capsule-preview.png)

<p align="center"><sub>Actual rendering, enlarged 3× · Sample quotas · Colored = remaining, black = used</sub></p>

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

## Use

Select a provider in the popover: **Codex**, **Claude Code**, or **Antigravity**. The capsule reports the lowest remaining value among the selected provider’s applicable windows (Codex uses its main bucket). It is not an average across models. Reset times use your system time zone.

Green means ≥20%, orange 10–20%, red <10%. `!` means refresh failed and the value is stale; `—` means no valid data yet. The app also refreshes on launch and wake. Choose **登录时启动** to launch at login, **立即刷新** to refresh, and **退出** to quit. After moving the installed app, toggle launch at login off and on to update its path.

## Privacy and limitations

No app-owned server, analytics, model conversations, automatic credit purchases, or automatic updater. Codex and Antigravity manage their own credentials. Claude OAuth is used only in memory for the official usage endpoint, without redirects or credential rewrites; expired credentials require signing in again. That endpoint may change upstream.

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

The compact capsule uses provider marks instead of letter abbreviations. Its colored width tracks the remaining percentage; the depleted portion is black. A failed refresh preserves the last known fraction in gray with `!`. Updates follow real quota readings every 180 seconds.

