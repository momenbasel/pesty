#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-1.0.0}"
export BUILD="${BUILD:-1}"
bash scripts/build_app.sh
bash scripts/sign_notarize.sh
echo "RELEASE_BUILD_DONE"
