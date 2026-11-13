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
exports.gmailCall = exports.gmailDisconnect = exports.gmailStatus = exports.gmailConnect = exports.gmailStatusRef = exports.gmailTokenRef = exports.GMAIL_SCOPES = void 0;
exports.encryptWith = encryptWith;
exports.decryptWith = decryptWith;
exports.encrypt = encrypt;
exports.decrypt = decrypt;
exports.clearToken = clearToken;
exports.oauth = oauth;
exports.uidOf = uidOf;
/**
 * Each Oneova user's own Gmail, connected in Connected accounts.
 *
 *   gmailConnect({ serverAuthCode })  exchange Google's one-time server code
 *                                     for a refresh token, store it encrypted
 *   gmailStatus()                     connected email + scopes
 *   gmailDisconnect()                 revoke at Google and delete everything
 *   gmailCall({ action, ... })        list / get / send / reply / modify / trash
 *
 * The refresh token lives under the user's own document at
 * `users/{uid}/secure_tokens/gmail` (server only; rules deny every client,
 * owner and admin included). It is encrypted with AES-256-GCM and the uid is
 * bound in as associated data, so a blob copied to another user's doc won't
 * decrypt. The app only sees a status doc at
 * `users/{uid}/social_connections/gmail`, also server-written.
 * Tokens from the old top-level `gmail_tokens/{uid}` location are moved on
 * first use.
 *
 * Setup (once, project mpepe-2b4bd):
 *   - GOOGLE_WEB_CLIENT_ID in functions/.env.mpepe-2b4bd (the Web client from
 *     google-services.json, client_type 3).
 *   - Secrets (optional; Gmail stays off until both exist and are readable,
 *     see optionalSecrets.ts):
 *       GOOGLE_OAUTH_CLIENT_SECRET  that Web client's secret (Cloud Console → Credentials)
 *       GMAIL_TOKEN_KEY             32 random bytes, base64: `openssl rand -base64 32`
 *   - Gmail API enabled, scopes on the OAuth consent screen. Restricted scopes:
 *     up to 100 test users until Google verification + security assessment.
 */
const crypto = __importStar(require("crypto"));
const googleapis_1 = require("googleapis");
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const optionalSecrets_1 = require("./optionalSecrets");
const webClientId = (0, params_1.defineString)('GOOGLE_WEB_CLIENT_ID', { default: '' });
const db = () => (0, firestore_1.getFirestore)();
exports.GMAIL_SCOPES = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/gmail.modify',
];
// ── encryption ────────────────────────────────────────────────────────────
async function key() {
    const k = await (0, optionalSecrets_1.optionalSecret)('GMAIL_TOKEN_KEY');
    const buf = k ? Buffer.from(k, 'base64') : Buffer.alloc(0);
    if (buf.length !== 32)
        throw new https_1.HttpsError('failed-precondition', 'Gmail connection is not set up on the server yet.');
    return buf;
}
/** `v2.iv.tag.data`, base64 parts; [uid] is the GCM associated data. */
function encryptWith(k, plain, uid) {
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv('aes-256-gcm', k, iv);
    c.setAAD(Buffer.from(uid, 'utf8'));
    const enc = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
    return ['v2', ...[iv, c.getAuthTag(), enc].map((b) => b.toString('base64'))].join('.');
}
/** Reads `v2.` blobs (uid-bound) and the original `iv.tag.data` format. */
function decryptWith(k, blob, uid) {
    const parts = blob.split('.');
    const v2 = parts[0] === 'v2';
    const [iv, tag, enc] = (v2 ? parts.slice(1) : parts).map((s) => Buffer.from(s, 'base64'));
    const d = crypto.createDecipheriv('aes-256-gcm', k, iv);
    if (v2)
        d.setAAD(Buffer.from(uid, 'utf8'));
    d.setAuthTag(tag);
    return Buffer.concat([d.update(enc), d.final()]).toString('utf8');
}
async function encrypt(plain, uid) {
    return encryptWith(await key(), plain, uid);
}
async function decrypt(blob, uid) {
    return decryptWith(await key(), blob, uid);
}
// ── token storage ────────────────────────────────────────────────────────
const gmailTokenRef = (uid) => tokenRef(uid);
exports.gmailTokenRef = gmailTokenRef;
const tokenRef = (uid) => db().collection('users').doc(uid).collection('secure_tokens').doc('gmail');
const legacyTokenRef = (uid) => db().collection('gmail_tokens').doc(uid);
const gmailStatusRef = (uid) => statusRef(uid);
exports.gmailStatusRef = gmailStatusRef;
const statusRef = (uid) => db().collection('users').doc(uid).collection('social_connections').doc('gmail');
/** The user's stored token; moves one from the old top-level location if needed. */
async function loadToken(uid) {
    var _a, _b, _c, _d, _e;
    const snap = await tokenRef(uid).get();
    if (snap.exists && snap.get('refreshToken')) {
        return { refreshToken: snap.get('refreshToken'), email: (_a = snap.get('email')) !== null && _a !== void 0 ? _a : '' };
    }
    const legacy = await legacyTokenRef(uid).get();
    const enc = legacy.get('refreshToken');
    if (!enc)
        return null;
    const refreshToken = await encrypt(await decrypt(enc, uid), uid);
    const batch = db().batch();
    batch.set(tokenRef(uid), {
        refreshToken,
        email: (_b = legacy.get('email')) !== null && _b !== void 0 ? _b : '',
        scopes: (_c = legacy.get('scopes')) !== null && _c !== void 0 ? _c : [],
        connectedAt: (_d = legacy.get('connectedAt')) !== null && _d !== void 0 ? _d : firestore_1.FieldValue.serverTimestamp(),
        movedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    batch.delete(legacyTokenRef(uid));
    await batch.commit();
    return { refreshToken, email: (_e = legacy.get('email')) !== null && _e !== void 0 ? _e : '' };
}
/** Removes the token (both locations) and the public status doc. */
async function clearToken(uid) {
    const batch = db().batch();
    batch.delete(tokenRef(uid));
    batch.delete(legacyTokenRef(uid));
    batch.delete(statusRef(uid));
    await batch.commit();
}
// ── OAuth client ─────────────────────────────────────────────────────────
async function oauth() {
    const secret = await (0, optionalSecrets_1.optionalSecret)('GOOGLE_OAUTH_CLIENT_SECRET');
    if (!webClientId.value() || !secret) {
        throw new https_1.HttpsError('failed-precondition', 'Gmail connection is not set up on the server yet.');
    }
    // Android/iOS server auth codes are exchanged with an empty redirect URI.
    return new googleapis_1.google.auth.OAuth2(webClientId.value(), secret, '');
}
function uidOf(req) {
    var _a;
    const a = req.auth;
    if (!a || ((_a = a.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) === 'anonymous')
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return a.uid;
}
async function gmailFor(uid) {
    const stored = await loadToken(uid);
    if (!stored) {
        // A status doc without a token (e.g. written by an older app build) would
        // show Gmail as connected when it can't work: remove it.
        await statusRef(uid).delete().catch(() => undefined);
        throw new https_1.HttpsError('failed-precondition', 'Connect Gmail first (Connected accounts → Gmail).');
    }
    const client = await oauth();
    client.setCredentials({ refresh_token: await decrypt(stored.refreshToken, uid) });
    return googleapis_1.google.gmail({ version: 'v1', auth: client });
}
function str(v, max = 20000) {
    return String(v !== null && v !== void 0 ? v : '').slice(0, max);
}
// ── connect / status / disconnect ────────────────────────────────────────
exports.gmailConnect = (0, https_1.onCall)(async (request) => {
    var _a;
    var _b, _c;
    const uid = uidOf(request);
    const code = str((_a = request.data) === null || _a === void 0 ? void 0 : _a.serverAuthCode, 2048);
    if (!code)
        throw new https_1.HttpsError('invalid-argument', 'Missing Google authorization code.');
    const client = await oauth();
    let tokens;
    try {
        ({ tokens } = await client.getToken(code));
    }
    catch (e) {
        logger.warn('[gmailConnect] code exchange failed', { error: String(e) });
        throw new https_1.HttpsError('permission-denied', 'Google did not accept the sign-in. Please try connecting again.');
    }
    const granted = ((_b = tokens.scope) !== null && _b !== void 0 ? _b : '').split(' ');
    const missing = exports.GMAIL_SCOPES.filter((s) => !granted.includes(s));
    if (missing.length) {
        throw new https_1.HttpsError('permission-denied', 'Please allow all Gmail permissions on Google’s screen (read, send and organise).');
    }
    if (!tokens.refresh_token) {
        throw new https_1.HttpsError('failed-precondition', 'Google didn’t grant offline access. Remove Oneova at myaccount.google.com/permissions and connect again.');
    }
    client.setCredentials(tokens);
    const profile = await googleapis_1.google.gmail({ version: 'v1', auth: client }).users.getProfile({ userId: 'me' });
    const email = (_c = profile.data.emailAddress) !== null && _c !== void 0 ? _c : '';
    const batch = db().batch();
    batch.set(tokenRef(uid), {
        refreshToken: await encrypt(tokens.refresh_token, uid),
        email,
        scopes: granted,
        connectedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    batch.delete(legacyTokenRef(uid));
    batch.set(statusRef(uid), {
        platform: 'gmail',
        accountName: email,
        email,
        grantedScopes: exports.GMAIL_SCOPES,
        scopes: exports.GMAIL_SCOPES.map((s) => s.split('/').pop()),
        // The refresh token is held server-side (secure_tokens/gmail).
        tokenStore: 'server',
        connectedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return { ok: true, email };
});
exports.gmailStatus = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const stored = await loadToken(uid);
    return stored ? { connected: true, email: stored.email } : { connected: false };
});
exports.gmailDisconnect = (0, https_1.onCall)(async (request) => {
    var _a;
    const uid = uidOf(request);
    const stored = await loadToken(uid).catch(() => null);
    // A token linked through Google services (googleLink.ts) is shared with the
    // user's other Google services: revoking it would cut those off too.
    const shared = (_a = (await tokenRef(uid).get().catch(() => null))) === null || _a === void 0 ? void 0 : _a.get('googleSub');
    if (stored && !shared) {
        try {
            const client = await oauth();
            await client.revokeToken(await decrypt(stored.refreshToken, uid));
        }
        catch (e) {
            logger.warn('[gmailDisconnect] revoke failed (token may already be gone)', { error: String(e) });
        }
    }
    await clearToken(uid);
    if (shared) {
        // Linked through Google services: show Gmail as off on that account too.
        const acc = db().collection('users').doc(uid).collection('google_accounts').doc(String(shared));
        if ((await acc.get()).exists)
            await acc.set({ services: { gmail: firestore_1.FieldValue.delete() } }, { merge: true });
    }
    return { ok: true };
});
// ── mail actions ─────────────────────────────────────────────────────────
function header(m, name) {
    var _a, _b, _c;
    var _d;
    return (_d = (_c = (_b = (_a = m.payload) === null || _a === void 0 ? void 0 : _a.headers) === null || _b === void 0 ? void 0 : _b.find((h) => { var _a; return ((_a = h.name) !== null && _a !== void 0 ? _a : '').toLowerCase() === name.toLowerCase(); })) === null || _c === void 0 ? void 0 : _c.value) !== null && _d !== void 0 ? _d : '';
}
function bodyText(p) {
    var _a, _b;
    var _c;
    if (!p)
        return '';
    if (p.mimeType === 'text/plain' && ((_a = p.body) === null || _a === void 0 ? void 0 : _a.data))
        return Buffer.from(p.body.data, 'base64url').toString('utf8');
    for (const c of (_c = p.parts) !== null && _c !== void 0 ? _c : []) {
        const t = bodyText(c);
        if (t)
            return t;
    }
    if (p.mimeType === 'text/html' && ((_b = p.body) === null || _b === void 0 ? void 0 : _b.data)) {
        return Buffer.from(p.body.data, 'base64url')
            .toString('utf8')
            .replace(/<style[\s\S]*?<\/style>/g, '')
            .replace(/<[^>]+>/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }
    return '';
}
function rfc822(to, subject, body, inReplyTo) {
    const lines = [
        `To: ${to}`,
        `Subject: =?UTF-8?B?${Buffer.from(subject).toString('base64')}?=`,
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset="UTF-8"',
        'Content-Transfer-Encoding: base64',
    ];
    if (inReplyTo)
        lines.push(`In-Reply-To: ${inReplyTo}`, `References: ${inReplyTo}`);
    lines.push('', Buffer.from(body).toString('base64'));
    return Buffer.from(lines.join('\r\n')).toString('base64url');
}
function summary(m) {
    var _a, _b, _c, _d;
    return {
        id: m.id,
        threadId: m.threadId,
        from: header(m, 'From'),
        to: header(m, 'To'),
        subject: header(m, 'Subject'),
        date: header(m, 'Date'),
        internalDate: (_a = m.internalDate) !== null && _a !== void 0 ? _a : null,
        snippet: (_b = m.snippet) !== null && _b !== void 0 ? _b : '',
        unread: ((_c = m.labelIds) !== null && _c !== void 0 ? _c : []).includes('UNREAD'),
        starred: ((_d = m.labelIds) !== null && _d !== void 0 ? _d : []).includes('STARRED'),
    };
}
exports.gmailCall = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e, _f;
    const uid = uidOf(request);
    const d = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const gmail = await gmailFor(uid);
    try {
        switch (d.action) {
            case 'list': {
                const max = Math.min(Math.max(Number((_b = d.limit) !== null && _b !== void 0 ? _b : 20), 1), 50);
                const res = await gmail.users.messages.list({
                    userId: 'me',
                    q: str((_c = d.query) !== null && _c !== void 0 ? _c : 'in:inbox', 500),
                    maxResults: max,
                    pageToken: d.pageToken ? str(d.pageToken, 200) : undefined,
                });
                const msgs = await Promise.all(((_d = res.data.messages) !== null && _d !== void 0 ? _d : []).map((m) => gmail.users.messages.get({ userId: 'me', id: m.id, format: 'metadata', metadataHeaders: ['From', 'To', 'Subject', 'Date'] })));
                return { messages: msgs.map((r) => summary(r.data)), nextPageToken: (_e = res.data.nextPageToken) !== null && _e !== void 0 ? _e : null };
            }
            case 'get': {
                const r = await gmail.users.messages.get({ userId: 'me', id: str(d.id, 64), format: 'full' });
                return Object.assign(Object.assign({}, summary(r.data)), { messageId: header(r.data, 'Message-ID'), body: bodyText(r.data.payload).slice(0, 100000) });
            }
            case 'send': {
                const to = str(d.to, 500);
                if (!/^[^\s@]+@[^\s@]+\.[^\s@]+/.test(to))
                    throw new https_1.HttpsError('invalid-argument', 'Enter a valid email address.');
                const r = await gmail.users.messages.send({ userId: 'me', requestBody: { raw: rfc822(to, str(d.subject, 500), str(d.body)) } });
                return { ok: true, id: r.data.id };
            }
            case 'reply': {
                const orig = await gmail.users.messages.get({ userId: 'me', id: str(d.id, 64), format: 'metadata', metadataHeaders: ['From', 'Reply-To', 'Subject', 'Message-ID'] });
                const to = header(orig.data, 'Reply-To') || header(orig.data, 'From');
                const subj = header(orig.data, 'Subject');
                const r = await gmail.users.messages.send({
                    userId: 'me',
                    requestBody: {
                        threadId: orig.data.threadId,
                        raw: rfc822(to, /^re:/i.test(subj) ? subj : `Re: ${subj}`, str(d.body), header(orig.data, 'Message-ID')),
                    },
                });
                return { ok: true, id: r.data.id, to };
            }
            case 'modify': {
                const add = Array.isArray(d.add) ? d.add.slice(0, 5) : [];
                const remove = Array.isArray(d.remove) ? d.remove.slice(0, 5) : [];
                await gmail.users.messages.modify({ userId: 'me', id: str(d.id, 64), requestBody: { addLabelIds: add, removeLabelIds: remove } });
                return { ok: true };
            }
            case 'trash': {
                await gmail.users.messages.trash({ userId: 'me', id: str(d.id, 64) });
                return { ok: true };
            }
            default:
                throw new https_1.HttpsError('invalid-argument', 'Unknown Gmail action.');
        }
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        const msg = String((_f = e.message) !== null && _f !== void 0 ? _f : e);
        if (/invalid_grant/.test(msg)) {
            // The user removed access in their Google account: clean up.
            await clearToken(uid);
            throw new https_1.HttpsError('failed-precondition', 'Gmail access was removed. Connect Gmail again.');
        }
        logger.warn('[gmailCall] failed', { action: d.action, error: msg });
        throw new https_1.HttpsError('internal', 'Gmail request failed. Try again.');
    }
});
//# sourceMappingURL=gmailUser.js.map