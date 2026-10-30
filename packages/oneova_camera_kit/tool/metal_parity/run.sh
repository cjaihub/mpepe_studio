#!/bin/bash
# Compares the plugin's Metal path against Flutter-path fixtures (macOS only).
#   ONEOVA_PARITY_OUT=/tmp/parity flutter test test/looks/native_parity_fixtures_test.dart
#   packages/oneova_camera_kit/tool/metal_parity/run.sh /tmp/parity
set -euo pipefail
if [ $# -ne 1 ]; then
  echo "usage: $0 <fixtures dir>" >&2
  exit 2
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSES="$DIR/../../ios/Classes"
BIN="$(mktemp -d)/metal_parity"
xcrun swiftc -O "$DIR/main.swift" \
  "$CLASSES/LookMetalPipeline.swift" \
  "$CLASSES/LookEngineShader.swift" \
  "$CLASSES/LookPassesShader.swift" \
  "$CLASSES/LookModels.swift" \
  -o "$BIN"
"$BIN" "$1"
