#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$HOME/Applications/QuotaNest.app"
LEGACY_APP="$HOME/Applications/CodexQuota.app"
AGENT="$HOME/Library/LaunchAgents/local.codexquota.plist"
if [ ! -x .build/QuotaNest.app/Contents/MacOS/QuotaNest ]; then ./scripts/build.sh; fi
LOGIN_ENABLED=1
if { [ -d "$APP" ] || [ -d "$LEGACY_APP" ]; } && [ ! -f "$AGENT" ]; then LOGIN_ENABLED=0; fi
launchctl bootout "gui/$(id -u)/local.codexquota" 2>/dev/null || true
# Only stop this application's executable when updating.
pkill -x QuotaNest 2>/dev/null || true
pkill -x CodexQuota 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
if [ -d "$APP" ]; then mv "$APP" "$APP.previous.$(date +%Y%m%d%H%M%S)"; fi
if [ -d "$LEGACY_APP" ]; then mv "$LEGACY_APP" "$LEGACY_APP.previous.$(date +%Y%m%d%H%M%S)"; fi
cp -R .build/QuotaNest.app "$APP"
codesign --verify --deep --strict "$APP"
if [ "$LOGIN_ENABLED" = 1 ]; then
python3 - "$APP/Contents/MacOS/QuotaNest" "$AGENT" <<'PY'
import plistlib,sys
with open(sys.argv[2], 'wb') as f:
 plistlib.dump({'Label':'local.codexquota','ProgramArguments':[sys.argv[1]],'RunAtLoad':True,'LimitLoadToSessionType':'Aqua','ProcessType':'Interactive'}, f)
PY
launchctl bootstrap "gui/$(id -u)" "$AGENT"
else
  open "$APP"
fi
echo "Installed and started: $APP"
