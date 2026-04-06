#!/bin/bash
#
# release.sh — Build both platforms and create a GitHub release
#
# Prerequisites:
#   - Version already bumped via bump-version.sh
#   - Changes committed and tagged (v1.2.3)
#   - gh CLI authenticated
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/Airbridge/app/build.gradle.kts"

# Read version from gradle
VERSION=$(grep 'versionName' "$GRADLE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
TAG="v$VERSION"

echo "=== Building Airbridge $TAG ==="
echo ""

# Check tag exists
if ! git tag -l "$TAG" | grep -q "$TAG"; then
    echo "Error: Tag $TAG not found. Run bump-version.sh first, commit, and tag."
    exit 1
fi

# 1. Build macOS
echo "--- Building macOS ---"
cd "$ROOT/macos/Airbridge"
swift build -c release 2>&1 | grep "error:" && { echo "  macOS build FAILED"; exit 1; } || true
echo "  macOS build succeeded"
MACOS_BIN="$ROOT/macos/Airbridge/.build/arm64-apple-macosx/release/AirbridgeApp"

# Build app bundle from scratch
APP_BUNDLE="$HOME/Applications/Airbridge.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$MACOS_BIN" "$APP_BUNDLE/Contents/MacOS/AirbridgeApp"
cp "$ROOT/macos/Airbridge/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Copy SPM resource bundle (required by Bundle.module)
RES_BUNDLE="$ROOT/macos/Airbridge/.build/arm64-apple-macosx/release/Airbridge_AirbridgeApp.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP_BUNDLE/Contents/Resources/Airbridge_AirbridgeApp.bundle"
else
    echo "  WARNING: Resource bundle not found at $RES_BUNDLE"
    exit 1
fi

# Copy icon
ICNS="$ROOT/macos/Airbridge/Sources/AirbridgeApp/Resources/AppIcon.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code sign so Gatekeeper doesn't show prohibition icon
codesign --force --deep --sign - "$APP_BUNDLE"
echo "  App bundle: $APP_BUNDLE"

# Create DMG with Applications symlink and compact window
DMG_PATH="$ROOT/Airbridge.dmg"
DMG_STAGE="$ROOT/.dmg-stage"
rm -rf "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/Airbridge.app"
ln -s /Applications "$DMG_STAGE/Applications"

# Set Finder window size and icon layout via .DS_Store
# Create a temporary read-write DMG first to set view options
DMG_RW="$ROOT/.dmg-rw.dmg"
rm -f "$DMG_RW"
hdiutil create -volname "Airbridge" -srcfolder "$DMG_STAGE" -ov -format UDRW "$DMG_RW" > /dev/null 2>&1
MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen 2>/dev/null | grep "/Volumes/Airbridge" | tail -1 | awk '{print $NF}')

if [ -n "$MOUNT_DIR" ]; then
    # Use AppleScript to set Finder view options
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "Airbridge"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {300, 200, 750, 470}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "Airbridge.app" of container window to {110, 120}
        set position of item "Applications" of container window to {340, 120}
        close
    end tell
end tell
APPLESCRIPT
    sync
    hdiutil detach "$MOUNT_DIR" > /dev/null 2>&1
fi

hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH" > /dev/null 2>&1
rm -f "$DMG_RW"
rm -rf "$DMG_STAGE"
echo "  DMG: $DMG_PATH"

# 2. Build Android
echo "--- Building Android ---"
cd "$ROOT/android/Airbridge"
./gradlew assembleRelease 2>&1 | tail -3

APK_RELEASE="$ROOT/android/Airbridge/app/build/outputs/apk/release/app-release.apk"
APK_DEBUG="$ROOT/android/Airbridge/app/build/outputs/apk/debug/app-debug.apk"

# Use release APK if available, otherwise debug
if [ -f "$APK_RELEASE" ]; then
    APK_PATH="$APK_RELEASE"
else
    echo "  Release APK not found (needs signing), building debug..."
    ./gradlew assembleDebug 2>&1 | tail -3
    APK_PATH="$APK_DEBUG"
fi

# Copy to root
cp "$APK_PATH" "$ROOT/Airbridge.apk"
echo "  APK: $ROOT/Airbridge.apk"

# 3. Create GitHub release
echo ""
echo "--- Creating GitHub Release $TAG ---"

NOTES="$(cat <<EOF
## Airbridge $TAG

### Downloads
- **macOS**: Airbridge.dmg
- **Android**: Airbridge.apk

### Changes since last release
$(git log --oneline v1.0.0..HEAD --no-decorate 2>/dev/null || git log --oneline -10 --no-decorate)
EOF
)"

gh release create "$TAG" \
    --title "Airbridge $TAG" \
    --notes "$NOTES" \
    "$ROOT/Airbridge.dmg#Airbridge.dmg" \
    "$ROOT/Airbridge.apk#Airbridge.apk"

echo ""
echo "=== Release $TAG published ==="
echo "https://github.com/negativepl/airbridge/releases/tag/$TAG"
