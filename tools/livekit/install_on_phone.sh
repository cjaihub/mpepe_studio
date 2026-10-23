#!/usr/bin/env bash
# Waits for the USB phone, installs the latest Live Studio test build in place,
# recreates the adb reverse tunnels and opens Oneova.
#   bash tools/livekit/install_on_phone.sh [apk]
set -euo pipefail
cd "$(dirname "$0")/../.."
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
APK="${1:-build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk}"
[ -f "$APK" ] || { echo "No APK at $APK"; exit 1; }

echo "Waiting for the phone (plug it in, unlock it, allow USB debugging)…"
"$ADB" wait-for-device
SERIAL=$("$ADB" get-serialno)
echo "Phone: $SERIAL"

"$ADB" install -r "$APK"
for p in 9099 8080 5001 7880 7881; do "$ADB" reverse "tcp:$p" "tcp:$p" >/dev/null; done
"$ADB" reverse --list
"$ADB" logcat -c
"$ADB" shell monkey -p com.oneova.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 15
"$ADB" logcat -d | grep -E "\[Emulators\]|FATAL|E flutter" | head -5 || true
echo "Installed and launched."
