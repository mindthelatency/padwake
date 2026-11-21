#!/usr/bin/env bash
set -euo pipefail

# Production release pipeline: Universal Binary -> Developer ID Hardened Runtime -> DMG -> Apple Notarization -> Staple
#
# Prerequisites (one-time setup):
#   1. Apple Developer Program ($99/yr) + "Developer ID Application" cert in Keychain
#      Find your exact identity string with:
#        security find-identity -v -p codesigning
#   2. Store notarytool credentials in Keychain:
#        xcrun notarytool store-credentials "padwake-notary" \
#          --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-password"
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="padwake-notary" \
#   ./scripts/sign-and-notarize.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-PadWake}"
VERSION="${VERSION:-1.4.0}"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$DEVELOPER_ID" ]]; then
    echo "Error: DEVELOPER_ID env var is required." >&2
    echo "Find yours with: security find-identity -v -p codesigning" >&2
    exit 1
fi

BUILD_DIR="$REPO_DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
DMG_STAGE="$BUILD_DIR/dmg-stage"
DMG_OUT="$BUILD_DIR/${APP_NAME}-${VERSION}-macOS.dmg"

echo "[release] Building Universal Binary (${APP_NAME} ${VERSION})..."
UNIVERSAL=1 SKIP_ADHOC_SIGN=1 "$REPO_DIR/scripts/build-app.sh"

echo "[release] Signing with Developer ID + Hardened Runtime..."
codesign --force --options runtime --timestamp \
    --entitlements "$REPO_DIR/app/PadWake.entitlements" \
    --sign "$DEVELOPER_ID" \
    "$APP_BUNDLE"

echo "[release] Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "[release] Packaging drag-to-Applications DMG..."
rm -rf "$DMG_STAGE" "$DMG_OUT" "${DMG_OUT}.sha256"
mkdir -p "$DMG_STAGE"
ditto "$APP_BUNDLE" "$DMG_STAGE/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_OUT" >/dev/null
rm -rf "$DMG_STAGE"

codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_OUT"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "[release] Submitting DMG to Apple Notary Service (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DMG_OUT" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "[release] Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_OUT"
    xcrun stapler validate "$DMG_OUT"

    echo "[release] Checking Gatekeeper assessment..."
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_OUT"
fi

(cd "$BUILD_DIR" && shasum -a 256 "$(basename "$DMG_OUT")" > "$(basename "$DMG_OUT").sha256")
echo "[release] SHA-256 written to ${DMG_OUT}.sha256"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "[release] DONE! Notarized release ready: $DMG_OUT"
else
    echo "[release] Signed DMG created (NOTARIZATION SKIPPED because NOTARY_PROFILE was unset): $DMG_OUT"
    echo "[release] To notarize, re-run with NOTARY_PROFILE=<keychain-profile>."
fi
