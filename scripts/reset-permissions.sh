#!/bin/bash
# reset-permissions.sh — Reset ALL macOS TCC permissions for AirBridge.
#
# Use this to test the onboarding / permissions flow from a clean slate:
# Accessibility (Quick Drop + phone control), Screen Recording, Notifications,
# Local Network — all reset in one shot.
#
# NOTE: with the stable signing cert (scripts/setup-signing-cert.sh) the
# Accessibility grant now survives rebuilds and updates, so you rarely need this.
# Run it only when you deliberately want to re-test the granting flow — a normal
# rebuild via dev-install.sh does NOT require a reset anymore.
#
# Optional: pass --android to also wipe the Android app's data (clears pairing
# keys + its accessibility grant) on every connected device.
set -euo pipefail

BUNDLE_ID="com.airbridge.macos"

echo "--- quitting AirBridge ---"
killall AirbridgeApp 2>/dev/null || true
sleep 0.3

echo "--- resetting all TCC permissions for $BUNDLE_ID ---"
# `All` covers every service (Accessibility, ScreenCapture, Notifications,
# LocalNetwork, …) granted to this bundle id. tccutil works without sudo for the
# current user.
tccutil reset All "$BUNDLE_ID"

if [ "${1:-}" = "--android" ]; then
    echo "--- clearing Android app data on connected devices ---"
    for DEV in $(adb devices | awk 'NR>1 && $2=="device" {print $1}'); do
        echo "  $DEV"
        adb -s "$DEV" shell pm clear com.airbridge || true
    done
fi

echo "✓ Done. Relaunch AirBridge and re-grant permissions to test the flow."
