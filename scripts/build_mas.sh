#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.1.0}"
BUILD="${BUILD:-5}"
APP="packaging/Pesty.app"
PKG="packaging/Pesty-MAS-$VERSION.pkg"
ENT="packaging/Pesty-MAS.entitlements"
PROFILE="${PROFILE:-packaging/Pesty_MAS.provisionprofile}"
APP_IDENTITY="${APP_IDENTITY:-Apple Distribution: Moamen Basel (H3WXHVTP97)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: Moamen Basel (H3WXHVTP97)}"

[ -f "$PROFILE" ] || { echo "Missing provisioning profile at $PROFILE"; exit 1; }

echo "==> Building universal release binary (sandboxed, no Accessibility — MAS flag)"
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -DMAS
BIN="$(swift build -c release --arch arm64 --arch x86_64 -Xswiftc -DMAS --show-bin-path)/Pesty"
bash scripts/make_icon.sh >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pesty"
cp packaging/Pesty.icns "$APP/Contents/Resources/Pesty.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

echo "==> Signing for the Mac App Store (sandboxed)"
codesign --force --timestamp --entitlements "$ENT" --sign "$APP_IDENTITY" "$APP/Contents/MacOS/Pesty"
codesign --force --timestamp --entitlements "$ENT" --sign "$APP_IDENTITY" "$APP"

echo "==> Building signed installer package"
rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"

echo "==> Verification"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- sandbox entitlement ---"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -A1 "app-sandbox" || \
  codesign -d --entitlements - "$APP" 2>/dev/null | plutil -p - 2>/dev/null | grep -i sandbox || true
echo "--- pkg signature ---"
pkgutil --check-signature "$PKG" | head -8
echo "==> Done: $PKG"
