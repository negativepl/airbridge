#!/bin/bash
# dev-install.sh — Debug build + replace binary in ~/Applications/AirBridge.app + relaunch
#
# Uses existing .app bundle structure created by release.sh. Fast iteration for UI work.
# Does NOT recreate the full bundle or re-sign — only replaces the binary and resource bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/macos/Airbridge"

echo "--- swift build ---"
swift build 2>&1 | tee /tmp/airbridge-build.log | grep -E ": (error|warning):" | head -40 || true

if grep -qE ': error:' /tmp/airbridge-build.log; then
    echo "BUILD FAILED — see /tmp/airbridge-build.log"
    exit 1
fi

APP="$HOME/Applications/AirBridge.app"
if [ ! -d "$APP" ]; then
    echo "ERROR: $APP doesn't exist — run scripts/release.sh once to create it"
    exit 1
fi

echo "--- killing running instance ---"
killall AirbridgeApp 2>/dev/null || true
sleep 0.3

echo "--- copying binary ---"
cp .build/debug/AirbridgeApp "$APP/Contents/MacOS/AirbridgeApp"

RES_BUNDLE=".build/debug/Airbridge_AirbridgeApp.bundle"
if [ -d "$RES_BUNDLE" ]; then
    rm -rf "$APP/Contents/Resources/Airbridge_AirbridgeApp.bundle"
    cp -R "$RES_BUNDLE" "$APP/Contents/Resources/Airbridge_AirbridgeApp.bundle"
fi

# Copy updated Info.plist (picks up CFBundleDevelopmentRegion / localization changes)
cp "$ROOT/macos/Airbridge/Resources/Info.plist" "$APP/Contents/Info.plist"

# Copy .lproj localization folders — AppKit uses their presence to pick the
# language for system menu items (Services, Hide, Quit, Edit, View, Window,
# Help). Without these, AppKit falls back to English regardless of
# CFBundleDevelopmentRegion.
for LPROJ in "$ROOT/macos/Airbridge/Resources"/*.lproj; do
    if [ -d "$LPROJ" ]; then
        NAME=$(basename "$LPROJ")
        rm -rf "$APP/Contents/Resources/$NAME"
        cp -R "$LPROJ" "$APP/Contents/Resources/$NAME"
    fi
done

echo "--- re-signing (ad-hoc) ---"
codesign --force --deep --sign - "$APP" 2>&1 | tail -5

echo "--- launching ---"
open "$APP"
echo "✓ AirBridge running from debug build"
