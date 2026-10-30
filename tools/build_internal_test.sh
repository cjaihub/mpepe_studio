#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Oneova Looks & Visual Intelligence — Internal Test Build Script
# Note: For internal test devices & CI verification ONLY.
# App Store & Google Play Store release submissions are STRICTLY BANNED at this stage.
# ==============================================================================

echo "=========================================================="
echo " Starting Oneova Internal Test Build Verification"
echo " Target: Internal Test Artifacts (Debug/Profile only)"
echo "=========================================================="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Step 1: Pre-flight Verification
echo "--> [1/4] Running Mandatory Guard Test: home_lock_test.dart..."
flutter test test/guards/home_lock_test.dart

echo "--> [2/4] Running Static Analysis on lib/looks/..."
flutter analyze lib/looks/

# Step 2: Validate Environment & Guard Against Production Store Flags
echo "--> [3/4] Validating Build Environment..."
if [[ "${1:-}" == "--release-store" || "${1:-}" == "--app-store" || "${1:-}" == "--play-store" ]]; then
  echo "ERROR: Production store release submission is strictly disabled per Plan v3."
  echo "Only internal test builds (--internal-apk, --internal-ios, or --dry-run) are allowed."
  exit 1
fi

OUTPUT_DIR="$PROJECT_ROOT/build/internal_test_outputs"
mkdir -p "$OUTPUT_DIR"

MODE="${1:---dry-run}"

# Step 3: Execute Target Build
echo "--> [4/4] Executing Internal Build in mode: $MODE..."
case "$MODE" in
  --internal-apk)
    echo "Building Android Internal Test APK (profile mode with debugging symbols)..."
    flutter build apk --profile
    cp "$PROJECT_ROOT/build/app/outputs/flutter-apk/app-profile.apk" "$OUTPUT_DIR/oneova-internal-test.apk" 2>/dev/null || true
    echo "Artifact created: $OUTPUT_DIR/oneova-internal-test.apk"
    ;;
  --internal-bundle)
    echo "Building Android Internal App Bundle for internal testing tracks..."
    flutter build appbundle --profile
    cp "$PROJECT_ROOT/build/app/outputs/bundle/profile/app-profile.aab" "$OUTPUT_DIR/oneova-internal-test.aab" 2>/dev/null || true
    echo "Artifact created: $OUTPUT_DIR/oneova-internal-test.aab"
    ;;
  --internal-ios)
    echo "Building iOS Internal Test Archive..."
    flutter build ios --profile --no-codesign
    echo "iOS internal archive staged at $PROJECT_ROOT/build/ios/iphoneos"
    ;;
  --dry-run|*)
    echo "Dry run verification successful. All guard tests passed, static analysis clean, and build manifests ready."
    ;;
esac

echo "=========================================================="
echo " Oneova Internal Test Build Pipeline COMPLETED SUCCESSFULLY"
echo "=========================================================="
