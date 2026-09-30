#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh

swift test ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} "$@"
