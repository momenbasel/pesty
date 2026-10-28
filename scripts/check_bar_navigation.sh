#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Compile the actual application views with a fixture entry point in place of
# Main.swift. The app delegate/clipboard monitor are never started.
probe_directory="$(mktemp -d "${TMPDIR:-/tmp}/pesty-navigation.XXXXXX")"
trap 'rm -rf "$probe_directory"' EXIT
mkdir "$probe_directory/home"
touch "$probe_directory/home/.pesty-fixture"

probe_sources=()
while IFS= read -r -d '' source; do
  probe_sources+=("$source")
done < <(find Sources/Pesty -type f -name '*.swift' ! -path 'Sources/Pesty/Main.swift' -print0)

xcrun swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$probe_directory/module-cache" \
  "${probe_sources[@]}" Tests/InteractionProbe/BarNavigationProbe.swift \
  -o "$probe_directory/PestyBarNavigationProbe"

CFFIXED_USER_HOME="$probe_directory/home" "$probe_directory/PestyBarNavigationProbe"
