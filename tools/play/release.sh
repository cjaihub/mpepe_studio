#!/usr/bin/env bash
# Build a signed release bundle with the next build number and push it to a
# Google Play track (internal by default). Production needs --confirm-production.
#
#   tools/play/release.sh [track] ["release notes"] [in-app update priority 0-5]
#
# Requires android/key.properties (upload key) and android/play-service-account.json.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TRACK="${1:-internal}"
NOTES="${2:-Bug fixes and improvements.}"
PRIORITY="${3:-0}"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"

# Guard: never ship secrets inside the bundled .env.
if grep -qE '^(OPENROUTER_API_KEY|TIKTOK_CLIENT_SECRET|META_APP_SECRET)=.+' .env; then
  echo "ERROR: a server secret is set in .env, which ships inside the app." >&2; exit 1
fi

flutter test test/guards/home_lock_test.dart

# Bump the build number (the +N in pubspec version). Play rejects reused codes.
CUR=$(grep -E '^version:' pubspec.yaml | sed -E 's/version: *//')
NAME="${CUR%%+*}"; CODE="${CUR##*+}"; NEXT=$((CODE + 1))
sed -i '' -E "s/^version: .*/version: ${NAME}+${NEXT}/" pubspec.yaml
echo "version ${NAME}+${NEXT}"

flutter build appbundle --release
AAB=build/app/outputs/bundle/release/app-release.aab
mkdir -p build/play && cp "$AAB" "build/play/oneova-${NAME}-${NEXT}.aab"

EXTRA=()
[[ "$TRACK" == "production" ]] && EXTRA+=(--confirm-production "${CONFIRM_PRODUCTION:-false}")
# While other Play Console changes wait for review, commit without sending: PLAY_NOT_SENT_FOR_REVIEW=1
[[ -n "${PLAY_NOT_SENT_FOR_REVIEW:-}" ]] && EXTRA+=(--not-sent-for-review)
node tools/play/play_publish.cjs --aab "$AAB" --track "$TRACK" --notes "$NOTES" --priority "$PRIORITY" "${EXTRA[@]+"${EXTRA[@]}"}"
