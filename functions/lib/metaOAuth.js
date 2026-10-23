"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.metaDeletionStatus = exports.metaDeauthorize = exports.metaDataDeletion = exports.metaExchangeCode = void 0;
/**
 * Meta (Facebook Pages, Instagram, WhatsApp Business) login, server side.
 *
 *   metaExchangeCode   callable: OAuth code → long-lived user token → the
 *                      user's Pages. The app secret never leaves Secret Manager.
 *   metaDataDeletion   Meta "Data Deletion Request" callback (required for App
 *                      Review). Verifies the signed_request and deletes the
 *                      Meta connection data Oneova keeps for that person.
 *   metaDeauthorize    Meta "Deauthorize" callback: same clean-up when someone
 *                      removes Oneova from their Facebook settings.
 *   metaDeletionStatus Status page Meta links people to (confirmation code).
 *
 * Setup:
 *   firebase functions:secrets:set META_APP_SECRET --project mpepe-2b4bd
 *   META_APP_ID / META_REDIRECT_URI live in functions/.env.mpepe-2b4bd.
 * Dashboard: Facebook Login → Settings
 *   Deauthorize callback URL   https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDeauthorize
 *   Data deletion request URL  https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDataDeletion
 */
const crypto = __importStar(require("crypto"));
const axios_1 = __importDefault(require("axios"));
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const mailTemplates_1 = require("./mailTemplates");
const metaAppSecret = (0, params_1.defineSecret)('META_APP_SECRET');
const metaAppId = (0, params_1.defineString)('META_APP_ID');
const metaRedirectUri = (0, params_1.defineString)('META_REDIRECT_URI');
const GRAPH = 'https://graph.facebook.com/v22.0';
const db = () => (0, firestore_1.getFirestore)();
const APP_FIELDS = {
    facebook: 'id,name,category,picture,fan_count,access_token,tasks',
    instagram: 'id,name,category,picture,fan_count,access_token,tasks,instagram_business_account{id,username,profile_picture_url,followers_count}',
    whatsapp: 'id,name,category,picture,fan_count,access_token,tasks',
};
/** appsecret_proof: Meta's recommended guard for server-side Graph calls. */
function proof(token) {
    return crypto.createHmac('sha256', metaAppSecret.value()).update(token).digest('hex');
}
function graphError(e) {
    var _a, _b;
    var _c;
    const d = (_b = (_a = e === null || e === void 0 ? void 0 : e.response) === null || _a === void 0 ? void 0 : _a.data) === null || _b === void 0 ? void 0 : _b.error;
    return (_c = d === null || d === void 0 ? void 0 : d.message) !== null && _c !== void 0 ? _c : String(e);
}
exports.metaExchangeCode = (0, https_1.onCall)({ secrets: [metaAppSecret] }, async (request) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    var _j, _k, _l, _m, _o, _p, _q, _r, _s;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const data = ((_j = request.data) !== null && _j !== void 0 ? _j : {});
    const code = String((_k = data.code) !== null && _k !== void 0 ? _k : '');
    const app = String((_l = data.app) !== null && _l !== void 0 ? _l : 'facebook');
    if (!code || code.length > 2048)
        throw new https_1.HttpsError('invalid-argument', 'Missing authorization code.');
    if (!APP_FIELDS[app])
        throw new https_1.HttpsError('invalid-argument', 'Unknown Meta app.');
    // The redirect URI must match the one used for the dialog; only ours is accepted.
    const redirectUri = metaRedirectUri.value();
    try {
        const short = await axios_1.default.get(`${GRAPH}/oauth/access_token`, {
            params: { client_id: metaAppId.value(), client_secret: metaAppSecret.value(), redirect_uri: redirectUri, code },
            timeout: 15000,
        });
        const shortToken = (_b = short.data) === null || _b === void 0 ? void 0 : _b.access_token;
        if (!shortToken)
            throw new Error('No access token from Meta.');
        const long = await axios_1.default.get(`${GRAPH}/oauth/access_token`, {
            params: { grant_type: 'fb_exchange_token', client_id: metaAppId.value(), client_secret: metaAppSecret.value(), fb_exchange_token: shortToken },
            timeout: 15000,
        });
        const userToken = (_m = (_c = long.data) === null || _c === void 0 ? void 0 : _c.access_token) !== null && _m !== void 0 ? _m : shortToken;
        const expiresIn = Number((_o = (_d = long.data) === null || _d === void 0 ? void 0 : _d.expires_in) !== null && _o !== void 0 ? _o : 5184000);
        const me = await axios_1.default.get(`${GRAPH}/me`, { params: { fields: 'id,name', access_token: userToken, appsecret_proof: proof(userToken) }, timeout: 15000 });
        const metaUserId = String((_p = (_e = me.data) === null || _e === void 0 ? void 0 : _e.id) !== null && _p !== void 0 ? _p : '');
        const perms = await axios_1.default.get(`${GRAPH}/me/permissions`, { params: { access_token: userToken, appsecret_proof: proof(userToken) }, timeout: 15000 });
        const granted = ((_q = (_f = perms.data) === null || _f === void 0 ? void 0 : _f.data) !== null && _q !== void 0 ? _q : [])
            .filter((p) => p.status === 'granted')
            .map((p) => p.permission);
        const accounts = await axios_1.default.get(`${GRAPH}/me/accounts`, {
            params: { fields: APP_FIELDS[app], limit: 50, access_token: userToken, appsecret_proof: proof(userToken) },
            timeout: 15000,
        });
        let pages = ((_r = (_g = accounts.data) === null || _g === void 0 ? void 0 : _g.data) !== null && _r !== void 0 ? _r : []);
        if (app === 'instagram')
            pages = pages.filter((p) => p.instagram_business_account);
        // Remember which Oneova account this Meta person belongs to, so a
        // deletion / deauthorize callback from Meta can find their data.
        if (metaUserId) {
            await db().collection('meta_users').doc(metaUserId).set({ uids: firestore_1.FieldValue.arrayUnion(uid), apps: firestore_1.FieldValue.arrayUnion(app), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
            await db().collection('users').doc(uid).collection('private').doc('meta').set({ metaUserId, granted, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        }
        return { userToken, expiresIn, metaUserId, metaUserName: (_s = (_h = me.data) === null || _h === void 0 ? void 0 : _h.name) !== null && _s !== void 0 ? _s : null, granted, pages };
    }
    catch (e) {
        logger.warn('[metaExchangeCode] failed', { error: graphError(e) });
        throw new https_1.HttpsError('failed-precondition', `Meta sign-in failed: ${graphError(e)}`);
    }
});
// ── Signed requests (deletion / deauthorize) ─────────────────────────────
function parseSignedRequest(signed) {
    const [sig, payload] = signed.split('.', 2);
    if (!sig || !payload)
        return null;
    const expected = crypto.createHmac('sha256', metaAppSecret.value()).update(payload).digest();
    const given = Buffer.from(sig.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
    if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected))
        return null;
    try {
        const json = JSON.parse(Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
        return (json === null || json === void 0 ? void 0 : json.algorithm) === 'HMAC-SHA256' ? json : null;
    }
    catch (_a) {
        return null;
    }
}
/** Deletes everything Oneova stores about this Meta person. Returns uids touched. */
async function purgeMetaUser(metaUserId, reason) {
    var _a;
    const ref = db().collection('meta_users').doc(metaUserId);
    const snap = await ref.get();
    const uids = (_a = snap.get('uids')) !== null && _a !== void 0 ? _a : [];
    for (const uid of uids) {
        const batch = db().batch();
        for (const app of ['facebook', 'instagram', 'whatsapp']) {
            batch.delete(db().collection('users').doc(uid).collection('social_connections').doc(app));
        }
        batch.delete(db().collection('users').doc(uid).collection('private').doc('meta'));
        // The phone drops its stored tokens when it sees the connection is gone.
        batch.set(db().collection('users').doc(uid), { metaDisconnectedAt: firestore_1.FieldValue.serverTimestamp(), metaDisconnectReason: reason }, { merge: true });
        await batch.commit();
    }
    await ref.delete();
    return uids.length;
}
function statusUrl(code) {
    var _a;
    const project = (_a = process.env.GCLOUD_PROJECT) !== null && _a !== void 0 ? _a : 'mpepe-2b4bd';
    return `https://us-central1-${project}.cloudfunctions.net/metaDeletionStatus?code=${encodeURIComponent(code)}`;
}
exports.metaDataDeletion = (0, https_1.onRequest)({ secrets: [metaAppSecret] }, async (req, res) => {
    var _a;
    var _b;
    if (req.method !== 'POST') {
        res.status(405).json({ error: 'POST signed_request' });
        return;
    }
    const parsed = parseSignedRequest(String((_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.signed_request) !== null && _b !== void 0 ? _b : ''));
    if (!(parsed === null || parsed === void 0 ? void 0 : parsed.user_id)) {
        res.status(400).json({ error: 'Invalid signed_request' });
        return;
    }
    const code = crypto.randomBytes(9).toString('base64url');
    const count = await purgeMetaUser(String(parsed.user_id), 'deletion');
    await db().collection('meta_deletions').doc(code).set({
        metaUserIdHash: crypto.createHash('sha256').update(String(parsed.user_id)).digest('hex'),
        accounts: count,
        status: 'completed',
        requestedAt: firestore_1.FieldValue.serverTimestamp(),
        completedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    res.json({ url: statusUrl(code), confirmation_code: code });
});
exports.metaDeauthorize = (0, https_1.onRequest)({ secrets: [metaAppSecret] }, async (req, res) => {
    var _a;
    var _b;
    const parsed = parseSignedRequest(String((_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.signed_request) !== null && _b !== void 0 ? _b : ''));
    if (!(parsed === null || parsed === void 0 ? void 0 : parsed.user_id)) {
        res.status(400).send('Invalid signed_request');
        return;
    }
    await purgeMetaUser(String(parsed.user_id), 'deauthorize');
    res.status(200).send('ok');
});
exports.metaDeletionStatus = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b;
    var _c;
    res.set('Cache-Control', 'no-store');
    const code = String((_c = req.query.code) !== null && _c !== void 0 ? _c : '').slice(0, 40);
    const snap = code ? await db().collection('meta_deletions').doc(code).get() : null;
    if (!(snap === null || snap === void 0 ? void 0 : snap.exists)) {
        res.status(404).send((0, mailTemplates_1.page)({ title: 'Request not found', message: 'We couldn’t find a deletion request with this code. Check the link from Facebook, or email privacy@oneova.app.', tone: 'warn' }));
        return;
    }
    const at = (_b = (_a = snap.get('completedAt')) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a);
    res.status(200).send((0, mailTemplates_1.page)({
        title: 'Your data was deleted',
        message: `Confirmation code <b>${code}</b>. Oneova removed your Facebook, Instagram and WhatsApp connection data` +
            (at ? ` on ${at.toUTCString()}` : '') +
            '. Your Oneova account itself is not deleted; to delete it, email <b>privacy@oneova.app</b> (see mpepe-2b4bd.web.app/deletion).',
        tone: 'ok',
    }));
});
//# sourceMappingURL=metaOAuth.js.map