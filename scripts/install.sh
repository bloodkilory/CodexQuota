#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$HOME/Applications/CodexQuota.app"
AGENT="$HOME/Library/LaunchAgents/local.codexquota.plist"
if [ ! -x .build/CodexQuota.app/Contents/MacOS/CodexQuota ]; then ./scripts/build.sh; fi
LOGIN_ENABLED=1
if [ -d "$APP" ] && [ ! -f "$AGENT" ]; then LOGIN_ENABLED=0; fi
launchctl bootout "gui/$(id -u)/local.codexquota" 2>/dev/null || true
# Only stop this application's executable when updating.
pkill -x CodexQuota 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
if [ -d "$APP" ]; then mv "$APP" "$APP.previous.$(date +%Y%m%d%H%M%S)"; fi
cp -R .build/CodexQuota.app "$APP"
codesign --verify --deep --strict "$APP"
if [ "$LOGIN_ENABLED" = 1 ]; then
python3 - "$APP/Contents/MacOS/CodexQuota" "$AGENT" <<'PY'
import plistlib,sys
with open(sys.argv[2], 'wb') as f:
 plistlib.dump({'Label':'local.codexquota','ProgramArguments':[sys.argv[1]],'RunAtLoad':True,'LimitLoadToSessionType':'Aqua','ProcessType':'Interactive'}, f)
PY
launchctl bootstrap "gui/$(id -u)" "$AGENT"
else
  open "$APP"
fi
echo "Installed and started: $APP"
