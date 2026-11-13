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
Object.defineProperty(exports, "__esModule", { value: true });
exports.googleAccessToken = exports.googleRemoveAccount = exports.googleUnlinkService = exports.googleLinkService = exports.GOOGLE_SERVICES = exports.GOOGLE_IDENTITY_SCOPES = void 0;
/**
 * Google services a person keeps linked to their Oneova profile
 * (Profile → Google services). This is separate from signing in to Oneova:
 * a person adds a Google account once, then switches on only the services
 * they use. Each service asks Google for its own scopes (incremental
 * authorization), so turning on Calendar never asks for Gmail.
 *
 *   googleLinkService({ service | services, serverAuthCode })  add services (and the account, first time)
 *   googleUnlinkService({ sub, service })           stop using one service
 *   googleRemoveAccount({ sub })                    revoke at Google, delete everything
 *   googleAccessToken({ sub, service })             short-lived access token for on-device API calls
 *
 * One refresh token per Google account, AES-256-GCM encrypted (uid-bound) in
 * `users/{uid}/secure_tokens/google_{sub}` (server only, same key as Gmail).
 * The app reads `users/{uid}/google_accounts/{sub}`, also server-written:
 * email, name, photo, granted scopes and `services.{id}.status`.
 *
 * Gmail keeps using gmailUser.ts: linking Gmail here writes the same token to
 * `secure_tokens/gmail` (tagged with `googleSub`) and the usual
 * `social_connections/gmail` status doc, so Ova and the inbox work unchanged.
 * Linking YouTube writes `youtube_accounts/{sub}` with the person's channels.
 *
 * Google has no per-scope revoke: turning one service off means Oneova stops
 * using it; only removing the account cuts Google's permission.
 */
const googleapis_1 = require("googleapis");
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const gmailUser_1 = require("./gmailUser");
const db = () => (0, firestore_1.getFirestore)();
/** Asked with every service so the account can be named on its card. */
exports.GOOGLE_IDENTITY_SCOPES = [
    'openid',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
];
/** Must match `GoogleService` in lib/backend/connections/google_services.dart. */
exports.GOOGLE_SERVICES = {
    // Gmail stays server-only: mail is read and sent through gmailCall.
    gmail: { label: 'Gmail', scopes: gmailUser_1.GMAIL_SCOPES, deviceToken: false },
    youtube: {
        label: 'YouTube',
        scopes: [
            'https://www.googleapis.com/auth/youtube.upload',
            'https://www.googleapis.com/auth/youtube.readonly',
            'https://www.googleapis.com/auth/youtube.force-ssl',
            'https://www.googleapis.com/auth/yt-analytics.readonly',
            'https://www.googleapis.com/auth/yt-analytics-monetary.readonly',
        ],
        deviceToken: true,
    },
    drive: { label: 'Google Drive', scopes: ['https://www.googleapis.com/auth/drive.file'], deviceToken: true },
    calendar: { label: 'Google Calendar', scopes: ['https://www.googleapis.com/auth/calendar.events'], deviceToken: true },
    contacts: { label: 'Google Contacts', scopes: ['https://www.googleapis.com/auth/contacts.readonly'], deviceToken: true },
    tasks: { label: 'Google Tasks', scopes: ['https://www.googleapis.com/auth/tasks'], deviceToken: true },
};
const user = (uid) => db().collection('users').doc(uid);
const tokenRef = (uid, sub) => user(uid).collection('secure_tokens').doc(`google_${sub}`);
const accountRef = (uid, sub) => user(uid).collection('google_accounts').doc(sub);
const youtubeRef = (uid, sub) => user(uid).collection('youtube_accounts').doc(sub);
function str(v, max) {
    return String(v !== null && v !== void 0 ? v : '').slice(0, max);
}
function serviceOf(v) {
    const id = str(v, 32);
    const def = exports.GOOGLE_SERVICES[id];
    if (!def)
        throw new https_1.HttpsError('invalid-argument', 'Unknown Google service.');
    return [id, def];
}
function subOf(v) {
    const sub = str(v, 64);
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(sub))
        throw new https_1.HttpsError('invalid-argument', 'Unknown Google account.');
    return sub;
}
async function client() {
    try {
        return await (0, gmailUser_1.oauth)();
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw new https_1.HttpsError('failed-precondition', 'Google services are not set up on the server yet.');
        throw e;
    }
}
/** Decrypted refresh token for [sub], or null when the account isn't linked. */
async function refreshTokenFor(uid, sub) {
    var _a;
    const snap = await tokenRef(uid, sub).get();
    const enc = snap.get('refreshToken');
    if (!enc)
        return null;
    return { token: await (0, gmailUser_1.decrypt)(enc, uid), scopes: (_a = snap.get('scopes')) !== null && _a !== void 0 ? _a : [] };
}
/** Marks every service on the account as needing a reconnect (Google said invalid_grant). */
async function markNeedsReconnect(uid, sub) {
    var _a;
    const acc = await accountRef(uid, sub).get();
    const services = ((_a = acc.get('services')) !== null && _a !== void 0 ? _a : {});
    const patch = {};
    for (const id of Object.keys(services))
        patch[id] = { status: 'needsReconnect' };
    await accountRef(uid, sub).set({ services: patch, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
}
// ── service-specific setup ───────────────────────────────────────────────
/** Gmail is one address per Oneova user: point gmailUser.ts at this account. */
async function linkGmail(uid, sub, email, refreshEnc, granted) {
    const prev = await (0, gmailUser_1.gmailTokenRef)(uid).get();
    const prevSub = prev.get('googleSub');
    const batch = db().batch();
    if (prevSub && prevSub !== sub) {
        batch.set(accountRef(uid, prevSub), { services: { gmail: firestore_1.FieldValue.delete() } }, { merge: true });
    }
    batch.set((0, gmailUser_1.gmailTokenRef)(uid), {
        refreshToken: refreshEnc,
        email,
        scopes: granted,
        googleSub: sub,
        connectedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    batch.set((0, gmailUser_1.gmailStatusRef)(uid), {
        platform: 'gmail',
        accountName: email,
        email,
        grantedScopes: gmailUser_1.GMAIL_SCOPES,
        scopes: gmailUser_1.GMAIL_SCOPES.map((s) => s.split('/').pop()),
        tokenStore: 'server',
        googleSub: sub,
        connectedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await batch.commit();
}
/** Writes `youtube_accounts/{sub}` in the shape YtAccountStore reads. */
async function syncYoutube(uid, sub, me, auth) {
    var _a, _b, _c, _d, _e, _f;
    const res = await googleapis_1.google.youtube({ version: 'v3', auth }).channels.list({ part: ['snippet', 'statistics'], mine: true });
    const prev = await youtubeRef(uid, sub).get();
    const prevActive = new Set(((_a = prev.get('channels')) !== null && _a !== void 0 ? _a : []).filter((c) => c.isActive).map((c) => c.id));
    // First YouTube account: make its first channel the active one.
    const anyActive = prevActive.size > 0 ||
        (await user(uid).collection('youtube_accounts').get()).docs.some((d) => { var _a; return d.id !== sub && ((_a = d.get('channels')) !== null && _a !== void 0 ? _a : []).some((c) => c.isActive); });
    const channels = ((_b = res.data.items) !== null && _b !== void 0 ? _b : []).map((ch, i) => { var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k; var _l, _m, _o, _p, _q, _r, _s, _t; return ({
        id: (_l = ch.id) !== null && _l !== void 0 ? _l : '',
        title: (_m = (_a = ch.snippet) === null || _a === void 0 ? void 0 : _a.title) !== null && _m !== void 0 ? _m : 'Unknown Channel',
        thumbnailUrl: (_p = (_o = (_d = (_c = (_b = ch.snippet) === null || _b === void 0 ? void 0 : _b.thumbnails) === null || _c === void 0 ? void 0 : _c.medium) === null || _d === void 0 ? void 0 : _d.url) !== null && _o !== void 0 ? _o : (_g = (_f = (_e = ch.snippet) === null || _e === void 0 ? void 0 : _e.thumbnails) === null || _f === void 0 ? void 0 : _f.default) === null || _g === void 0 ? void 0 : _g.url) !== null && _p !== void 0 ? _p : '',
        subscriberCount: Number((_q = (_h = ch.statistics) === null || _h === void 0 ? void 0 : _h.subscriberCount) !== null && _q !== void 0 ? _q : 0),
        videoCount: Number((_r = (_j = ch.statistics) === null || _j === void 0 ? void 0 : _j.videoCount) !== null && _r !== void 0 ? _r : 0),
        viewCount: Number((_s = (_k = ch.statistics) === null || _k === void 0 ? void 0 : _k.viewCount) !== null && _s !== void 0 ? _s : 0),
        isActive: prevActive.size > 0 ? prevActive.has((_t = ch.id) !== null && _t !== void 0 ? _t : '') : !anyActive && i === 0,
    }); });
    await youtubeRef(uid, sub).set({
        googleId: sub,
        accountName: (_d = (_c = me.name) !== null && _c !== void 0 ? _c : me.email) !== null && _d !== void 0 ? _d : '',
        email: (_e = me.email) !== null && _e !== void 0 ? _e : '',
        profilePictureUrl: (_f = me.picture) !== null && _f !== void 0 ? _f : '',
        channels,
        connectedAt: prev.exists ? prev.get('connectedAt') : firestore_1.FieldValue.serverTimestamp(),
        lastRefreshed: firestore_1.FieldValue.serverTimestamp(),
        tokenStore: 'server',
    }, { merge: true });
}
// ── callables ────────────────────────────────────────────────────────────
exports.googleLinkService = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e, _f, _g;
    const uid = (0, gmailUser_1.uidOf)(request);
    const d = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    // One service, or several picked together (one Google consent screen).
    const picked = (Array.isArray(d.services) ? d.services.slice(0, 10) : [d.service]).map(serviceOf);
    const code = str(d.serverAuthCode, 2048);
    if (!code)
        throw new https_1.HttpsError('invalid-argument', 'Missing Google authorization code.');
    const auth = await client();
    let tokens;
    try {
        ({ tokens } = await auth.getToken(code));
    }
    catch (e) {
        logger.warn('[googleLinkService] code exchange failed', { error: String(e) });
        throw new https_1.HttpsError('permission-denied', 'Google did not accept the sign-in. Please try again.');
    }
    const granted = ((_b = tokens.scope) !== null && _b !== void 0 ? _b : '').split(' ').filter(Boolean);
    // A service counts only when every one of its scopes was ticked.
    const linked = picked.filter(([, def]) => def.scopes.every((s) => granted.includes(s)));
    if (!linked.length) {
        const label = picked.length === 1 ? picked[0][1].label : 'the services you picked';
        throw new https_1.HttpsError('permission-denied', `Please tick every permission for ${label} on Google’s screen.`);
    }
    const ids = linked.map(([id]) => id);
    auth.setCredentials(tokens);
    const me = (await googleapis_1.google.oauth2({ version: 'v2', auth }).userinfo.get()).data;
    const sub = (_c = me.id) !== null && _c !== void 0 ? _c : '';
    if (!sub)
        throw new https_1.HttpsError('failed-precondition', 'Google didn’t say which account this is. Please try again.');
    const email = (_d = me.email) !== null && _d !== void 0 ? _d : '';
    const prev = await tokenRef(uid, sub).get();
    const refreshEnc = tokens.refresh_token
        ? await (0, gmailUser_1.encrypt)(tokens.refresh_token, uid)
        : prev.get('refreshToken');
    if (!refreshEnc) {
        throw new https_1.HttpsError('failed-precondition', 'Google didn’t grant offline access. Remove Oneova at myaccount.google.com/permissions and try again.');
    }
    const scopes = Array.from(new Set([...((_e = prev.get('scopes')) !== null && _e !== void 0 ? _e : []), ...granted]));
    await tokenRef(uid, sub).set({ refreshToken: refreshEnc, email, scopes, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    // Gmail holds a copy of this account's token: keep it current.
    const gmail = await (0, gmailUser_1.gmailTokenRef)(uid).get();
    if (ids.includes('gmail')) {
        await linkGmail(uid, sub, email, refreshEnc, granted);
    }
    else if (gmail.get('googleSub') === sub && tokens.refresh_token) {
        await (0, gmailUser_1.gmailTokenRef)(uid).set({ refreshToken: refreshEnc }, { merge: true });
    }
    if (ids.includes('youtube')) {
        try {
            await syncYoutube(uid, sub, me, auth);
        }
        catch (e) {
            logger.warn('[googleLinkService] YouTube channel sync failed', { error: String(e) });
        }
    }
    const acc = await accountRef(uid, sub).get();
    await accountRef(uid, sub).set(Object.assign({ sub,
        email, name: (_f = me.name) !== null && _f !== void 0 ? _f : '', photoUrl: (_g = me.picture) !== null && _g !== void 0 ? _g : '', grantedScopes: scopes, tokenStore: 'server', services: Object.fromEntries(ids.map((id) => [id, { status: 'connected', linkedAt: firestore_1.FieldValue.serverTimestamp() }])), updatedAt: firestore_1.FieldValue.serverTimestamp() }, (acc.exists ? {} : { createdAt: firestore_1.FieldValue.serverTimestamp() })), { merge: true });
    return { ok: true, sub, email, linked: ids, skipped: picked.map(([id]) => id).filter((id) => !ids.includes(id)) };
});
exports.googleUnlinkService = (0, https_1.onCall)(async (request) => {
    var _a;
    const uid = (0, gmailUser_1.uidOf)(request);
    const d = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const sub = subOf(d.sub);
    const [service] = serviceOf(d.service);
    // Older on-phone YouTube links have no Google services account: nothing to do.
    if (!(await accountRef(uid, sub).get()).exists)
        return { ok: true };
    if (service === 'gmail' && (await (0, gmailUser_1.gmailTokenRef)(uid).get()).get('googleSub') === sub) {
        await (0, gmailUser_1.clearToken)(uid);
    }
    if (service === 'youtube')
        await youtubeRef(uid, sub).delete();
    await accountRef(uid, sub).set({ services: { [service]: firestore_1.FieldValue.delete() }, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    return { ok: true };
});
exports.googleRemoveAccount = (0, https_1.onCall)(async (request) => {
    var _a;
    const uid = (0, gmailUser_1.uidOf)(request);
    const sub = subOf((_a = request.data) === null || _a === void 0 ? void 0 : _a.sub);
    const stored = await refreshTokenFor(uid, sub).catch(() => null);
    if (stored) {
        try {
            await (await client()).revokeToken(stored.token);
        }
        catch (e) {
            logger.warn('[googleRemoveAccount] revoke failed (token may already be gone)', { error: String(e) });
        }
    }
    if ((await (0, gmailUser_1.gmailTokenRef)(uid).get()).get('googleSub') === sub)
        await (0, gmailUser_1.clearToken)(uid);
    const batch = db().batch();
    batch.delete(tokenRef(uid, sub));
    batch.delete(accountRef(uid, sub));
    batch.delete(youtubeRef(uid, sub));
    await batch.commit();
    return { ok: true };
});
exports.googleAccessToken = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c;
    const uid = (0, gmailUser_1.uidOf)(request);
    const d = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const sub = subOf(d.sub);
    const [service, def] = serviceOf(d.service);
    if (!def.deviceToken)
        throw new https_1.HttpsError('permission-denied', `${def.label} is used through Oneova’s server only.`);
    const acc = await accountRef(uid, sub).get();
    if (acc.get(`services.${service}.status`) !== 'connected') {
        throw new https_1.HttpsError('failed-precondition', `Turn on ${def.label} in Profile → Google services first.`);
    }
    const stored = await refreshTokenFor(uid, sub);
    if (!stored)
        throw new https_1.HttpsError('failed-precondition', `Turn on ${def.label} in Profile → Google services first.`);
    const auth = await client();
    auth.setCredentials({ refresh_token: stored.token });
    try {
        const { token } = await auth.getAccessToken();
        if (!token)
            throw new Error('no access token');
        return { accessToken: token, expiresAt: (_b = auth.credentials.expiry_date) !== null && _b !== void 0 ? _b : Date.now() + 50 * 60 * 1000, scopes: def.scopes };
    }
    catch (e) {
        const msg = String((_c = e.message) !== null && _c !== void 0 ? _c : e);
        if (/invalid_grant/.test(msg)) {
            await markNeedsReconnect(uid, sub);
            throw new https_1.HttpsError('failed-precondition', `Google access was removed. Reconnect ${def.label} in Profile → Google services.`);
        }
        logger.warn('[googleAccessToken] refresh failed', { service, error: msg });
        throw new https_1.HttpsError('internal', 'Couldn’t reach Google. Try again.');
    }
});
//# sourceMappingURL=googleLink.js.map