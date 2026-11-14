#!/usr/bin/env bash
# Deploys the voice server to Cloud Run with one NVIDIA L4. Costs money while
# running (scale to zero when idle). Run only after the user says yes to the GPU cost.
# Public ingress on purpose: phones open the call stream directly. Every route except
# /health checks its own credential in the app (Functions' Google ID token, or a
# short-lived HMAC stream token), see voice/auth.py and voice/api.py.
set -euo pipefail
P=${P:-mpepe-2b4bd}; R=${R:-us-central1}; S=oneova-voice
FN_SA=90836164478-compute@developer.gserviceaccount.com
cd "$(dirname "$0")"
gcloud run deploy $S --project $P --region $R --source . \
  --gpu 1 --gpu-type nvidia-l4 --no-gpu-zonal-redundancy \
  --cpu 8 --memory 32Gi --concurrency 4 --timeout 900 \
  --min-instances ${MIN_INSTANCES:-0} --max-instances ${MAX_INSTANCES:-3} \
  --allow-unauthenticated \
  --set-env-vars VOICE_BUCKET=${VOICE_BUCKET:-mpepe-2b4bd.firebasestorage.app},VOICE_ALLOWED_CALLERS=$FN_SA \
  --set-secrets VOICE_STREAM_KEY=VOICE_STREAM_KEY:latest
URL=$(gcloud run services describe $S --project $P --region $R --format='value(status.url)')
gcloud run services update $S --project $P --region $R --update-env-vars VOICE_AUDIENCE=$URL
echo "Voice server: $URL  →  set it as the VOICE_SERVER_URL secret for Cloud Functions."
