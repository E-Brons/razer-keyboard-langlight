#!/bin/sh
# Stop any running langlight, rebuild, and start it again, persistently.
# Runs as an app in ~/Applications registered as a Login Item (starts at every login;
# it re-applies the color itself on wake/unlock). Tries a LaunchAgent first.
set -e
cd "$(dirname "$0")/.."
APP="$HOME/Applications/Langlight.app"
BIN="$APP/Contents/MacOS/langlight"
UID_=$(id -u)

scripts/build.sh

# stop previous instances
launchctl bootout "gui/$UID_/local.langlight" 2>/dev/null || true
"$BIN" login-item off 2>/dev/null || true
pkill -x langlight 2>/dev/null || true
sleep 1

# app bundle (binary has Info.plist embedded; add LSUIElement so no Dock icon)
mkdir -p "$APP/Contents/MacOS"
cp .build/release/langlight "$BIN"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.langlight</string>
<key>CFBundleName</key><string>Langlight</string>
<key>CFBundleExecutable</key><string>langlight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>langlight sets your Razer keyboard color by input language.</string>
</dict></plist>
P
codesign --force --deep --sign - --identifier local.langlight "$APP"

# keep the CLI copy current too
mkdir -p "$HOME/.local/bin"
cp .build/release/langlight "$HOME/.local/bin/langlight"
codesign --force --sign - --identifier local.langlight "$HOME/.local/bin/langlight"

# persist across logins
"$BIN" login-item
rm -f "$HOME/Library/LaunchAgents/local.langlight.plist"

open "$APP"
sleep 2
pgrep -lx langlight && echo "running; registered as login item"
