#!/bin/bash
# dev-install.sh — Debug build + replace binary in ~/Applications/Airbridge.app + relaunch
#
# Uses existing .app bundle structure created by release.sh. Fast iteration for UI work.
# Does NOT recreate the full bundle or re-sign — only replaces the binary and resource bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/macos/Airbridge"

echo "--- swift build ---"
swift build 2>&1 | tee /tmp/airbridge-build.log | grep -E "error:|warning:" | head -40 || true

if grep -q "error:" /tmp/airbridge-build.log; then
    echo "BUILD FAILED — see /tmp/airbridge-build.log"
    exit 1
fi

APP="$HOME/Applications/Airbridge.app"
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

echo "--- re-signing (ad-hoc) ---"
codesign --force --deep --sign - "$APP" 2>&1 | tail -5

echo "--- launching ---"
open "$APP"
echo "✓ Airbridge running from debug build"
