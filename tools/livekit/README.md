# Self-hosted LiveKit for Live Studio v2

Oneova runs its own open-source LiveKit server; there is no LiveKit Cloud account. See docs/live-studio/ARCHITECTURE.md §2 and §7.

## Local dev server
```bash
docker compose -f tools/livekit/docker-compose.dev.yml up -d
```
- The image is pinned to `livekit/livekit-server:v1.13.10`.
- The signaling and API endpoint is `ws://127.0.0.1:7880` (HTTP API on the same port). WebRTC uses 7881/tcp and 7882/udp.
- Dev keys are `devkey` / `secret`. They are built into `--dev` mode and must never be used in production.
- Clients on other devices need a different address:
  - **iOS Simulator:** `ws://127.0.0.1:7880`.
  - **Android emulator:** `ws://10.0.2.2:7880`.
  - **Real phones on Wi-Fi:** start the server with `NODE_IP=<Mac LAN IP>`, then use `ws://<Mac LAN IP>:7880`.

Smoke test (room API, token grants per role, data fan-out):
```bash
npm --prefix functions run test:livestudio
```
```bash
node tools/livekit/smoke_server.js
```
The first command builds `functions/.ls-build`, which the smoke test reads.

Stop the server:
```bash
docker compose -f tools/livekit/docker-compose.dev.yml down
```

## Production (later)
- **Keys:** generate our own, and set them as the function secrets `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` and the param `LIVEKIT_URL` (`wss://live.<our domain>`):
  ```bash
  docker run --rm livekit/livekit-server:v1.13.10 generate-keys
  ```
- **TLS** in front of 7880. A TURN relay (LiveKit's built-in TURN/TLS on 443 or 5349) for mobile carriers.
- **Scale to the 100k-viewer target:** a multi-node cluster with Redis, spread across regions, plus load testing.
