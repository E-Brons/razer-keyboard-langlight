#!/bin/sh
# Build release binary (Info.plist is embedded by Package.swift) and ad-hoc codesign it.
set -e
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
BIN=.build/release/langlight
codesign --force --sign - --identifier local.langlight "$BIN"
echo "built $BIN"
