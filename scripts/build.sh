#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/.build/QuotaNest.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/bin
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
    swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework AppKit Sources/*.swift -o ".build/bin/QuotaNest-$ARCH"
done
lipo -create .build/bin/QuotaNest-arm64 .build/bin/QuotaNest-x86_64 -output "$APP/Contents/MacOS/QuotaNest"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/PROVIDER-MARKS.md "$APP/Contents/Resources/PROVIDER-MARKS.md"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexquota</string>
<key>CFBundleName</key><string>QuotaNest</string>
<key>CFBundleDisplayName</key><string>余度 QuotaNest</string>
<key>CFBundleExecutable</key><string>QuotaNest</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.1</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 QuotaNest contributors. MIT License.</string>
</dict></plist>
PLIST
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "$APP"
