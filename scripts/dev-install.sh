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

# Copy resources directly into Contents/Resources. Code uses
# AppResources.bundle = Bundle.main, not SwiftPM's Bundle.module.
RES_SRC="$ROOT/macos/Airbridge/Sources/AirbridgeApp/Resources"
if [ -d "$RES_SRC" ]; then
    rm -rf "$APP/Airbridge_AirbridgeApp.bundle" "$APP/Contents/Resources/Airbridge_AirbridgeApp.bundle"
    cp -R "$RES_SRC"/* "$APP/Contents/Resources/"
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

# Sign with the stable self-signed identity (NOT ad-hoc). The designated
# requirement is derived from the cert, so it stays identical across builds and
# the TCC Accessibility grant survives rebuilds — no more re-granting each time.
echo "--- ensuring signing identity ---"
"$ROOT/scripts/setup-signing-cert.sh"
echo "--- re-signing ('AirBridge Signing') ---"
codesign --force --deep --sign "AirBridge Signing" "$APP" 2>&1 | tail -5

echo "--- launching ---"
open "$APP"
echo "✓ AirBridge running from debug build"
