#!/usr/bin/env bash
# Waits for the USB phone, installs the latest Live Studio test build in place,
# recreates the adb reverse tunnels and opens Oneova.
#   bash tools/livekit/install_on_phone.sh [apk]
set -euo pipefail
cd "$(dirname "$0")/../.."
ADB0="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
# Target one phone by serial when several devices (e.g. an emulator) are attached.
SERIAL="${SERIAL:-119722543M014078}"
ADB() { "$ADB0" -s "$SERIAL" "$@"; }
APK="${1:-build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk}"
[ -f "$APK" ] || { echo "No APK at $APK"; exit 1; }

echo "Waiting for phone $SERIAL (plug it in, unlock it, allow USB debugging)…"
until "$ADB0" devices | grep -q "^${SERIAL}[[:space:]]*device"; do sleep 5; done
echo "Phone: $SERIAL"

ADB install -r "$APK"
for p in 9099 8080 5001 7880 7881; do ADB reverse "tcp:$p" "tcp:$p" >/dev/null; done
ADB reverse --list
ADB logcat -c
ADB shell monkey -p com.oneova.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 15
ADB logcat -d | grep -E "\[Emulators\]|FATAL|E flutter" | head -5 || true
echo "Installed and launched."
