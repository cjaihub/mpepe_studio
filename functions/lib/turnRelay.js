"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getIceServers = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("./guard/protect");
const STUN = [
    { urls: ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'] },
];
const TTL_SECONDS = 6 * 60 * 60;
exports.getIceServers = (0, https_1.onCall)(async (request) => {
    var _a;
    var _b, _c, _d, _e;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    await (0, protect_1.limit)(uid, 'ice_servers', 120, 60 * 60000);
    const cfg = (_b = (await (0, firestore_1.getFirestore)().doc('server_config/turn').get()).data()) !== null && _b !== void 0 ? _b : {};
    const keyId = String((_c = cfg.cloudflareKeyId) !== null && _c !== void 0 ? _c : '').trim();
    const token = String((_d = cfg.cloudflareApiToken) !== null && _d !== void 0 ? _d : '').trim();
    if (!keyId || !token) {
        return { iceServers: STUN, relay: false, ttl: 3600 };
    }
    try {
        const res = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ ttl: TTL_SECONDS }),
        });
        if (!res.ok) {
            console.warn('[getIceServers] Cloudflare TURN responded', res.status);
            return { iceServers: STUN, relay: false, ttl: 600 };
        }
        const body = (await res.json());
        const relay = [].concat((_e = body.iceServers) !== null && _e !== void 0 ? _e : []);
        return { iceServers: [...STUN, ...relay], relay: relay.length > 0, ttl: TTL_SECONDS };
    }
    catch (e) {
        console.warn('[getIceServers] relay unavailable', e);
        return { iceServers: STUN, relay: false, ttl: 600 };
    }
});
//# sourceMappingURL=turnRelay.js.map