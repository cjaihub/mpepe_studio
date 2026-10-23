# Production LiveKit for Oneova (self-hosted)

These files run one production node: LiveKit, plus Caddy for automatic TLS and TURN/TLS on 443, plus Redis. Everything is pinned:
- `livekit/livekit-server:v1.13.10`
- `livekit/caddyl4:v2.11.3`
- `redis:7.4.1-alpine`

## 1. What you provision
- **A Linux VM with a public IPv4.** 4 vCPU / 8 GB is a good start (for example DigitalOcean, Hetzner or GCP), with Docker installed.
- **Two DNS A records** pointing at the VM, for example `live.oneova.com` and `turn.oneova.com`.
- **Firewall inbound rules:**
  - 80/tcp and 443/tcp
  - 7881/tcp
  - 3478/udp
  - 50000–60000/udp

## 2. Keys (already generated)
`secrets/livekit_api_key.txt` and `secrets/livekit_api_secret.txt` are owner-only and git-ignored. The same pair must be in Firebase Secret Manager:
```bash
firebase functions:secrets:set LIVEKIT_API_KEY --project mpepe-2b4bd --data-file tools/livekit/prod/secrets/livekit_api_key.txt
```
```bash
firebase functions:secrets:set LIVEKIT_API_SECRET --project mpepe-2b4bd --data-file tools/livekit/prod/secrets/livekit_api_secret.txt
```
To rotate the keys:
```bash
docker run --rm livekit/livekit-server:v1.13.10 generate-keys
```
Write the new values into those two files, then rerun both commands above.

## 3. On the VM
Copy this folder, including `secrets/`, to the VM over a secure channel (for example `scp`; never through chat or email). Then:
```bash
cp .env.example .env
```
Edit `.env` with the real domains and an email for Let's Encrypt, then:
```bash
bash setup.sh
```
```bash
docker compose up -d
```
`setup.sh` writes `livekit.yaml` and `caddy.yaml` with mode 600. Both contain the secret and are git-ignored.

## 4. Point the backend at it
Add `LIVEKIT_URL=wss://live.oneova.com` to `functions/.env.mpepe-2b4bd`, then redeploy the Live Studio functions.

## 5. Check
```bash
curl -I https://live.oneova.com
```
Then run the smoke test against the server, with its HTTPS URL and the keys from step 2:
```bash
LIVEKIT_HTTP=https://live.oneova.com node tools/livekit/smoke_server.js
```
Run the smoke test with `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` set in its environment. Read them from the files in `secrets/`; never paste them on the command line.

## Security notes
- LiveKit's API and signaling listen on 127.0.0.1 only; Caddy terminates TLS in front.
- Media is always encrypted in transit (DTLS-SRTP), and TURN runs over TLS on 443 for strict networks.
- Webhooks are signed with the API key and verified by `lsLivekitWebhook`.
- Scaling: add more nodes that share one Redis (move Redis to a private network host), behind DNS. Then load-test before raising the `live_studio_v2` rollout.
