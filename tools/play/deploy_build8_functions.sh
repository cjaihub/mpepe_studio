#!/usr/bin/env bash
# Deploy all Oneova Build 8 (v1.0.0+8) Cloud Functions & Rules.
#
# IMPORTANT: Never run an unscoped `firebase deploy --only functions` on mpepe-2b4bd,
# because `oc*` functions from another codebase share the project.
#
# Prerequisite: Active billing on GCP project `mpepe-2b4bd`:
#   https://console.developers.google.com/billing/enable?project=mpepe-2b4bd
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
P=mpepe-2b4bd

echo "=== Deploying Firestore & Storage Rules ==="
firebase deploy --only firestore:rules,storage --project "$P"

npm --prefix functions run build

BATCH_1="voiceTidy chatAssist aiGateway aiProxy gmailConnect gmailStatus gmailDisconnect gmailCall suggestProfileDetails onFeedTuned onAppReleasePublished shareToAudience contentSetDestination contentOpenDestination"
ONLY_1=$(for f in $BATCH_1; do printf 'functions:%s,' "$f"; done); ONLY_1=${ONLY_1%,}
echo "=== Deploying Batch 1 (AI, Voice, Chat, Gmail, Profile & Reels Links) ==="
firebase deploy --only "$ONLY_1" --project "$P"

BATCH_2="lsPool lsWatch lsYouTubeSearch lsComment lsDeleteComment lsMuteChat lsReact lsShare lsLivekitWebhook lsGifSearch lsStart lsToken lsEnd lsStateFull"
ONLY_2=$(for f in $BATCH_2; do printf 'functions:%s,' "$f"; done); ONLY_2=${ONLY_2%,}
echo "=== Deploying Batch 2 (Live Studio 3D Pool, Watch Party & Social) ==="
firebase deploy --only "$ONLY_2" --project "$P"

echo "✔ All Build 8 Cloud Functions and Rules deployed successfully."

