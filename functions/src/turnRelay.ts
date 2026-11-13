/**
 * ICE servers for the phone ↔ computer WebRTC link.
 *
 * STUN alone only connects devices whose routers allow a direct path. When
 * the phone is on mobile data and the computer is on home Wi-Fi (or behind a
 * strict NAT), traffic has to go through a TURN relay. This callable hands
 * out short-lived TURN credentials from Cloudflare Realtime TURN, so the
 * long-lived API token never leaves the server.
 *
 * Setup (once): create a TURN key in the Cloudflare dashboard (Realtime →
 * TURN) and store it in Firestore at `server_config/turn`:
 *   { cloudflareKeyId: "<TURN key id>", cloudflareApiToken: "<API token>" }
 * `server_config` is denied to every client by firestore.rules; only the
 * Admin SDK here can read it. Without it, STUN-only servers are returned and
 * the app keeps working on the same / friendly networks.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { limit } from './guard/protect';

const STUN = [
  { urls: ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'] },
];

const TTL_SECONDS = 6 * 60 * 60;

type IceServer = { urls: string | string[]; username?: string; credential?: string };

export const getIceServers = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  await limit(uid, 'ice_servers', 120, 60 * 60000);

  const cfg = (await getFirestore().doc('server_config/turn').get()).data() ?? {};
  const keyId = String(cfg.cloudflareKeyId ?? '').trim();
  const token = String(cfg.cloudflareApiToken ?? '').trim();
  if (!keyId || !token) {
    return { iceServers: STUN, relay: false, ttl: 3600 };
  }

  try {
    const res = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ttl: TTL_SECONDS }),
      },
    );
    if (!res.ok) {
      console.warn('[getIceServers] Cloudflare TURN responded', res.status);
      return { iceServers: STUN, relay: false, ttl: 600 };
    }
    const body = (await res.json()) as { iceServers?: IceServer | IceServer[] };
    const relay = ([] as IceServer[]).concat(body.iceServers ?? []);
    return { iceServers: [...STUN, ...relay], relay: relay.length > 0, ttl: TTL_SECONDS };
  } catch (e) {
    console.warn('[getIceServers] relay unavailable', e);
    return { iceServers: STUN, relay: false, ttl: 600 };
  }
});
