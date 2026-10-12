#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' .build/CodexQuota.app/Contents/Info.plist)
STAGE=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R .build/CodexQuota.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明 - Read me.txt" <<'TXT'
CodexQuota — AI quota, at a glance.

1. Drag CodexQuota.app to Applications. Eject this disk image.
2. Open the installed app. Look for the CX capsule in the menu bar.
3. Sign in with your provider's official CLI. See the project README.
4. Enable “登录时启动” in the app to launch at login.

拖动 CodexQuota.app 到 Applications 文件夹，推出磁盘，再打开已安装的应用。
应用运行在菜单栏，没有 Dock 图标。请先安装并登录所需平台的官方 CLI。

This community build is ad-hoc signed, not Apple-notarized.
If macOS blocks the first launch, use System Settings → Privacy & Security → Open Anyway for this app.
本构建未经 Apple 公证。首次打开被阻止时，可在系统设置 → 隐私与安全性中为本应用选择“仍要打开”。
Do not disable Gatekeeper globally. 不需要关闭系统的安全保护。
TXT
mkdir -p dist
DMG="dist/CodexQuota-$VERSION-universal.dmg"
hdiutil create -ov -volname CodexQuota -srcfolder "$STAGE" -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "CodexQuota-$VERSION-universal.dmg" > SHA256SUMS.txt)
echo "$PWD/$DMG"
