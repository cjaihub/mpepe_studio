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
exports.verifyEmailCode = exports.sendEmailCode = void 0;
/**
 * Email one-time codes, sent from the team's Gmail (see mailer.ts).
 *
 *   sendEmailCode({ purpose, email?, deviceLabel?, platform? })
 *   verifyEmailCode({ purpose, email?, code })
 *
 * Purposes (both need a signed-in user):
 *   verify_email     signed in; marks the email verified (or adopts the new
 *                    email the user just proved they own).
 *   sensitive_action signed in; a fresh "it's really me" check before risky
 *                    changes (stamps security_state/{uid}.stepUpAt).
 *
 * Codes: 6 digits, stored only as a salted hash, 10 minutes, one use,
 * 5 wrong tries. Sending: one per minute and 5 per hour per address, plus a
 * per-IP cap.
 *
 * There is deliberately no "sign in with an email code": Oneova sign-in needs
 * two checks (password + SMS code), and a passwordless email login would skip
 * them. SMS login codes are auto-filled in the app via Google's SMS User
 * Consent API instead.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const mailTemplates_1 = require("./mailTemplates");
const mailer_1 = require("./mailer");
const securityMail_1 = require("./securityMail");
const db = () => (0, firestore_1.getFirestore)();
const CODE_MINUTES = 10;
const MAX_TRIES = 5;
const RESEND_SECONDS = 60;
const MAX_PER_HOUR = 5;
const MAX_PER_IP_HOUR = 20;
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const PURPOSES = ['verify_email', 'sensitive_action'];
function cleanEmail(v) {
    const e = String(v !== null && v !== void 0 ? v : '').trim().toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) && e.length <= 254 ? e : null;
}
function purposeOf(v) {
    const p = String(v !== null && v !== void 0 ? v : '');
    if (!PURPOSES.includes(p))
        throw new https_1.HttpsError('invalid-argument', 'Unknown code purpose.');
    return p;
}
function maskIp(ip) {
    if (!ip)
        return '';
    if (ip.includes(':'))
        return ip.split(':').slice(0, 3).join(':') + ':…';
    const p = ip.split('.');
    return p.length === 4 ? `${p[0]}.${p[1]}.${p[2]}.x` : '';
}
async function resolveTarget(data, authUid) {
    var _a;
    if (!authUid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const user = await (0, auth_1.getAuth)().getUser(authUid);
    const email = (_a = cleanEmail(data.email)) !== null && _a !== void 0 ? _a : cleanEmail(user.email);
    if (!email)
        throw new https_1.HttpsError('failed-precondition', 'Add an email address to your account first.');
    return { email, user };
}
exports.sendEmailCode = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    var _c, _d;
    const data = ((_c = request.data) !== null && _c !== void 0 ? _c : {});
    const purpose = purposeOf(data.purpose);
    const { email, user } = await resolveTarget(data, (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid);
    const ip = (_d = (_b = request.rawRequest) === null || _b === void 0 ? void 0 : _b.ip) !== null && _d !== void 0 ? _d : null;
    const now = Date.now();
    // Per-IP cap (all addresses).
    if (ip) {
        const ipRef = db().collection('email_code_ips').doc(sha(ip));
        const ok = await db().runTransaction(async (tx) => {
            var _a, _b;
            const s = await tx.get(ipRef);
            const start = (_a = s.get('windowStart')) !== null && _a !== void 0 ? _a : 0;
            const count = now - start > 3600000 ? 0 : ((_b = s.get('count')) !== null && _b !== void 0 ? _b : 0);
            if (count >= MAX_PER_IP_HOUR)
                return false;
            tx.set(ipRef, { windowStart: count === 0 ? now : start, count: count + 1 }, { merge: true });
            return true;
        });
        if (!ok)
            throw new https_1.HttpsError('resource-exhausted', 'Too many codes from this network. Try again in an hour.');
    }
    const docId = sha(`${email}|${purpose}`);
    const ref = db().collection('email_codes').doc(docId);
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
    const limit = await db().runTransaction(async (tx) => {
        var _a, _b, _c;
        const s = await tx.get(ref);
        const sentAt = (_a = s.get('sentAt')) !== null && _a !== void 0 ? _a : 0;
        const windowStart = (_b = s.get('windowStart')) !== null && _b !== void 0 ? _b : 0;
        const inWindow = now - windowStart < 3600000;
        const sends = inWindow ? ((_c = s.get('sends')) !== null && _c !== void 0 ? _c : 0) : 0;
        if (now - sentAt < RESEND_SECONDS * 1000)
            return { wait: Math.ceil((RESEND_SECONDS * 1000 - (now - sentAt)) / 1000) };
        if (sends >= MAX_PER_HOUR)
            return { wait: Math.ceil((3600000 - (now - windowStart)) / 1000) };
        tx.set(ref, {
            purpose,
            uid: user.uid,
            codeHash: sha(`${code}:${docId}`),
            expiresAt: firestore_1.Timestamp.fromMillis(now + CODE_MINUTES * 60000),
            tries: 0,
            sentAt: now,
            windowStart: inWindow ? windowStart : now,
            sends: sends + 1,
        });
        return { wait: 0 };
    });
    if (limit.wait > 0) {
        throw new https_1.HttpsError('resource-exhausted', `Please wait ${limit.wait < 120 ? `${limit.wait} seconds` : `${Math.ceil(limit.wait / 60)} minutes`} before asking for another code.`);
    }
    const from = [
        { label: 'Device', value: [data.deviceLabel, data.platform].filter((x) => typeof x === 'string' && x).join(' · ').slice(0, 80) },
        { label: 'IP address', value: maskIp(ip) },
        { label: 'Time', value: new Date(now).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }) + ' UTC' },
    ];
    // A code the user didn't ask for while signed in means someone else has the session.
    const secureUrl = await (0, securityMail_1.createSecurityLink)(user.uid, null, 'secure');
    const sent = await (0, mailer_1.sendMail)(email, (0, mailTemplates_1.codeEmail)({ code, purpose, minutes: CODE_MINUTES, requestedFrom: from, secureUrl }));
    if (!sent) {
        await ref.delete();
        throw new https_1.HttpsError('unavailable', 'We couldn’t send the email right now. Try again in a minute.');
    }
    return { ok: true, expiresInMinutes: CODE_MINUTES, resendInSeconds: RESEND_SECONDS };
});
exports.verifyEmailCode = (0, https_1.onCall)(async (request) => {
    var _a;
    var _b, _c;
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const purpose = purposeOf(data.purpose);
    const code = String((_c = data.code) !== null && _c !== void 0 ? _c : '').replace(/\D/g, '');
    if (code.length !== 6)
        throw new https_1.HttpsError('invalid-argument', 'Enter the 6-digit code.');
    const { email, user } = await resolveTarget(data, (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid);
    const docId = sha(`${email}|${purpose}`);
    const ref = db().collection('email_codes').doc(docId);
    const result = await db().runTransaction(async (tx) => {
        var _a;
        const s = await tx.get(ref);
        if (!s.exists || !s.get('codeHash'))
            return { error: 'expired' };
        if (s.get('expiresAt').toMillis() < Date.now()) {
            tx.update(ref, { codeHash: null });
            return { error: 'expired' };
        }
        const tries = (_a = s.get('tries')) !== null && _a !== void 0 ? _a : 0;
        if (tries >= MAX_TRIES)
            return { error: 'locked' };
        const expected = Buffer.from(String(s.get('codeHash')), 'hex');
        const given = Buffer.from(sha(`${code}:${docId}`), 'hex');
        if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) {
            tx.update(ref, { tries: tries + 1 });
            return { error: 'wrong', left: MAX_TRIES - tries - 1 };
        }
        tx.update(ref, { codeHash: null, usedAt: firestore_1.FieldValue.serverTimestamp() });
        return { error: null };
    });
    if (result.error === 'expired')
        throw new https_1.HttpsError('deadline-exceeded', 'This code expired. Ask for a new one.');
    if (result.error === 'locked')
        throw new https_1.HttpsError('resource-exhausted', 'Too many wrong tries. Ask for a new code.');
    if (result.error === 'wrong') {
        throw new https_1.HttpsError('invalid-argument', result.left > 0 ? `That code isn’t right. ${result.left} tries left.` : 'Too many wrong tries. Ask for a new code.');
    }
    switch (purpose) {
        case 'verify_email':
            await (0, auth_1.getAuth)().updateUser(user.uid, { email, emailVerified: true });
            return { ok: true, email };
        case 'sensitive_action':
            await db().collection('security_state').doc(user.uid).set({ stepUpAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
            return { ok: true };
    }
});
//# sourceMappingURL=emailCodes.js.map