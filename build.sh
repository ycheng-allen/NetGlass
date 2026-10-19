#!/bin/bash
# Build NetGlass.app  —  ./build.sh [run]
set -e
cd "$(dirname "$0")"

APP="build/NetGlass.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> swiftc compiling…"
# Use the Xcode toolchain: the CLT swiftc cannot load the SwiftUI macro plugins.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -O -parse-as-library \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/NetGlass" \
    -target arm64-apple-macos15.0

cp Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force -s - "$APP" 2>/dev/null || true

echo "==> built: $(pwd)/$APP"

if [ "$1" == "run" ]; then
    open "$APP"
fi

if [ "$1" == "install" ]; then
    pkill -x NetGlass 2>/dev/null || true
    sleep 1
    rm -rf /Applications/NetGlass.app
    ditto "$APP" /Applications/NetGlass.app
    open /Applications/NetGlass.app
    echo "==> installed to /Applications and launched"
fi
