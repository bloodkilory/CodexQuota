# QuotaNest Windows beta / Windows 内测版

The Windows client is independent of the Swift/AppKit macOS app. Target: **Windows 11 x64**. No Windows ARM64 or WSL login discovery yet.

Windows 客户端与现有 Mac 版独立，面向 **Windows 11 x64**。本轮不支持 Windows ARM64、WSL 内的登录以及其他平台的官方套餐额度。

## Install / 安装

Download `QuotaNest-windows-x64-beta` from the successful **Windows beta** Actions run. Extract the ZIP and check the installer against its adjacent `SHA256SUMS.txt`. Run `QuotaNest-1.9.0-beta.1-windows-x64-setup.exe`. Installation is per user and does not require writing to Program Files. Beta artifacts are not official Releases and are never delivered by the Mac updater.

从成功的 **Windows beta** Actions 下载上述 artifact，解压后核对 SHA-256，再运行安装程序。按当前用户安装。内测包没有 Windows 代码签名证书，系统可能显示 SmartScreen 提示；不自动关闭或绕过它。内测附件不进入 Mac 正式更新渠道。

```powershell
Get-FileHash .\QuotaNest-1.9.0-beta.1-windows-x64-setup.exe -Algorithm SHA256
```

## Use / 使用

- Open the tray icon to show the details window. Closing the window hides it; Settings → Quit exits the app. 托盘图标打开详情，关闭窗口后驻留托盘，在设置中退出。
- **Codex:** install the official native Windows CLI and sign in there. QuotaNest invokes `codex.exe app-server` directly, without cmd/PowerShell shell interpolation. Standard PATH and the official npm package's native vendor path are searched. It never falls back to WSL or invokes an unknown `.cmd` shim. If not detected, add the directory containing the official `codex.exe` to PATH and restart QuotaNest.
- **DeepSeek:** Settings → CC Switch data directory → Read saved connections; then choose an official DeepSeek connection in the single Display source selector. Existing schema 18–20 Claude Code/Codex configurations are supported. 不手动添加 Key，不改 CC Switch 的任何配置，不声称配置就是实际会话路由。
- Only `https://api.deepseek.com/user/balance` is queried, using the selected saved official credential. Third-party/localhost proxy endpoints are recognized as unsupported rather than sent a balance request. Keys stay in the Rust backend and are not sent to the WebView.
- Startup/manual/every-minute refresh; transient errors keep a marked stale reading. Credential/source changes clear old balances; unknown is never shown as zero.
- Language: follow system / English / 中文. Settings include launch at sign-in and manual update. Update checks run on startup and click only. Only formal GitHub Releases with the exact Windows x64 installer and matching SHA-256 are accepted; current Mac-only Releases yield no Windows update.

## Verification / 验证边界

CI uses synthetic credentials and database fixtures. It builds the actual Windows installer, runs Rust/frontend tests, installs the app in the runner, drives the native WebView2 with tauri-driver, saves English/Chinese screenshots, and uninstalls it. Successful CI does **not** prove real account querying or the complete Windows 11 desktop experience.

Release acceptance still needs Windows users to verify: real CC Switch versions/accounts, native Codex login, Clash/proxy behavior, tray position and overflow, 100%/125%/150% DPI, multiple monitors, sign-in startup and upgrade from an earlier installed build. Do not send keys, tokens, full databases, or unredacted account screenshots in bug reports.

## Development / 开发

```sh
cd windows
npm ci --ignore-scripts
npm test
npm run build
cargo test --locked --no-default-features --manifest-path src-tauri/Cargo.toml
npm run tauri dev
# On Windows, with official Tauri prerequisites installed:
npm run tauri build -- --bundles nsis
```

`npm run dev` opens a credential-free UI preview outside Tauri; synthetic data is clearly labeled. Native `QuotaNest.exe --demo` is also fixture-only and does not modify preferences, autostart, or real account configuration. The normal app does not set this flag.
