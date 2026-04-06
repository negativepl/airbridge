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
swift build -c release 2>&1 | tail -3
MACOS_BIN="$ROOT/macos/Airbridge/.build/arm64-apple-macosx/release/AirbridgeApp"

# Copy to app bundle
APP_BUNDLE="$HOME/Applications/Airbridge.app"
if [ -d "$APP_BUNDLE" ]; then
    cp "$MACOS_BIN" "$APP_BUNDLE/Contents/MacOS/AirbridgeApp"
    # Update Info.plist version
    PLIST="$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi

# Create DMG
DMG_PATH="$ROOT/Airbridge.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "Airbridge" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH" > /dev/null 2>&1
echo "  DMG: $DMG_PATH"

# 2. Build Android
echo "--- Building Android ---"
cd "$ROOT/android/Airbridge"
./gradlew assembleRelease 2>&1 | tail -3

APK_RELEASE="$ROOT/android/Airbridge/app/build/outputs/apk/release/app-release-unsigned.apk"
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
$(git log --oneline $(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "HEAD~10")..HEAD --no-decorate)
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
