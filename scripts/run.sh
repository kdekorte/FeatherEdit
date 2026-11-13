#!/bin/bash
# Build (if needed) and run FeatherEdit. Extra arguments are treated as
# file paths to open, e.g. scripts/run.sh notes.txt
set -euo pipefail
cd "$(dirname "$0")/.."

swift run FeatherEdit "$@"
