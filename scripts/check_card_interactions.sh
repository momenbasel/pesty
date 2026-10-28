#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# This probe opens its own window and posts events only to that window.
# It uses fixture callbacks, never the clipboard store or paste service.
probe_directory="$(mktemp -d "${TMPDIR:-/tmp}/pesty-interactions.XXXXXX")"
trap 'rm -rf "$probe_directory"' EXIT

xcrun swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$probe_directory/module-cache" \
  Sources/Pesty/UI/ClipCardInteractions.swift \
  Tests/InteractionProbe/CardInteractionProbe.swift \
  -o "$probe_directory/PestyInteractionProbe"

"$probe_directory/PestyInteractionProbe"
