#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Oneova Direct Wireless Debugging Pairing & Auto-Installer
# Usage: ./tools/pair_phone.sh <IP:PAIR_PORT> <6_DIGIT_CODE> [CONNECT_PORT]
# Example: ./tools/pair_phone.sh 192.168.1.100:38472 123456 41235
# ==============================================================================

ADB="/Users/imac/Library/Android/sdk/platform-tools/adb"
APK="/Users/imac/Music/MPEPE STUDIO/build/app/outputs/flutter-apk/app-debug.apk"
PACKAGE="com.oneova.app"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <IP:PAIRING_PORT> <PAIRING_CODE> [CONNECT_PORT]"
  echo "Example: $0 192.168.1.45:41235 654321"
  exit 1
fi

PAIR_ADDRESS="$1"
PAIR_CODE="$2"
CONNECT_PORT="${3:-}"

echo "=========================================================="
echo " Oneova Wireless Direct Pairing & Installer"
echo "=========================================================="
echo "Pair Address : $PAIR_ADDRESS"
echo "Pair Code    : $PAIR_CODE"
echo "Target APK   : $APK"
echo "----------------------------------------------------------"

echo "--> [1/4] Pairing with device..."
"$ADB" pair "$PAIR_ADDRESS" "$PAIR_CODE"

IP="${PAIR_ADDRESS%:*}"

if [ -n "$CONNECT_PORT" ]; then
  echo "--> [2/4] Connecting to $IP:$CONNECT_PORT..."
  "$ADB" connect "$IP:$CONNECT_PORT"
else
  # If connect port wasn't provided, try mDNS or query port
  echo "--> [2/4] Looking for connect port via mDNS or port on $IP..."
  sleep 2
  "$ADB" devices -l
fi

echo "--> [3/4] Installing Oneova APK ($APK)..."
"$ADB" install -r -d "$APK"

echo "--> [4/4] Launching Oneova App..."
"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1

echo "=========================================================="
echo " ONEOVA INSTALLED & LAUNCHED SUCCESSFULLY!"
echo "=========================================================="
