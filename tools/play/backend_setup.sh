#!/usr/bin/env bash
# One-time backend setup for the Play release. Run it yourself from the repo root:
#   bash tools/play/backend_setup.sh
# 1) Stores the TikTok client secret (read from the gitignored .env.secrets.local) in Secret Manager.
# 2) Asks for a Gemini API key (https://aistudio.google.com/apikey); press Enter to skip.
# 3) Deploys only the Cloud Functions the app calls that are not live yet (by name;
#    nothing else in the project is touched or deleted).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
P=mpepe-2b4bd

grep -E '^TIKTOK_CLIENT_SECRET=' .env.secrets.local | cut -d= -f2- | tr -d '\n"' \
  | firebase functions:secrets:set TIKTOK_CLIENT_SECRET --project $P --data-file -
FUNCS="aiProxy tiktokExchangeCode sendEmailCode verifyEmailCode metaExchangeCode metaDataDeletion metaDeauthorize metaDeletionStatus checkLegacyPassword loginContext guardReportAuthFailure guardReportSession guardRespond guardRevokeDevice globalSemanticSearch"

read -r -s -p "Gemini API key (Enter to skip): " GEMINI; echo
if [[ -n "$GEMINI" ]]; then
  printf '%s' "$GEMINI" | firebase functions:secrets:set GEMINI_API_KEY --project $P --data-file -
  FUNCS="$FUNCS aiGateway generateLiveApiToken guardExplainEvent"
fi

ONLY=$(for f in $FUNCS; do printf 'functions:%s,' "$f"; done); ONLY=${ONLY%,}
firebase deploy --only "$ONLY" --project $P
