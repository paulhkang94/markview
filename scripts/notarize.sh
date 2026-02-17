#!/bin/bash
set -euo pipefail

# MarkView — Notarize a signed .app bundle
# Usage: bash scripts/notarize.sh /path/to/MarkView.app
#
# Required env vars:
#   NOTARIZE_KEY_ID    — App Store Connect API Key ID
#   NOTARIZE_ISSUER_ID — App Store Connect Issuer ID
#   NOTARIZE_KEY_PATH  — Path to .p8 key file (default: ~/.private_keys/AuthKey_${NOTARIZE_KEY_ID}.p8)

APP_PATH="${1:?Usage: bash scripts/notarize.sh /path/to/MarkView.app}"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH does not exist"
    exit 1
fi

# Validate env vars
: "${NOTARIZE_KEY_ID:?Set NOTARIZE_KEY_ID to your App Store Connect API Key ID}"
: "${NOTARIZE_ISSUER_ID:?Set NOTARIZE_ISSUER_ID to your App Store Connect Issuer ID}"
NOTARIZE_KEY_PATH="${NOTARIZE_KEY_PATH:-$HOME/.private_keys/AuthKey_${NOTARIZE_KEY_ID}.p8}"

if [ ! -f "$NOTARIZE_KEY_PATH" ]; then
    echo "ERROR: Key file not found at $NOTARIZE_KEY_PATH"
    echo "Download from App Store Connect → Users & Access → Integrations → Keys"
    exit 1
fi

APP_NAME=$(basename "$APP_PATH" .app)
ZIP_PATH="/tmp/${APP_NAME}-notarize.zip"

# Step 1: Zip the .app for submission
echo "--- Zipping $APP_PATH for notarization ---"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# Step 2: Submit to Apple notary service
echo ""
echo "--- Submitting to Apple notary service ---"
xcrun notarytool submit "$ZIP_PATH" \
    --key "$NOTARIZE_KEY_PATH" \
    --key-id "$NOTARIZE_KEY_ID" \
    --issuer "$NOTARIZE_ISSUER_ID" \
    --wait

# Step 3: Staple the notarization ticket
echo ""
echo "--- Stapling notarization ticket ---"
xcrun stapler staple "$APP_PATH"

# Clean up
rm -f "$ZIP_PATH"

echo ""
echo "=== Notarization complete ==="
echo "Verify with: stapler validate $APP_PATH"
