#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
APP="packaging/Pesty.app"

echo "==> Building universal release binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Pesty"
echo "    binary: $BIN"

echo "==> Generating icon"
bash scripts/make_icon.sh >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pesty"
cp packaging/Pesty.icns "$APP/Contents/Resources/Pesty.icns"

# Copy localization resources into the app bundle
for lproj in Sources/Pesty/Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
done

# Copy SPM resource bundle if it exists (for Bundle.module fallback)
SPM_BUNDLE="$(dirname "$BIN")/Pesty_Pesty.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$APP/Contents/Resources/"
fi

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Explicitly sign the assembled bundle with a stable designated requirement.
# Without this, each release build only carries Swift's per-binary linker
# signature (a changing CDHash), which makes macOS ask for Accessibility again.
echo "==> Signing $APP"
/usr/bin/codesign --force --sign - --identifier com.greycorelabs.pesty \
  -r='designated => identifier "com.greycorelabs.pesty"' "$APP"

echo "==> Built $APP"
/usr/bin/file "$APP/Contents/MacOS/Pesty"
echo "    version $VERSION ($BUILD)"
