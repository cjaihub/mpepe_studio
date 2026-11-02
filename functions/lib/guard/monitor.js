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
exports.guardBackfillContacts = exports.accountLookup = exports.guardSweep = exports.guardReverseAction = exports.guardCheckLinks = exports.guardOnProfileWrite = exports.guardScanContentComment = exports.guardScanPostComment = void 0;
exports.scanChatMessage = scanChatMessage;
exports.restrictedUntil = restrictedUntil;
/**
 * Ova Guard — background content monitor + protected lookups.
 *
 * Triggers (cheap first: heuristics → Web Risk only for links → Vertex
 * Flash-Lite only for texts the heuristics already flagged, cached, with a
 * daily budget; see reputation.ts):
 *   guardScanPostComment / guardScanContentComment   new comments
 *   guardOnProfileWrite                              bio / website / name
 *       changes, profile-change bursts, impersonation of verified names,
 *       contact index + (opt-in) moving email/phone off the public profile.
 *   scanChatMessage()                                called by guardOnMessage
 *       (security.ts) for messages the server can read (not E2E).
 * Callables:
 *   guardCheckLinks      link reputation for the app (E2E chats send only the
 *                        links, never the message).
 *   guardReverseAction   admin undo of any automatic action.
 *   accountLookup        sign-in "is there an account for this number/email"
 *                        without reading other people's profiles.
 *   guardBackfillContacts admin, one-off: fills contact_index (and, when
 *                        GUARD_SPLIT_PRIVATE_FIELDS=true, moves the fields).
 * Schedule:
 *   guardSweep           every 30 min: lifts expired restrictions.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const auth_1 = require("firebase-admin/auth");
const firestore_2 = require("firebase-admin/firestore");
const linkSafety_1 = require("./linkSafety");
const reputation_1 = require("./reputation");
const actions_1 = require("./actions");
const protect_1 = require("./protect");
const security_1 = require("../security");
const gif_logic_1 = require("../liveStudio/gif_logic");
const db = () => (0, firestore_2.getFirestore)();
/** What the app shows on a message, comment or profile (no message text). */
function safetyField(v) {
    return {
        verdict: v.verdict,
        reasons: v.reasons.slice(0, 4),
        blockedLinks: v.links.filter((l) => l.verdict === 'dangerous').map((l) => l.url).slice(0, 5),
        categories: v.categories,
        by: 'ova_guard',
        checkedAt: firestore_2.FieldValue.serverTimestamp(),
    };
}
/** Repeat offenders: 3+ dangerous posts in a day → pause + human review. */
async function escalateRepeats(uid, scope, source, reason, targetPath) {
    if ((await (0, actions_1.recentActions)(uid, source, 86400000)) < 3)
        return;
    await (0, actions_1.takeAction)({ uid, action: 'rate_limit', scope, durationMs: 6 * 3600000, reason: `Several dangerous links were blocked: ${reason}`, source });
    await (0, actions_1.takeAction)({ uid, action: 'escalate_admin', reason: `Repeated dangerous links (${scope})`, source, targetPath });
}
// ─────────────── Chat messages (called by guardOnMessage) ───────────────
async function scanChatMessage(ref, data) {
    var _a, _b, _c;
    if (data.isEncrypted === true || data.mediaEncrypted === true)
        return; // E2E: the app checks links itself
    const text = typeof data.text === 'string' ? data.text : '';
    const senderId = String((_a = data.senderId) !== null && _a !== void 0 ? _a : '');
    if (!text || !senderId)
        return;
    const quick = (0, linkSafety_1.analyzeText)(text);
    if (!quick.links.length && quick.points < 25)
        return;
    const v = await (0, reputation_1.checkText)(text);
    if (v.verdict === 'safe')
        return;
    await ref.set({ safety: safetyField(v) }, { merge: true });
    if (v.verdict === 'dangerous') {
        const source = 'scan:chat';
        await (0, actions_1.takeAction)({ uid: senderId, action: 'notify_user', source, reason: `A link you sent was blocked: ${(_b = v.reasons[0]) !== null && _b !== void 0 ? _b : 'it is on a list of dangerous sites'}. If you didn’t send it, secure your account.`, notifyTitle: 'Dangerous link blocked' });
        await (0, security_1.recordSecurityEvent)(senderId, 'phishing_sent', { details: { where: 'chat', reasons: v.reasons } });
        await escalateRepeats(senderId, 'messaging', source, (_c = v.reasons[0]) !== null && _c !== void 0 ? _c : '', ref.path);
    }
}
// ─────────────── Comments ───────────────
async function scanComment(ref, data) {
    var _a, _b, _c;
    if (!data)
        return;
    // GIF comments may only carry a GIPHY image (from lsGifSearch); anything
    // else is hidden so the GIF slot can't be used to post arbitrary links.
    if (data.type === 'gif' || data.gif !== undefined) {
        if ((0, gif_logic_1.parseCommentGif)((_a = data.gif) !== null && _a !== void 0 ? _a : null) === 'invalid' || (data.type === 'gif' && !data.gif)) {
            await ref.set({ isModerated: true, safety: { verdict: 'dangerous', reasons: ['This GIF is not from the GIF picker'], blockedLinks: [], categories: [], by: 'ova_guard', checkedAt: firestore_2.FieldValue.serverTimestamp() } }, { merge: true });
            return;
        }
    }
    const text = typeof data.content === 'string' ? data.content : '';
    const authorId = String((_b = data.authorId) !== null && _b !== void 0 ? _b : '');
    if (!text || !authorId)
        return;
    const quick = (0, linkSafety_1.analyzeText)(text);
    if (!quick.links.length && quick.points < 25)
        return;
    const v = await (0, reputation_1.checkText)(text);
    if (v.verdict === 'safe')
        return;
    await ref.set({ safety: safetyField(v) }, { merge: true });
    if (v.verdict === 'dangerous') {
        const source = 'scan:comment';
        const reason = (_c = v.reasons[0]) !== null && _c !== void 0 ? _c : 'It contains a dangerous link';
        await (0, actions_1.takeAction)({ uid: authorId, action: 'hide_content', targetPath: ref.path, source, reason: `Comment hidden until reviewed: ${reason}` });
        await (0, security_1.recordSecurityEvent)(authorId, 'phishing_sent', { details: { where: 'comment', reasons: v.reasons } });
        await escalateRepeats(authorId, 'comments', source, reason, ref.path);
    }
}
exports.guardScanPostComment = (0, firestore_1.onDocumentCreated)('posts/{postId}/comments/{commentId}', (e) => e.data ? scanComment(e.data.ref, e.data.data()) : Promise.resolve());
exports.guardScanContentComment = (0, firestore_1.onDocumentCreated)('content/{postId}/comments/{commentId}', (e) => e.data ? scanComment(e.data.ref, e.data.data()) : Promise.resolve());
// ─────────────── Profiles ───────────────
const PRIVATE_FIELDS = ['email', 'phoneNumber', 'phone', 'recoveryEmail', 'linkedEmails', 'dateOfBirth', 'birthday'];
const WATCHED = ['displayName', 'username', 'bio', 'website', 'photoUrl', 'avatarUrl'];
const splitOn = () => process.env.GUARD_SPLIT_PRIVATE_FIELDS === 'true';
async function indexContacts(uid, d) {
    const batch = db().batch();
    let n = 0;
    for (const p of [d.phoneNumber, d.phone]) {
        if (typeof p === 'string' && /^\+[1-9]\d{6,14}$/.test(p)) {
            batch.set(db().collection('contact_index').doc(protect_1.contactKey.phone(p)), { uid, kind: 'phone' }, { merge: true });
            n++;
        }
    }
    const emails = [d.email, d.recoveryEmail, ...(Array.isArray(d.linkedEmails) ? d.linkedEmails : [])];
    for (const e of emails) {
        if (typeof e === 'string' && e.includes('@') && e.length < 200) {
            batch.set(db().collection('contact_index').doc(protect_1.contactKey.email(e)), { uid, kind: 'email' }, { merge: true });
            n++;
        }
    }
    if (n)
        await batch.commit();
}
/** Copies contact fields to users/{uid}/private/contact and removes them from the public profile. */
async function movePrivateFields(uid, d) {
    const present = PRIVATE_FIELDS.filter((f) => d[f] !== undefined);
    if (!present.length)
        return;
    const copy = Object.fromEntries(present.map((f) => [f, d[f]]));
    await db().doc(`users/${uid}/private/contact`).set(Object.assign(Object.assign({}, copy), { updatedAt: firestore_2.FieldValue.serverTimestamp() }), { merge: true });
    await db().doc(`users/${uid}`).update(Object.fromEntries(present.map((f) => [f, firestore_2.FieldValue.delete()])));
}
async function bumpProfileChanges(uid) {
    const ref = db().collection('security_counters').doc(uid);
    return db().runTransaction(async (tx) => {
        var _a, _b;
        const s = await tx.get(ref);
        const start = Number((_a = s.get('profStart')) !== null && _a !== void 0 ? _a : 0);
        const fresh = Date.now() - start > 3600000;
        const n = (fresh ? 0 : Number((_b = s.get('profCount')) !== null && _b !== void 0 ? _b : 0)) + 1;
        tx.set(ref, { profStart: fresh ? Date.now() : start, profCount: n }, { merge: true });
        return n;
    });
}
exports.guardOnProfileWrite = (0, firestore_1.onDocumentWritten)('users/{uid}', async (event) => {
    var _a, _b, _c, _d, _e, _f;
    var _g, _h, _j, _k;
    const uid = event.params.uid;
    const before = (_g = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data()) !== null && _g !== void 0 ? _g : {};
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    if (!after)
        return;
    const contactChanged = PRIVATE_FIELDS.some((f) => after[f] !== undefined && JSON.stringify(after[f]) !== JSON.stringify(before[f]));
    if (contactChanged)
        await indexContacts(uid, after);
    if (splitOn() && PRIVATE_FIELDS.some((f) => after[f] !== undefined))
        await movePrivateFields(uid, after);
    const changed = WATCHED.filter((f) => after[f] !== before[f]);
    if (!changed.length || !((_f = (_e = event.data) === null || _e === void 0 ? void 0 : _e.before) === null || _f === void 0 ? void 0 : _f.exists))
        return;
    // Names of accounts an admin verified (verifiedBy is admin-only in the
    // rules; the signup isVerified flag is self-chosen, so it is not trusted).
    const nameKeys = [after.displayName, after.username].filter((x) => typeof x === 'string' && x.length >= 4).map((x) => (0, linkSafety_1.skeleton)(x.normalize('NFKD').replace(/[^\p{L}\p{N}]/gu, '')));
    if (after.isVerified === true && typeof after.verifiedBy === 'string') {
        await Promise.all(nameKeys.map((k) => db().collection('guard_verified_names').doc(k.slice(0, 120)).set({ uid }, { merge: true })));
    }
    else if (changed.includes('displayName') || changed.includes('username')) {
        for (const k of nameKeys) {
            const hit = await db().collection('guard_verified_names').doc(k.slice(0, 120)).get();
            if (hit.exists && hit.get('uid') !== uid) {
                await (0, actions_1.takeAction)({ uid, action: 'escalate_admin', source: 'scan:impersonation', targetPath: `users/${uid}`, reason: `Profile name copies a verified account (${hit.get('uid')})` });
                await db().doc(`users/${uid}`).set({ safety: { impersonationOf: hit.get('uid'), by: 'ova_guard' } }, { merge: true });
                break;
            }
        }
    }
    // Bio / website links.
    if (changed.includes('bio') || changed.includes('website')) {
        const text = `${(_h = after.bio) !== null && _h !== void 0 ? _h : ''} ${(_j = after.website) !== null && _j !== void 0 ? _j : ''}`.trim();
        if (text && ((0, linkSafety_1.extractUrls)(text).length || (0, linkSafety_1.analyzeText)(text).points >= 25)) {
            const v = await (0, reputation_1.checkText)(text);
            if (v.verdict !== 'safe')
                await db().doc(`users/${uid}`).set({ safety: { bio: safetyField(v) } }, { merge: true });
            if (v.verdict === 'dangerous') {
                await (0, actions_1.takeAction)({ uid, action: 'notify_user', source: 'scan:bio', notifyTitle: 'Link in your bio blocked', reason: `A link in your bio was blocked: ${(_k = v.reasons[0]) !== null && _k !== void 0 ? _k : ''}` });
            }
        }
    }
    // Many profile changes in an hour is a classic takeover sign.
    if ((await bumpProfileChanges(uid)) === 6) {
        await (0, security_1.recordSecurityEvent)(uid, 'profile_change_spike', { details: { count: 6, fields: changed } });
    }
});
// ─────────────── Callables ───────────────
/** Link reputation for links the app is about to show (E2E chats) or send. */
exports.guardCheckLinks = (0, https_1.onCall)(async (request) => {
    var _a;
    const uid = (0, protect_1.requireAccount)(request);
    const raw = (_a = request.data) === null || _a === void 0 ? void 0 : _a.urls;
    if (!Array.isArray(raw) || raw.length === 0 || raw.length > 10)
        throw new https_1.HttpsError('invalid-argument', 'Send 1 to 10 links.');
    await (0, protect_1.limit)(uid, 'links', 120, 10 * 60000);
    // One answer per link sent, in the same order.
    const out = await Promise.all(raw.map(async (u) => {
        var _a;
        const input = String(u).slice(0, 500);
        const finding = (0, linkSafety_1.analyzeUrl)((_a = (0, linkSafety_1.extractUrls)(input, 1)[0]) !== null && _a !== void 0 ? _a : input);
        if (!finding)
            return { url: input, host: null, verdict: 'safe', reasons: [] };
        const [rep] = await (0, reputation_1.checkLinks)({ links: [finding], points: 0, reasons: [], categories: [] });
        return { url: input, host: rep.host, verdict: rep.verdict, reasons: rep.reasons.slice(0, 3) };
    }));
    return { links: out };
});
exports.guardReverseAction = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c;
    const admin = await (0, protect_1.requireAdmin)(request);
    const d = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const id = String((_b = d.actionId) !== null && _b !== void 0 ? _b : '');
    if (!/^[A-Za-z0-9]{10,40}$/.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Missing action.');
    const ok = await (0, actions_1.reverseAction)(id, admin, String((_c = d.reason) !== null && _c !== void 0 ? _c : '').slice(0, 300));
    if (!ok)
        throw new https_1.HttpsError('failed-precondition', 'That action is not active.');
    return { ok };
});
exports.guardSweep = (0, scheduler_1.onSchedule)('every 30 minutes', async () => {
    const due = await db()
        .collection('security_actions')
        .where('status', '==', 'active')
        .where('expiresAt', '<=', firestore_2.Timestamp.now())
        .limit(300)
        .get();
    for (const d of due.docs)
        await (0, actions_1.reverseAction)(d.id, 'ova_guard', 'Time limit ended', 'expired');
    if (due.size)
        logger.info('guard sweep lifted actions', { count: due.size });
});
/**
 * Sign-in lookup. Returns only what the sign-in header shows. The phone or
 * e-mail itself comes back only to someone already signed in with it.
 */
exports.accountLookup = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c;
    var _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const d = ((_d = request.data) !== null && _d !== void 0 ? _d : {});
    const phone = typeof d.phone === 'string' ? d.phone.trim() : '';
    const email = typeof d.email === 'string' ? d.email.trim().toLowerCase() : '';
    if (phone && !/^\+[1-9]\d{6,14}$/.test(phone))
        throw new https_1.HttpsError('invalid-argument', 'Bad number.');
    if (email && !/^[^@\s]{1,64}@[^@\s]{1,190}$/.test(email))
        throw new https_1.HttpsError('invalid-argument', 'Bad e-mail.');
    if (!phone && !email)
        throw new https_1.HttpsError('invalid-argument', 'Send a phone or e-mail.');
    await (0, protect_1.limit)((0, protect_1.callerIp)(request), 'lookup_ip', 60, 15 * 60000);
    await (0, protect_1.limit)((_e = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid) !== null && _e !== void 0 ? _e : null, 'lookup_uid', 40, 15 * 60000);
    const uid = phone ? await (0, protect_1.uidForPhone)(phone) : await (0, protect_1.uidForEmail)(email);
    if (!uid)
        return { found: false };
    const p = (await db().doc(`users/${uid}`).get()).data();
    if (!p)
        return { found: false };
    const token = (_b = request.auth) === null || _b === void 0 ? void 0 : _b.token;
    const ownsEmail = !!email && (token === null || token === void 0 ? void 0 : token.email) === email && (token === null || token === void 0 ? void 0 : token.email_verified) === true;
    const ownsPhone = !!phone && (token === null || token === void 0 ? void 0 : token.phone_number) === phone;
    let accountPhone = null;
    if (ownsEmail || ownsPhone) {
        const priv = (await db().doc(`users/${uid}/private/contact`).get()).data();
        accountPhone = ((_h = (_g = (_f = priv === null || priv === void 0 ? void 0 : priv.phoneNumber) !== null && _f !== void 0 ? _f : p.phoneNumber) !== null && _g !== void 0 ? _g : p.phone) !== null && _h !== void 0 ? _h : null);
        if (!accountPhone)
            accountPhone = (_j = (_c = (await (0, auth_1.getAuth)().getUser(uid).catch(() => null))) === null || _c === void 0 ? void 0 : _c.phoneNumber) !== null && _j !== void 0 ? _j : null;
    }
    return {
        found: true,
        uid,
        displayName: (_l = (_k = p.displayName) !== null && _k !== void 0 ? _k : p.name) !== null && _l !== void 0 ? _l : null,
        username: (_m = p.username) !== null && _m !== void 0 ? _m : null,
        photoUrl: (_p = (_o = p.photoUrl) !== null && _o !== void 0 ? _o : p.avatarUrl) !== null && _p !== void 0 ? _p : null,
        authPasswordLinked: p.authPasswordLinked === true,
        legacyPasswordPending: p.legacyPasswordPending === true || !!p.passwordHash || !!p.password,
        phoneNumber: phone || accountPhone,
    };
});
exports.guardBackfillContacts = (0, https_1.onCall)({ timeoutSeconds: 540 }, async (request) => {
    var _a;
    var _b;
    await (0, protect_1.requireAdmin)(request);
    let after = (_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.after) !== null && _b !== void 0 ? _b : null;
    let indexed = 0;
    let moved = 0;
    for (let page = 0; page < 10; page++) {
        let q = db().collection('users').orderBy('__name__').limit(300);
        if (after)
            q = q.startAfter(after);
        const snap = await q.get();
        if (snap.empty)
            return { indexed, moved, done: true };
        for (const doc of snap.docs) {
            const d = doc.data();
            if (PRIVATE_FIELDS.some((f) => d[f] !== undefined)) {
                await indexContacts(doc.id, d);
                indexed++;
                if (splitOn()) {
                    await movePrivateFields(doc.id, d);
                    moved++;
                }
            }
        }
        after = snap.docs[snap.docs.length - 1].id;
    }
    return { indexed, moved, done: false, after };
});
/** Restriction check for server-written content (live comments etc.). */
async function restrictedUntil(uid, scope) {
    var _a;
    var _b;
    const s = await db().collection('security_state').doc(uid).get();
    return (_b = (_a = s.get(`restrictions.${scope}`)) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : 0;
}
//# sourceMappingURL=monitor.js.map