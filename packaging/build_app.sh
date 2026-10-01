#!/bin/bash
# Builds EctoRemote.app from the SwiftPM executable, bundles icon + Info.plist,
# ad-hoc signs it, and produces a distributable .zip (and .dmg if possible).
# Runs on a macOS GitHub Actions runner.
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD="${2:-1}"
APP="EctoRemote.app"

echo "==> Building universal release binary (arm64 + x86_64)"
if swift build -c release --arch arm64 --arch x86_64; then
    BINDIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "    universal build failed, falling back to native arch"
    swift build -c release
    BINDIR="$(swift build -c release --show-bin-path)"
fi
BIN="$BINDIR/EctoRemote"
echo "    binary: $BIN"
file "$BIN" || true

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EctoRemote"
chmod +x "$APP/Contents/MacOS/EctoRemote"

sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

echo "==> Generating app icon"
if swift packaging/make_icon.swift icon.png; then
    rm -rf AppIcon.iconset
    mkdir -p AppIcon.iconset
    gen() { sips -z "$1" "$1" icon.png --out "AppIcon.iconset/$2" >/dev/null; }
    gen 16   icon_16x16.png
    gen 32   icon_16x16@2x.png
    gen 32   icon_32x32.png
    gen 64   icon_32x32@2x.png
    gen 128  icon_128x128.png
    gen 256  icon_128x128@2x.png
    gen 256  icon_256x256.png
    gen 512  icon_256x256@2x.png
    gen 512  icon_512x512.png
    gen 1024 icon_512x512@2x.png
    iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
    echo "    icon embedded"
else
    echo "    WARNING: icon generation failed, continuing without a custom icon"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP" || true

echo "==> Packaging zip"
ZIP="EctoRemote-macOS-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "    created $ZIP"

echo "==> Packaging dmg (best effort)"
DMG="EctoRemote-macOS-${VERSION}.dmg"
rm -f "$DMG"
STAGING="dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications" || true
if hdiutil create -volname "Ecto Remote" -srcfolder "$STAGING" -ov -format UDZO "$DMG"; then
    echo "    created $DMG"
else
    echo "    WARNING: dmg creation failed (zip is still available)"
fi

# Expose artifact names to the workflow if running in GitHub Actions.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "zip=$ZIP"
        echo "dmg=$DMG"
    } >> "$GITHUB_OUTPUT"
fi
echo "==> Done"
