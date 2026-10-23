#!/usr/bin/env bash
# Live Studio v2 — local test stack for a USB-connected Android phone.
#
#   bash tools/livekit/dev_stack.sh
#
# Starts Docker + our self-hosted LiveKit (dev keys), tunnels the ports to the
# phone over USB (adb reverse — no Wi-Fi/firewall changes needed), then runs
# the Firebase Auth/Firestore/Functions emulators in the foreground.
# Stop with Ctrl-C. The app must be built with
#   --dart-define=USE_EMULATORS=127.0.0.1 --dart-define=LIVE_STUDIO_V2=true
set -euo pipefail
cd "$(dirname "$0")/../.."

ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
JAVA_HOME="${JAVA_HOME:-$(ls -d "$HOME"/.local/jdk/jdk-21*/Contents/Home 2>/dev/null | head -1)}"
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"

echo "▸ Docker"
if ! docker info >/dev/null 2>&1; then
  open -a Docker
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 3; done
fi
docker info >/dev/null 2>&1 || { echo "Docker did not start"; exit 1; }

echo "▸ LiveKit (self-hosted, dev mode)"
docker compose -f tools/livekit/docker-compose.dev.yml up -d
for _ in $(seq 1 20); do curl -fs -o /dev/null http://127.0.0.1:7880/ && break; sleep 1; done
curl -fs -o /dev/null http://127.0.0.1:7880/ && echo "  LiveKit up on :7880" || { echo "LiveKit not responding"; exit 1; }

echo "▸ USB tunnels to the phone"
"$ADB" wait-for-device
for p in 9099 8080 5001 7880 7881; do "$ADB" reverse "tcp:$p" "tcp:$p" >/dev/null; done
"$ADB" reverse --list

echo "▸ Functions build"
npm --prefix functions run build >/dev/null

echo "▸ Firebase emulators (Ctrl-C to stop)"
exec firebase emulators:start --only auth,firestore,functions --project mpepe-2b4bd
