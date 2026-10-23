#!/usr/bin/env bash
# Generates livekit.yaml and caddy.yaml from .env and secrets/ (never commit
# the generated files: they contain the API secret).
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "Copy .env.example to .env and fill it in"; exit 1; }
# shellcheck disable=SC1091
source .env
: "${LIVE_DOMAIN:?}" "${TURN_DOMAIN:?}"
ACME_EMAIL="${ACME_EMAIL:-}"   # optional: Let's Encrypt expiry notices only
KEY=$(cat secrets/livekit_api_key.txt)
SECRET=$(cat secrets/livekit_api_secret.txt)
WEBHOOK_URL="${WEBHOOK_URL:-https://us-central1-mpepe-2b4bd.cloudfunctions.net/lsLivekitWebhook}"

umask 077
cat > livekit.yaml <<EOF
port: 7880
bind_addresses: ["127.0.0.1"]   # only Caddy reaches the API/signaling
log_level: info
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 60000
  use_external_ip: true
redis:
  address: 127.0.0.1:6379
keys:
  ${KEY}: ${SECRET}
webhook:
  api_key: ${KEY}
  urls:
    - ${WEBHOOK_URL}
room:
  empty_timeout: 600
  max_participants: 0          # viewers are unlimited; stage size is enforced by our functions
turn:
  enabled: true
  domain: ${TURN_DOMAIN}
  tls_port: 5349
  udp_port: 3478
  external_tls: true
limit:
  num_tracks: 20
  bytes_per_sec: 0
EOF

cat > caddy.yaml <<EOF
logging:
  logs:
    default:
      level: INFO
storage:
  module: file_system
  root: /data
apps:
  tls:
    certificates:
      automate:
        - ${LIVE_DOMAIN}
        - ${TURN_DOMAIN}
    automation:
      policies:
        - issuers:
            - module: acme${ACME_EMAIL:+
              email: ${ACME_EMAIL}}
  layer4:
    servers:
      main:
        listen: [":443"]
        routes:
          - match:
              - tls:
                  sni: ["${TURN_DOMAIN}"]
            handle:
              - handler: tls
              - handler: proxy
                upstreams:
                  - dial: ["127.0.0.1:5349"]
          - match:
              - tls:
                  sni: ["${LIVE_DOMAIN}"]
            handle:
              - handler: tls
                connection_policies:
                  - alpn: ["http/1.1"]
              - handler: proxy
                upstreams:
                  - dial: ["127.0.0.1:7880"]
EOF
echo "Wrote livekit.yaml and caddy.yaml (mode 600). Next: docker compose up -d"
