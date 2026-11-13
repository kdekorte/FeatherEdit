#!/bin/bash
# Package FeatherEdit as a proper macOS app bundle in build/FeatherEdit.app
# and ad-hoc code-sign it. Pass --install to also copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="FeatherEdit"
BUNDLE_ID="com.featheredit.app"
CONFIG="release"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

swift build -c "$CONFIG"
BIN=".build/$CONFIG/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"
cp Sources/FeatherEdit/Resources/FeatherEdit.icns "$APP_DIR/Contents/Resources/FeatherEdit.icns"

# Ad-hoc signature (no developer account needed for local use).
codesign --force --deep --sign - "$APP_DIR"

# Register the bundle (and its document types) with Launch Services so it
# shows up in Finder's "Open With" right away.
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREG" ]; then
    "$LSREG" -f "$PWD/$APP_DIR"
fi

echo "Created $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
    echo "Installed to /Applications/$APP_NAME.app"
    echo "You can now use:  open -a FeatherEdit file.txt"
fi
