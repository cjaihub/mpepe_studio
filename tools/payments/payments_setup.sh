#!/usr/bin/env bash
# Oneova creator payouts: wires Stripe and Flutterwave / Paystack to the
# deployed Cloud Functions. Secrets go straight into Secret Manager and are
# never printed (except the Flutterwave webhook hash, which you paste into
# the Flutterwave dashboard yourself).
#
#   tools/payments/payments_setup.sh stripe       webhook endpoint + signing secret, Connect check
#   tools/payments/payments_setup.sh flutterwave  asks for your secret key, makes the webhook hash
#   tools/payments/payments_setup.sh paystack     asks for your secret key
#   tools/payments/payments_setup.sh status       what is set up
set -euo pipefail

PROJECT=mpepe-2b4bd
SA="90836164478-compute@developer.gserviceaccount.com"
BASE="https://us-central1-${PROJECT}.cloudfunctions.net"

have_secret() { gcloud secrets describe "$1" --project "$PROJECT" >/dev/null 2>&1; }

# put_secret NAME  (value on stdin)
put_secret() {
  local name=$1
  if have_secret "$name"; then
    gcloud secrets versions add "$name" --project "$PROJECT" --data-file=- >/dev/null
  else
    gcloud secrets create "$name" --project "$PROJECT" --replication-policy=automatic --data-file=- >/dev/null
  fi
  gcloud secrets add-iam-policy-binding "$name" --project "$PROJECT" \
    --member="serviceAccount:${SA}" --role=roles/secretmanager.secretAccessor >/dev/null
  echo "  ✔ ${name} saved"
}

read_secret() { gcloud secrets versions access latest --secret "$1" --project "$PROJECT" 2>/dev/null; }

stripe_api() { # METHOD PATH [curl args...]
  local m=$1 p=$2; shift 2
  curl -sS -X "$m" "https://api.stripe.com/v1${p}" -u "${STRIPE_KEY}:" "$@"
}

setup_stripe() {
  STRIPE_KEY=$(read_secret STRIPE_SECRET_KEY || true)
  if [[ -z "${STRIPE_KEY}" ]]; then
    echo "STRIPE_SECRET_KEY is missing. Add it first: firebase functions:secrets:set STRIPE_SECRET_KEY --project ${PROJECT}"
    exit 1
  fi
  [[ "$STRIPE_KEY" == sk_live_* || "$STRIPE_KEY" == rk_live_* ]] && mode=LIVE || mode=TEST
  echo "Stripe key mode: ${mode}"

  local url="${BASE}/creatorStripeWebhook"
  local existing
  existing=$(stripe_api GET "/webhook_endpoints?limit=100" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'error' in d: print('ERR:'+d['error'].get('message','')); sys.exit()
print(next((e['id'] for e in d.get('data',[]) if e.get('url')=='$url'),''))")
  if [[ "$existing" == ERR:* ]]; then echo "  ✖ Stripe said: ${existing#ERR:}"; exit 1; fi
  if [[ -n "$existing" ]] && have_secret STRIPE_PAYOUTS_WEBHOOK_SECRET; then
    echo "  ✔ webhook already set up (${existing})"
  else
    # Stripe only shows a signing secret at creation, so recreate it if we lost it.
    [[ -n "$existing" ]] && stripe_api DELETE "/webhook_endpoints/${existing}" >/dev/null
    stripe_api POST /webhook_endpoints \
      -d url="$url" \
      -d "description=Oneova creator payouts and identity" \
      -d "enabled_events[]=identity.verification_session.verified" \
      -d "enabled_events[]=identity.verification_session.requires_input" \
      -d "enabled_events[]=identity.verification_session.processing" \
      -d "enabled_events[]=identity.verification_session.canceled" \
      -d "enabled_events[]=transfer.reversed" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'error' in d: sys.stderr.write('  ✖ Stripe said: '+d['error'].get('message','')+'\n'); sys.exit(1)
sys.stdout.write(d['secret'])" | put_secret STRIPE_PAYOUTS_WEBHOOK_SECRET
    echo "  ✔ webhook endpoint created → ${url}"
  fi

  # Connect must be on for Stripe payouts outside Africa.
  if stripe_api GET "/accounts?limit=1" | python3 -c "import json,sys; sys.exit(1 if 'error' in json.load(sys.stdin) else 0)"; then
    echo "  ✔ Connect is on"
  else
    echo "  ✖ Connect is off → turn it on: https://dashboard.stripe.com/connect/overview"
  fi
  echo "  • Identity: make sure it is activated → https://dashboard.stripe.com/identity"
}

ask_key() { # prompt
  local v
  read -r -s -p "$1: " v; echo >&2
  printf '%s' "$v"
}

setup_flutterwave() {
  local key
  key=$(ask_key "Paste your Flutterwave SECRET key (FLWSECK-..., hidden)")
  [[ "$key" == FLWSECK* ]] || { echo "That doesn't look like a Flutterwave secret key."; exit 1; }
  printf '%s' "$key" | put_secret FLUTTERWAVE_SECRET_KEY
  local hash
  hash=$(openssl rand -hex 24)
  printf '%s' "$hash" | put_secret FLUTTERWAVE_WEBHOOK_HASH
  cat <<EOF

Now in the Flutterwave dashboard → Settings → Webhooks:
  URL:          ${BASE}/flutterwaveWebhook
  Secret hash:  ${hash}
  Tick "Receive webhook response in JSON format" and save.
EOF
}

setup_paystack() {
  local key
  key=$(ask_key "Paste your Paystack SECRET key (sk_live_... or sk_test_..., hidden)")
  [[ "$key" == sk_* ]] || { echo "That doesn't look like a Paystack secret key."; exit 1; }
  printf '%s' "$key" | put_secret PAYSTACK_SECRET_KEY
  echo "In Paystack → Settings → API Keys & Webhooks, set the webhook URL to: ${BASE}/paystackWebhook"
}

status() {
  for s in STRIPE_SECRET_KEY STRIPE_PAYOUTS_WEBHOOK_SECRET FLUTTERWAVE_SECRET_KEY FLUTTERWAVE_WEBHOOK_HASH PAYSTACK_SECRET_KEY GOOGLE_MAPS_SERVER_KEY; do
    if have_secret "$s"; then echo "  ✔ $s"; else echo "  · $s (not set)"; fi
  done
}

case "${1:-status}" in
  stripe) setup_stripe ;;
  flutterwave) setup_flutterwave ;;
  paystack) setup_paystack ;;
  status) status ;;
  *) echo "usage: $0 stripe|flutterwave|paystack|status"; exit 1 ;;
esac
