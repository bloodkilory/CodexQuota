#!/bin/bash
set -euo pipefail
launchctl bootout "gui/$(id -u)/local.codexquota" 2>/dev/null || true
pkill -x QuotaNest 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.codexquota.plist"
rm -rf "$HOME/Applications/QuotaNest.app"
echo 'QuotaNest 已卸载；源码、诊断信息和更新备份保留。'
