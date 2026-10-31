"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.connectorStatus = void 0;
/**
 * Which platform connections can actually work right now, so the app shows
 * "Waiting for setup" instead of starting a sign-in that is bound to fail.
 *
 * A platform is ready when the server has what its connect flow needs:
 *  - Facebook / Instagram / WhatsApp: META_APP_ID + META_REDIRECT_URI params and
 *    the META_APP_SECRET secret (metaExchangeCode).
 *  - TikTok: TIKTOK_CLIENT_KEY + TIKTOK_REDIRECT_URI params and the
 *    TIKTOK_CLIENT_SECRET secret (tiktokExchangeCode).
 *  - Gmail (server-kept connection): GOOGLE_WEB_CLIENT_ID, and the optional
 *    secrets GOOGLE_OAUTH_CLIENT_SECRET and GMAIL_TOKEN_KEY (gmailConnect).
 *  - YouTube: Google sign-in on the phone; nothing server-side.
 *
 * An admin can also hold a platform back (e.g. while it waits for the
 * platform's app review, or when a secret is known to be stale) with
 * `app_config/connectors.{platform} = { ready: false, note: '...' }`.
 * Only booleans and plain notes are returned; never secret values.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const optionalSecrets_1 = require("./optionalSecrets");
const has = (name) => { var _a; return ((_a = process.env[name]) !== null && _a !== void 0 ? _a : '').trim().length > 0; };
exports.connectorStatus = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const [metaSecret, tiktokSecret, googleSecret, gmailKey, overrides] = await Promise.all([
        (0, optionalSecrets_1.optionalSecret)('META_APP_SECRET'),
        (0, optionalSecrets_1.optionalSecret)('TIKTOK_CLIENT_SECRET'),
        (0, optionalSecrets_1.optionalSecret)('GOOGLE_OAUTH_CLIENT_SECRET'),
        (0, optionalSecrets_1.optionalSecret)('GMAIL_TOKEN_KEY'),
        (0, firestore_1.getFirestore)().collection('app_config').doc('connectors').get().then((d) => { var _a; return (_a = d.data()) !== null && _a !== void 0 ? _a : {}; }).catch(() => ({})),
    ]);
    const waiting = 'This connection is being set up. Check back soon.';
    const meta = has('META_APP_ID') && has('META_REDIRECT_URI') && metaSecret
        ? { ready: true }
        : { ready: false, note: waiting };
    const status = {
        facebook: meta,
        instagram: meta,
        whatsapp: meta,
        tiktok: has('TIKTOK_CLIENT_KEY') && has('TIKTOK_REDIRECT_URI') && tiktokSecret ? { ready: true } : { ready: false, note: waiting },
        gmail: has('GOOGLE_WEB_CLIENT_ID') && googleSecret && gmailKey ? { ready: true } : { ready: false, note: waiting },
        youtube: { ready: true },
    };
    for (const [platform, o] of Object.entries(overrides)) {
        const v = o;
        if (status[platform] && v && v.ready === false) {
            status[platform] = { ready: false, note: typeof v.note === 'string' && v.note ? v.note.slice(0, 160) : waiting };
        }
    }
    return { platforms: status };
});
//# sourceMappingURL=connectorStatus.js.map