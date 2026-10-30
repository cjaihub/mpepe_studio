#!/usr/bin/env bash
# One-time backend setup for the Play release. Run it yourself from the repo root:
#   bash tools/play/backend_setup.sh
# 1) Stores the TikTok client secret (read from the gitignored .env.secrets.local) in
#    Secret Manager, unless it is already there.
# 2) Turns on Vertex AI for the project and lets the Cloud Functions service account
#    call it. Gemini runs on Vertex as that account, so there is no Gemini API key.
# 3) Deploys only the Cloud Functions the app calls that are not live yet (by name;
#    nothing else in the project is touched or deleted).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
P=mpepe-2b4bd
RUNTIME_SA=90836164478-compute@developer.gserviceaccount.com

if ! firebase functions:secrets:get TIKTOK_CLIENT_SECRET --project $P >/dev/null 2>&1; then
  grep -E '^TIKTOK_CLIENT_SECRET=' .env.secrets.local | cut -d= -f2- | tr -d '\n"' \
    | firebase functions:secrets:set TIKTOK_CLIENT_SECRET --project $P --data-file -
fi

gcloud services enable aiplatform.googleapis.com --project $P
gcloud projects add-iam-policy-binding $P \
  --member "serviceAccount:$RUNTIME_SA" --role roles/aiplatform.user --condition=None >/dev/null

FUNCS="aiProxy tiktokExchangeCode sendEmailCode verifyEmailCode metaExchangeCode metaDataDeletion metaDeauthorize metaDeletionStatus checkLegacyPassword loginContext guardReportAuthFailure guardReportSession guardRespond guardRevokeDevice guardExplainEvent globalSemanticSearch aiGateway"

ONLY=$(for f in $FUNCS; do printf 'functions:%s,' "$f"; done); ONLY=${ONLY%,}
firebase deploy --only "$ONLY" --project $P
