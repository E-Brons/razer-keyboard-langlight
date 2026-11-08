#!/bin/sh
# Build, copy to ~/.local/bin, re-sign in place, and install the LaunchAgent.
# Extra arguments are passed to `langlight install` (e.g. --he FFFF00).
set -e
cd "$(dirname "$0")/.."
scripts/build.sh
mkdir -p "$HOME/.local/bin"
cp .build/release/langlight "$HOME/.local/bin/langlight"
codesign --force --sign - --identifier local.langlight "$HOME/.local/bin/langlight"
"$HOME/.local/bin/langlight" install "$@"
