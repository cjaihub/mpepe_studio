#!/usr/bin/env bash
# One-time setup + redeploy for the reels pipeline. Safe to re-run.
# Review before running: it creates a PUBLIC bucket (only transcoded reels go
# there; raw uploads stay private in the Firebase bucket).
set -euo pipefail

PROJECT="${PROJECT:-mpepe-2b4bd}"
REGION="${REGION:-us-central1}"
JOB="${JOB:-reels-transcode}"
REELS_BUCKET="${REELS_BUCKET:-${PROJECT}-reels}"
REELS_CDN_BASE="${REELS_CDN_BASE:-https://storage.googleapis.com/${REELS_BUCKET}}"
JOB_SA="reels-worker@${PROJECT}.iam.gserviceaccount.com"
FN_SA="${FN_SA:-${PROJECT}@appspot.gserviceaccount.com}"   # functions runtime SA; check yours

cd "$(dirname "$0")"
gcloud config set project "$PROJECT" >/dev/null

# 1. Public output bucket with long caching (objects never change once written).
gcloud storage buckets describe "gs://${REELS_BUCKET}" >/dev/null 2>&1 ||
  gcloud storage buckets create "gs://${REELS_BUCKET}" --location="$REGION" --uniform-bucket-level-access
gcloud storage buckets add-iam-policy-binding "gs://${REELS_BUCKET}" \
  --member=allUsers --role=roles/storage.objectViewer >/dev/null

# 2. Service account for the job: read uploads, write reels, update Firestore.
gcloud iam service-accounts describe "$JOB_SA" >/dev/null 2>&1 ||
  gcloud iam service-accounts create reels-worker --display-name="Reels transcode job"
for role in roles/storage.objectAdmin roles/datastore.user; do
  gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:${JOB_SA}" \
    --role="$role" --condition=None >/dev/null
done

# 3. Build and deploy the job. 4 vCPU / 4 GiB handles a 60 s reel in well under a minute.
gcloud run jobs deploy "$JOB" --source . --region "$REGION" \
  --service-account "$JOB_SA" --cpu 4 --memory 4Gi --task-timeout 15m --max-retries 1 \
  --set-env-vars "REELS_BUCKET=${REELS_BUCKET},REELS_CDN_BASE=${REELS_CDN_BASE}"

# 4. Let the Cloud Function start executions with env overrides.
gcloud run jobs add-iam-policy-binding "$JOB" --region "$REGION" \
  --member="serviceAccount:${FN_SA}" --role=roles/run.developer >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$JOB_SA" \
  --member="serviceAccount:${FN_SA}" --role=roles/iam.serviceAccountUser >/dev/null

echo "Job ready. Next:"
echo "  - Cloud CDN: create a backend bucket for gs://${REELS_BUCKET} with CDN on, put an"
echo "    HTTPS load balancer in front, then redeploy with REELS_CDN_BASE=https://<your domain>."
echo "  - Deploy only the new function so other deployed functions are untouched:"
echo "      firebase deploy --only functions:onReelUploaded,firestore,storage"
