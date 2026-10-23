#!/usr/bin/env bash
# Waits for the USB phone, then records Oneova's Flutter/LiveKit logs to
# build/phone_live_logs.txt for 20 minutes (or until Ctrl-C).
set -uo pipefail
cd "$(dirname "$0")/../.."
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
OUT=build/phone_live_logs.txt
"$ADB" wait-for-device
"$ADB" logcat -c
echo "Recording to $OUT" >&2
timeout_s=1200; start=$(date +%s)
"$ADB" logcat -v time 2>/dev/null | grep --line-buffered -iE " flutter|livekit|webrtc|AndroidRuntime|FATAL" > "$OUT" &
pid=$!
while kill -0 $pid 2>/dev/null && [ $(( $(date +%s) - start )) -lt $timeout_s ]; do sleep 5; done
kill $pid 2>/dev/null; echo "done" >&2
