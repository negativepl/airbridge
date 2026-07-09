#!/bin/bash
# gen-update-keys.sh — one-time Ed25519 key pair for update-manifest signing.
set -euo pipefail
KEY="$HOME/.airbridge/update-signing.pem"
if [ -f "$KEY" ]; then echo "Key already exists: $KEY"; else
    mkdir -p "$(dirname "$KEY")"
    openssl genpkey -algorithm ed25519 -out "$KEY"
    chmod 600 "$KEY"
    echo "Private key written to $KEY (backup it like the keystore!)"
fi
echo "Public key (base64, embed in UpdateChecker.kt / UpdateService.swift):"
openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64
