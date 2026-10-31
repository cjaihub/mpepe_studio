#!/usr/bin/env bash
# Ova Guard + endpoint hardening rollout. Run it yourself from the repo root,
# one step at a time (each step asks before it changes production):
#   bash tools/play/guard_deploy.sh
# Functions are deployed BY NAME only: the project also runs `oc*` functions
# from another codebase, and an unscoped deploy would delete them.
# See docs/backend-endpoints.md for every endpoint and its protection.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
P=mpepe-2b4bd
RUNTIME_SA=90836164478-compute@developer.gserviceaccount.com

ask() { read -r -p "$1 [y/N] " a; [[ "$a" == "y" || "$a" == "Y" ]]; }

# 1) Google Web Risk (Safe Browsing for apps) for link checks, called as the
#    functions' service account (no API key). First 100k lookups/month are free.
if ask "Enable the Web Risk API and let the functions call it?"; then
  # No extra IAM role: the runtime service account ($RUNTIME_SA) has Editor,
  # which already allows calling Web Risk (there is no webrisk.* role).
  gcloud services enable webrisk.googleapis.com aiplatform.googleapis.com --project $P
fi

# 2) Self-cleaning caches and counters (Firestore TTL on expiresAt).
if ask "Turn on Firestore TTL for the guard caches?"; then
  for c in security_rate link_reputation guard_ai_cache guard_budget; do
    gcloud firestore fields ttls update expiresAt --collection-group=$c --enable-ttl --project $P --async
  done
fi

# 3) Rules + indexes (tighter rules, guard pauses, security_actions indexes).
#    Deploy the functions in step 4 in the same sitting.
if ask "Deploy firestore.rules, firestore indexes and storage.rules?"; then
  firebase deploy --only firestore:rules,firestore:indexes,storage --project $P
fi

# 4) Functions changed or added by this work (by name).
FUNCS="accountLookup guardCheckLinks guardReverseAction guardSweep guardBackfillContacts
guardScanPostComment guardScanContentComment guardOnProfileWrite guardOnMessage guardOnRelationship
guardReportSession guardReportAuthFailure checkLegacyPassword guardRespond guardRevokeDevice guardExplainEvent
moveLegacyPasswordHashesDaily moveLegacyPasswordHashesNow guardEmailOnEvent loginContext
aiProxy aiGateway chatAssist globalSemanticSearch biometricSignIn registerBiometricKey revokeBiometricKey
tiktokExchangeCode metaExchangeCode lsComment processAiCommand generateAbTests publishToSocials"
if ask "Deploy the Ova Guard and hardened functions?"; then
  ONLY=$(for f in $FUNCS; do printf 'functions:%s,' "$f"; done); ONLY=${ONLY%,}
  firebase deploy --only "$ONLY" --project $P
fi

# 5) Fill the private contact index once (admin account in the app, or here):
#    call guardBackfillContacts from an admin session until it returns done:true.
#
# 6) LATER, only after an app build with accountLookup is the one people use:
#    add GUARD_SPLIT_PRIVATE_FIELDS=true to functions/.env.mpepe-2b4bd and
#    redeploy guardOnProfileWrite + guardBackfillContacts, then run the backfill
#    again. That moves email/phone off the public profiles. Older builds look
#    accounts up by those fields and would not find them.
#
# 7) After requestWithdrawal checks security_state.withdrawalsFrozenUntil
#    (patch in the side-session notes), add GUARD_WITHDRAWAL_FREEZE=true and
#    redeploy the guard functions so risky sign-ins pause withdrawals.
#
# 8) LATER, once the App Check console shows nearly all traffic verified:
#    add APP_CHECK_ENFORCE=true to functions/.env.mpepe-2b4bd and redeploy the
#    callables the app uses (see docs/backend-endpoints.md).
