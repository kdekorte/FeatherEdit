#!/bin/bash
# Build FeatherEdit (debug by default, release with --release).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
fi

swift build -c "$CONFIG"
echo "Built .build/$CONFIG/FeatherEdit"
