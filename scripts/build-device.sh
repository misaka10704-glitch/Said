#!/bin/bash
# Build Said for a physical device (iPhone or iPad route). Same sources, iOS 12+.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTE="${1:-ipad}"
CONFIG="${2:-Debug}"
DERIVED="${DERIVED_DATA_PATH:-/tmp/Said-${ROUTE}-Derived}"

case "$(echo "$ROUTE" | tr '[:upper:]' '[:lower:]')" in
  iphone|phone|1)
    SCHEME="Said-iPhone"
    ;;
  ipad|pad|2)
    SCHEME="Said-iPad"
    ;;
  *)
    echo "Usage: $0 [iphone|ipad] [Debug|Release]" >&2
    exit 1
    ;;
esac

cd "$ROOT"
xcodebuild \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$DERIVED/Build/Products/${CONFIG}-iphoneos/Said.app"
echo ""
echo "Built: $APP"
echo "Scheme: $SCHEME  Configuration: $CONFIG  MinimumOS: 12.0"
