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

echo "=== Building AirBridge $TAG ==="
echo ""

# Check tag exists
if ! git tag -l "$TAG" | grep -q "$TAG"; then
    echo "Error: Tag $TAG not found. Run bump-version.sh first, commit, and tag."
    exit 1
fi

# 1. Build macOS
echo "--- Building macOS ---"
cd "$ROOT/macos/Airbridge"
BUILD_LOG="$(mktemp -t airbridge-macos-build)"
if ! swift build -c release > "$BUILD_LOG" 2>&1; then
    echo "  macOS build FAILED — last 30 lines of $BUILD_LOG:"
    tail -30 "$BUILD_LOG"
    exit 1
fi
rm -f "$BUILD_LOG"
echo "  macOS build succeeded"
MACOS_BIN="$ROOT/macos/Airbridge/.build/arm64-apple-macosx/release/AirbridgeApp"

# Build app bundle from scratch
APP_BUNDLE="$HOME/Applications/AirBridge.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$MACOS_BIN" "$APP_BUNDLE/Contents/MacOS/AirbridgeApp"
cp "$ROOT/macos/Airbridge/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Copy SPM resources directly into Contents/Resources. We avoid SwiftPM's
# Bundle.module accessor (its generated fallback path is hardcoded to the
# developer's .build/ directory, which crashes on any other Mac). Code in
# AirbridgeApp uses AppResources.bundle = Bundle.main instead.
RES_SRC="$ROOT/macos/Airbridge/Sources/AirbridgeApp/Resources"
if [ ! -d "$RES_SRC" ]; then
    echo "  ERROR: Resources not found at $RES_SRC"
    exit 1
fi
cp -R "$RES_SRC"/* "$APP_BUNDLE/Contents/Resources/"

# Copy .lproj localization folders so AppKit shows system menu items in the
# user's language (requires CFBundleDevelopmentRegion + matching .lproj dirs).
for LPROJ in "$ROOT/macos/Airbridge/Resources"/*.lproj; do
    if [ -d "$LPROJ" ]; then
        cp -R "$LPROJ" "$APP_BUNDLE/Contents/Resources/"
    fi
done

# Sign with the stable self-signed identity (NOT ad-hoc) so the bundle's
# designated requirement is derived from the cert and stays constant across
# releases. That lets macOS TCC keep the Accessibility grant across app updates
# instead of dropping it every version (which ad-hoc's cdhash-based requirement
# did). First launch on a new Mac still needs right-click → Open (unidentified
# developer); updates afterwards are friction-free.
"$ROOT/scripts/setup-signing-cert.sh"
codesign --force --deep --sign "AirBridge Signing" "$APP_BUNDLE"
echo "  App bundle: $APP_BUNDLE (signed: AirBridge Signing)"

# Create DMG with Applications symlink and compact window
DMG_PATH="$ROOT/AirBridge.dmg"
DMG_STAGE="$ROOT/.dmg-stage"
rm -rf "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/AirBridge.app"
ln -s /Applications "$DMG_STAGE/Applications"

# Set Finder window size and icon layout via .DS_Store
# Create a temporary read-write DMG first to set view options
DMG_RW="$ROOT/.dmg-rw.dmg"
rm -f "$DMG_RW"
hdiutil create -volname "AirBridge" -srcfolder "$DMG_STAGE" -ov -format UDRW "$DMG_RW" > /dev/null 2>&1
MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen 2>/dev/null | grep "/Volumes/AirBridge" | tail -1 | awk '{print $NF}')

if [ -n "$MOUNT_DIR" ]; then
    # Use AppleScript to set Finder view options
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "AirBridge"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {300, 200, 750, 470}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "AirBridge.app" of container window to {110, 120}
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
cp "$APK_PATH" "$ROOT/AirBridge.apk"
echo "  APK: $ROOT/AirBridge.apk"

# 3. Create GitHub release
echo ""
echo "--- Creating GitHub Release $TAG ---"

# Changelog base: the tag immediately preceding $TAG; fall back to the last
# 10 commits when there is no earlier tag.
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
if [ -n "$PREV_TAG" ]; then
    CHANGELOG="$(git log --oneline "$PREV_TAG..$TAG" --no-decorate)"
else
    CHANGELOG="$(git log --oneline -10 --no-decorate "$TAG")"
fi

NOTES="$(cat <<EOF
## AirBridge $TAG

### Downloads
- **macOS**: AirBridge.dmg
- **Android**: AirBridge.apk

### Changes since last release
$CHANGELOG
EOF
)"

gh release create "$TAG" \
    --title "AirBridge $TAG" \
    --notes "$NOTES" \
    "$ROOT/AirBridge.dmg#AirBridge.dmg" \
    "$ROOT/AirBridge.apk#AirBridge.apk"

echo ""
echo "=== Release $TAG published ==="
echo "https://github.com/negativepl/airbridge/releases/tag/$TAG"
