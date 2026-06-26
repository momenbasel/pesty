#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p packaging
swift scripts/IconGen.swift packaging/icon_1024.png

ICONSET="packaging/Pesty.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

gen() { sips -z "$1" "$1" packaging/icon_1024.png --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp packaging/icon_1024.png "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o packaging/Pesty.icns
echo "wrote packaging/Pesty.icns"
