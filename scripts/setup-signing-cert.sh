#!/bin/bash
# setup-signing-cert.sh — Ensure the stable self-signed code-signing identity exists.
#
# Why: ad-hoc signing (`codesign --sign -`) gives every build a fresh cdhash, and
# macOS TCC ties the Accessibility grant to that cdhash for ad-hoc code. Result:
# every app update drops the grant and the user must re-enable Accessibility.
#
# A stable self-signed certificate fixes this. codesign derives the bundle's
# designated requirement from the signing cert:
#
#   designated => identifier "com.airbridge.macos" and certificate leaf = H"<cert hash>"
#
# That requirement is identical across builds (same cert), so TCC keeps the grant
# across updates. Gatekeeper still shows "unidentified developer" on FIRST launch
# (right-click → Open once); updates after that are friction-free.
#
# This script is idempotent: it's safe to run from dev-install.sh / release.sh.
set -euo pipefail

SIGN_ID="AirBridge Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
BACKUP="$HOME/.airbridge/airbridge-signing.p12"
PASS_FILE="$HOME/.airbridge/airbridge-signing.pass"

# The p12 password lives OUTSIDE the repo (this is a public repo). It's read from
# PASS_FILE, generated on first run if missing. The real secret is the .p12 key
# itself — guard ~/.airbridge, never commit it, never sync it to the cloud:
# anyone with that key can sign an app that inherits AirBridge's Accessibility grant.
p12_pass() {
    if [ ! -f "$PASS_FILE" ]; then
        mkdir -p "$(dirname "$PASS_FILE")"
        openssl rand -hex 24 > "$PASS_FILE"
        chmod 600 "$PASS_FILE"
    fi
    cat "$PASS_FILE"
}

# Already in the keychain? Nothing to do.
if security find-certificate -c "$SIGN_ID" "$KEYCHAIN" >/dev/null 2>&1; then
    exit 0
fi

# Restore from backup if we have one (e.g. fresh machine, same cert → same DR).
if [ -f "$BACKUP" ]; then
    echo "--- importing signing identity '$SIGN_ID' from $BACKUP ---"
    security import "$BACKUP" -k "$KEYCHAIN" -P "$(p12_pass)" -T /usr/bin/codesign
    exit 0
fi

# Otherwise create a fresh one. NOTE: a new cert means a NEW designated
# requirement, so any existing TCC grants for older builds will NOT carry over —
# users re-grant Accessibility once. Keep the backup so this only happens once.
echo "--- creating new self-signed signing identity '$SIGN_ID' ---"
PASS="$(p12_pass)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -nodes \
    -subj "/CN=$SIGN_ID" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
# -legacy: macOS `security` can't read PKCS12 produced by OpenSSL 3's default algos.
openssl pkcs12 -export -legacy -out "$WORK/cert.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$SIGN_ID" -passout "pass:$PASS" 2>/dev/null
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
mkdir -p "$(dirname "$BACKUP")"
cp "$WORK/cert.p12" "$BACKUP"
chmod 600 "$BACKUP"
echo "--- backed up to $BACKUP (password in $PASS_FILE) — keep BOTH to sign on other machines ---"
