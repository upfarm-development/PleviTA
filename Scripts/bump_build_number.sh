#!/bin/bash
# Increments CURRENT_PROJECT_VERSION (the build number) in Config/Base.xcconfig by 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCCONFIG="$SCRIPT_DIR/../Config/Base.xcconfig"

if [ ! -f "$XCCONFIG" ]; then
  echo "error: $XCCONFIG not found" >&2
  exit 1
fi

current="$(grep -E '^CURRENT_PROJECT_VERSION = [0-9]+$' "$XCCONFIG" | grep -oE '[0-9]+$' || true)"
if [ -z "$current" ]; then
  echo "error: could not find a 'CURRENT_PROJECT_VERSION = <int>' line in $XCCONFIG" >&2
  exit 1
fi

next=$((current + 1))
sed -i '' -E "s/^CURRENT_PROJECT_VERSION = [0-9]+\$/CURRENT_PROJECT_VERSION = ${next}/" "$XCCONFIG"

echo "Build number bumped: ${current} -> ${next}"
