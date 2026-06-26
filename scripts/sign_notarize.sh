#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="packaging/Pesty.app"
DMG="packaging/Pesty-$VERSION.dmg"
ENTITLEMENTS="packaging/Pesty.entitlements"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Moamen Basel (H3WXHVTP97)}"
ASC_KEY="${ASC_KEY:-$HOME/.appstoreconnect/private_keys/AuthKey_5G7R52L8RK.p8}"
ASC_KEY_ID="${ASC_KEY_ID:-5G7R52L8RK}"
ASC_ISSUER="${ASC_ISSUER:-5de3898a-cd31-4061-850f-ae17b389e46a}"

[ -d "$APP" ] || { echo "Missing $APP — run build_app.sh first"; exit 1; }

echo "==> Codesigning app (hardened runtime)"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP/Contents/MacOS/Pesty"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Notarizing app"
ZIP="packaging/Pesty.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
    --key "$ASC_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
    --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> Building DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Pesty.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pesty" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Signing + notarizing DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" \
    --key "$ASC_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
    --wait
xcrun stapler staple "$DMG"

echo "==> Gatekeeper assessment"
spctl -a -vvv -t install "$DMG" || true
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" || true

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
