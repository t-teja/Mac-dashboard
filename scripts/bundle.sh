#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Headroom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Headroom "$APP/Contents/MacOS/Headroom"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
