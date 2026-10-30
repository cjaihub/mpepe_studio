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
exports.moveLegacyPasswordHashesNow = exports.moveLegacyPasswordHashesDaily = exports.guardOnRelationship = exports.guardOnMessage = exports.guardExplainEvent = exports.guardRevokeDevice = exports.guardRespond = exports.checkLegacyPassword = exports.guardReportAuthFailure = exports.guardReportSession = exports.loginContext = void 0;
exports.score = score;
exports.recordSecurityEvent = recordSecurityEvent;
exports.secureAccount = secureAccount;
/**
 * Ova Guard: per-account security monitor.
 *
 * Every security event is written here, server-side, to
 * `security_events/{uid}/events/{id}` (clients can read their own, never
 * write). Each event gets a score from the plain rules in `score()` below,
 * so every alert can say exactly why it fired. Gemini is only used on
 * request to summarise an event in friendly words; it never sets the score.
 *
 * Sources:
 *   - guardReportSession (app start / sign-in): new device, new country,
 *     impossible travel, one session used from two devices or countries,
 *     password / email / phone changes (detected from the Auth user record,
 *     not trusted from the client).
 *   - guardReportAuthFailure (signed out): failed passwords / SMS codes as
 *     reported by a device. Rate limited per IP; lower trust than server data.
 *   - checkLegacyPassword: server-side check for old in-profile password
 *     hashes; its failures are server-verified.
 *   - Firestore triggers: message bursts (chats/{id}/messages) and
 *     follow/unfollow bursts (relationships/{a_b}).
 *   - recordSecurityEvent() from biometric.ts: new fingerprint keys.
 *
 * High-risk events create an urgent `notifications` doc (pushed by
 * onNotificationCreated) and stay "open" until the user answers
 * "Yes, it was me" or "Secure my account" (guardRespond), which revokes all
 * sessions and fingerprint keys and forces every device to sign in again.
 *
 * Geo: set GUARD_IPINFO_TOKEN in functions/.env to resolve IPs (country +
 * coordinates via ipinfo.io). Without it, only the device's network country
 * is known and impossible-travel checks are skipped.
 */
const crypto = __importStar(require("crypto"));
const axios_1 = __importDefault(require("axios"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const auth_1 = require("firebase-admin/auth");
const firestore_2 = require("firebase-admin/firestore");
const genai_1 = require("@google/genai");
const geminiSecret = (0, params_1.defineSecret)('GEMINI_API_KEY');
const db = () => (0, firestore_2.getFirestore)();
const HIGH = 70;
const MEDIUM = 40;
// ─────────────────────────── Scoring rules ───────────────────────────
/**
 * Explainable risk rules. Each rule adds points and a reason the user sees.
 * >= 70 is high (push + "Was this you?"), >= 40 medium, otherwise low.
 */
function score(type, d = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    let s = 0;
    const reasons = [];
    const add = (points, reason) => {
        s += points;
        reasons.push(reason);
    };
    switch (type) {
        case 'sign_in':
            add(0, 'Sign-in from a device you have used before');
            break;
        case 'new_device':
            if (d.firstDevice) {
                add(5, 'First device on this account');
            }
            else {
                add(40, 'Sign-in from a device we have not seen on your account');
            }
            if (d.newCountry)
                add(30, `First sign-in from ${(_a = d.country) !== null && _a !== void 0 ? _a : 'a new country'}`);
            if (d.recentFailures && Number(d.recentFailures) >= 5)
                add(20, `${d.recentFailures} failed attempts shortly before`);
            break;
        case 'new_country':
            add(45, `First sign-in from ${(_b = d.country) !== null && _b !== void 0 ? _b : 'a new country'}`);
            if (d.recentFailures && Number(d.recentFailures) >= 5)
                add(20, `${d.recentFailures} failed attempts shortly before`);
            break;
        case 'impossible_travel':
            add(75, `Signed in ${Math.round(Number((_c = d.km) !== null && _c !== void 0 ? _c : 0))} km away ${Math.round(Number((_d = d.minutes) !== null && _d !== void 0 ? _d : 0))} min after the previous sign-in (faster than a plane)`);
            break;
        case 'auth_failures': {
            const n = Number((_e = d.count) !== null && _e !== void 0 ? _e : 0);
            if (n >= 10)
                add(70, `${n} wrong ${d.kind === 'otp' ? 'SMS codes' : 'passwords'} in 15 minutes`);
            else
                add(45, `${n} wrong ${d.kind === 'otp' ? 'SMS codes' : 'passwords'} in 15 minutes`);
            if (d.verified)
                add(5, 'Checked by Oneova servers');
            break;
        }
        case 'password_changed':
            add(50, 'Your password was changed');
            if (d.newDevice)
                add(30, 'Changed from a device added in the last 24 hours');
            break;
        case 'email_changed':
            add(70, 'The email on your account was changed');
            if (d.newDevice)
                add(20, 'Changed from a device added in the last 24 hours');
            break;
        case 'phone_changed':
            add(70, 'The phone number on your account was changed');
            if (d.newDevice)
                add(20, 'Changed from a device added in the last 24 hours');
            break;
        case 'message_spike': {
            const n = Number((_f = d.count) !== null && _f !== void 0 ? _f : 0);
            const chats = Number((_g = d.chats) !== null && _g !== void 0 ? _g : 0);
            if (n >= 200 || chats >= 60)
                add(75, `${n} messages to ${chats} chats in a few minutes`);
            else
                add(50, `${n} messages to ${chats} chats in a few minutes`);
            break;
        }
        case 'follow_spike': {
            const n = Number((_h = d.count) !== null && _h !== void 0 ? _h : 0);
            if (n >= 150)
                add(75, `${n} follows/unfollows in 10 minutes`);
            else
                add(50, `${n} follows/unfollows in 10 minutes`);
            break;
        }
        case 'session_reuse':
            add(85, String((_j = d.why) !== null && _j !== void 0 ? _j : 'The same sign-in session was used from two places'));
            break;
        case 'biometric_key_added':
            add(25, 'Fingerprint sign-in was turned on for a device');
            if (d.newDevice)
                add(30, 'The device was added in the last 24 hours');
            break;
        case 'account_secured':
            add(0, 'You secured your account: other sessions and fingerprint keys were removed');
            break;
    }
    const value = Math.min(100, s);
    return { score: value, risk: value >= HIGH ? 'high' : value >= MEDIUM ? 'medium' : 'low', reasons };
}
const TITLES = {
    sign_in: 'Signed in',
    new_device: 'New device signed in',
    new_country: 'Sign-in from a new country',
    impossible_travel: 'Impossible-travel sign-in',
    auth_failures: 'Failed sign-in attempts',
    password_changed: 'Password changed',
    email_changed: 'Email changed',
    phone_changed: 'Phone number changed',
    message_spike: 'Unusual messaging activity',
    follow_spike: 'Unusual follow activity',
    session_reuse: 'Session used from two places',
    biometric_key_added: 'Fingerprint sign-in turned on',
    account_secured: 'Account secured',
};
// ─────────────────────────── Recording ───────────────────────────
/** Writes one scored event and raises an alert when it is high risk. */
async function recordSecurityEvent(uid, type, ctx = {}) {
    var _a;
    var _b, _c, _d, _e, _f, _g;
    const details = (_b = ctx.details) !== null && _b !== void 0 ? _b : {};
    const scored = score(type, Object.assign(Object.assign({}, details), { country: (_a = ctx.geo) === null || _a === void 0 ? void 0 : _a.country }));
    const ref = db().collection('security_events').doc(uid).collection('events').doc();
    const needsAnswer = scored.risk === 'high' && type !== 'account_secured';
    await ref.set({
        type,
        title: TITLES[type],
        score: scored.score,
        risk: scored.risk,
        reasons: scored.reasons,
        status: needsAnswer ? 'open' : 'closed',
        deviceId: (_c = ctx.deviceId) !== null && _c !== void 0 ? _c : null,
        deviceLabel: (_d = ctx.deviceLabel) !== null && _d !== void 0 ? _d : null,
        platform: (_e = ctx.platform) !== null && _e !== void 0 ? _e : null,
        ipMasked: maskIp(ctx.ip),
        geo: (_f = ctx.geo) !== null && _f !== void 0 ? _f : null,
        details,
        at: firestore_2.FieldValue.serverTimestamp(),
    });
    const stateRef = db().collection('security_state').doc(uid);
    await stateRef.set(Object.assign({ lastEventAt: firestore_2.FieldValue.serverTimestamp(), lastEventType: type }, (needsAnswer ? { openHighRisk: firestore_2.FieldValue.increment(1) } : {})), { merge: true });
    await refreshRiskLevel(uid);
    if (needsAnswer) {
        await db().collection('notifications').add({
            userId: uid,
            category: 'security',
            type: 'security_alert',
            priority: 'urgent',
            title: `Ova Guard: ${TITLES[type]}`,
            body: `${(_g = scored.reasons[0]) !== null && _g !== void 0 ? _g : 'Unusual activity'}. Was this you?`,
            deepLink: '/profile/security',
            payload: { route: '/profile/security', eventId: ref.id },
            isRead: false,
            timestamp: firestore_2.FieldValue.serverTimestamp(),
            createdAt: firestore_2.FieldValue.serverTimestamp(),
        });
    }
    return ref.id;
}
/** Account risk = worst open event, else the worst event in the last 7 days. */
async function refreshRiskLevel(uid) {
    const events = db().collection('security_events').doc(uid).collection('events');
    const open = await events.where('status', '==', 'open').limit(20).get();
    let level = 'low';
    let reason = 'No unusual activity';
    if (!open.empty) {
        level = 'high';
        reason = `${open.size} alert${open.size === 1 ? '' : 's'} need your answer`;
    }
    else {
        const week = await events
            .where('at', '>=', firestore_2.Timestamp.fromMillis(Date.now() - 7 * 86400000))
            .orderBy('at', 'desc')
            .limit(50)
            .get();
        const medium = week.docs.filter((d) => d.get('risk') === 'medium').length;
        if (medium > 0) {
            level = 'medium';
            reason = `${medium} event${medium === 1 ? '' : 's'} worth a look this week`;
        }
    }
    await db().collection('security_state').doc(uid).set({ riskLevel: level, riskReason: reason, openHighRisk: open.size, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
}
// ─────────────────────────── Helpers ───────────────────────────
function sha256(v) {
    return crypto.createHash('sha256').update(v).digest('hex');
}
function safeEqualStr(a, b) {
    const ab = Buffer.from(a);
    const bb = Buffer.from(b);
    return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}
function maskIp(ip) {
    if (!ip)
        return null;
    if (ip.includes(':'))
        return ip.split(':').slice(0, 3).join(':') + ':…';
    const p = ip.split('.');
    return p.length === 4 ? `${p[0]}.${p[1]}.${p[2]}.x` : null;
}
function clientIp(request) {
    var _a, _b, _c;
    var _d;
    const fwd = String((_d = (_b = (_a = request.rawRequest) === null || _a === void 0 ? void 0 : _a.headers) === null || _b === void 0 ? void 0 : _b['x-forwarded-for']) !== null && _d !== void 0 ? _d : '');
    const ip = fwd.split(',')[0].trim() || ((_c = request.rawRequest) === null || _c === void 0 ? void 0 : _c.ip) || '';
    return ip || null;
}
function str(v, max = 80) {
    if (v === undefined || v === null)
        return null;
    const s = String(v).trim();
    return s ? s.slice(0, max) : null;
}
function deviceIdFrom(v) {
    const id = String(v !== null && v !== void 0 ? v : '');
    if (!/^[0-9a-f]{32}$/.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Bad device.');
    return id;
}
async function geoFor(request, ip, deviceCountry) {
    var _a, _b, _c, _d, _e;
    var _f;
    const token = process.env.GUARD_IPINFO_TOKEN;
    if (token && ip) {
        try {
            const res = await axios_1.default.get(`https://ipinfo.io/${encodeURIComponent(ip)}/json`, {
                params: { token },
                timeout: 2500,
            });
            const [lat, lng] = String((_f = (_a = res.data) === null || _a === void 0 ? void 0 : _a.loc) !== null && _f !== void 0 ? _f : '').split(',').map(Number);
            return {
                country: str((_b = res.data) === null || _b === void 0 ? void 0 : _b.country, 2),
                city: str((_c = res.data) === null || _c === void 0 ? void 0 : _c.city, 60),
                lat: Number.isFinite(lat) ? lat : null,
                lng: Number.isFinite(lng) ? lng : null,
                source: 'ip',
            };
        }
        catch (e) {
            logger.warn('ipinfo lookup failed', { error: String(e) });
        }
    }
    const header = str((_e = (_d = request.rawRequest) === null || _d === void 0 ? void 0 : _d.headers) === null || _e === void 0 ? void 0 : _e['x-appengine-country'], 2);
    if (header && header !== 'ZZ')
        return { country: header.toUpperCase(), source: 'ip' };
    return { country: deviceCountry ? deviceCountry.toUpperCase().slice(0, 2) : null, source: deviceCountry ? 'device' : null };
}
function km(a, b) {
    const r = 6371;
    const dLat = ((b.lat - a.lat) * Math.PI) / 180;
    const dLng = ((b.lng - a.lng) * Math.PI) / 180;
    const h = Math.sin(dLat / 2) ** 2 +
        Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
    return 2 * r * Math.asin(Math.sqrt(h));
}
function requireUser(request) {
    var _a;
    const auth = request.auth;
    if (!auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    if (((_a = auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) === 'anonymous') {
        throw new https_1.HttpsError('permission-denied', 'Guests have no account to protect.');
    }
    return auth;
}
// Devices seen by Ova Guard (server-written). Separate from the login gate's
// `users/{uid}/trusted_devices`, which only an SMS check may fill.
const devicesCol = (uid) => db().collection('security_state').doc(uid).collection('devices');
const trustedCol = (uid) => db().collection('users').doc(uid).collection('trusted_devices');
async function recentFailures(uid) {
    var _a, _b;
    const c = await db().collection('security_counters').doc(uid).get();
    const since = Number((_a = c.get('failWindowStart')) !== null && _a !== void 0 ? _a : 0);
    return Date.now() - since < 15 * 60000 ? Number((_b = c.get('failCount')) !== null && _b !== void 0 ? _b : 0) : 0;
}
// ─────────────────────────── Callables ───────────────────────────
/**
 * Called by the app on start and after each sign-in. Updates this device's
 * entry and records new-device / location / session / account-change events.
 * Returns whether this device was logged out remotely.
 */
/**
 * Network context for the app's login history row: masked IP and the IP's
 * region. Read-only; writes nothing.
 */
exports.loginContext = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c;
    requireUser(request);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const ip = clientIp(request);
    const geo = await geoFor(request, ip, str(data.networkCountry, 2));
    return {
        ipMasked: maskIp(ip),
        country: geo.source === 'ip' ? (_b = geo.country) !== null && _b !== void 0 ? _b : null : null,
        city: geo.source === 'ip' ? (_c = geo.city) !== null && _c !== void 0 ? _c : null : null,
        region: null,
    };
});
exports.guardReportSession = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e, _f;
    var _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1, _2, _3;
    const auth = requireUser(request);
    const uid = auth.uid;
    const data = ((_g = request.data) !== null && _g !== void 0 ? _g : {});
    const deviceId = deviceIdFrom(data.deviceId);
    const label = (_h = str(data.deviceLabel)) !== null && _h !== void 0 ? _h : 'Unknown device';
    const platform = str(data.platform, 20);
    const appVersion = str(data.appVersion, 20);
    const ip = clientIp(request);
    const geo = await geoFor(request, ip, str(data.networkCountry, 2));
    const authTime = Number((_j = auth.token.auth_time) !== null && _j !== void 0 ? _j : 0);
    const provider = String((_k = (_a = auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) !== null && _k !== void 0 ? _k : '');
    const now = Date.now();
    const stateRef = db().collection('security_state').doc(uid);
    const deviceRef = devicesCol(uid).doc(deviceId);
    const [state, device, otherDevices, user] = await Promise.all([
        stateRef.get(),
        deviceRef.get(),
        devicesCol(uid).limit(1).get(),
        (0, auth_1.getAuth)().getUser(uid),
    ]);
    // Logged out remotely, or signed in before "Secure my account".
    const revokedAt = (_l = (_b = state.get('sessionsRevokedAt')) === null || _b === void 0 ? void 0 : _b.toMillis()) !== null && _l !== void 0 ? _l : 0;
    if (device.exists && device.get('revoked') === true && ((_m = (_d = (_c = device.get('revokedAt')) === null || _c === void 0 ? void 0 : _c.toMillis) === null || _d === void 0 ? void 0 : _d.call(_c)) !== null && _m !== void 0 ? _m : 0) > authTime * 1000) {
        return { loggedOut: true };
    }
    if (revokedAt > authTime * 1000)
        return { loggedOut: true };
    const ctx = { deviceId, deviceLabel: label, platform, ip, geo };
    const known = device.exists && device.get('revoked') !== true;
    const sessions = ((_o = state.get('sessions')) !== null && _o !== void 0 ? _o : {});
    const isNewSession = authTime > 0 && !sessions[String(authTime)];
    const failures = isNewSession ? await recentFailures(uid) : 0;
    // 1) The same sign-in (auth_time) showing up on another device or country.
    const prev = sessions[String(authTime)];
    if (prev && prev.d !== deviceId) {
        await recordSecurityEvent(uid, 'session_reuse', Object.assign(Object.assign({}, ctx), { details: { why: 'The same sign-in session was used from a second device' } }));
    }
    else if (prev && prev.c && geo.country && prev.c !== geo.country && now - prev.t < 3600000) {
        await recordSecurityEvent(uid, 'session_reuse', Object.assign(Object.assign({}, ctx), { details: { why: `The same session was used from ${prev.c} and ${geo.country} within an hour` } }));
    }
    // 2) New sign-in: device, country, impossible travel.
    const knownCountries = (_p = state.get('knownCountries')) !== null && _p !== void 0 ? _p : [];
    const newCountry = !!geo.country && knownCountries.length > 0 && !knownCountries.includes(geo.country);
    if (isNewSession) {
        if (!known) {
            await recordSecurityEvent(uid, 'new_device', Object.assign(Object.assign({}, ctx), { details: { firstDevice: otherDevices.empty, newCountry, recentFailures: failures, provider } }));
        }
        else if (newCountry) {
            await recordSecurityEvent(uid, 'new_country', Object.assign(Object.assign({}, ctx), { details: { recentFailures: failures, provider } }));
        }
        else {
            await recordSecurityEvent(uid, 'sign_in', Object.assign(Object.assign({}, ctx), { details: { provider } }));
        }
        const last = state.get('lastLogin');
        if ((last === null || last === void 0 ? void 0 : last.lat) != null && (last === null || last === void 0 ? void 0 : last.lng) != null && geo.lat != null && geo.lng != null && last.at) {
            const distance = km({ lat: last.lat, lng: last.lng }, { lat: geo.lat, lng: geo.lng });
            const minutes = Math.max(1, (now - last.at) / 60000);
            if (distance > 500 && distance / (minutes / 60) > 900) {
                await recordSecurityEvent(uid, 'impossible_travel', Object.assign(Object.assign({}, ctx), { details: { km: distance, minutes } }));
            }
        }
    }
    // 3) Account changes, read from the Auth record (cannot be faked by a client).
    const snap = state.get('authSnapshot');
    const deviceAgeMs = device.exists ? now - ((_q = (_f = (_e = device.get('firstSeenAt')) === null || _e === void 0 ? void 0 : _e.toMillis) === null || _f === void 0 ? void 0 : _f.call(_e)) !== null && _q !== void 0 ? _q : now) : 0;
    const newDevice = !known || deviceAgeMs < 86400000;
    if (snap) {
        if (((_r = snap.email) !== null && _r !== void 0 ? _r : null) !== ((_s = user.email) !== null && _s !== void 0 ? _s : null)) {
            await recordSecurityEvent(uid, 'email_changed', Object.assign(Object.assign({}, ctx), { details: { newDevice } }));
        }
        if (((_t = snap.phone) !== null && _t !== void 0 ? _t : null) !== ((_u = user.phoneNumber) !== null && _u !== void 0 ? _u : null)) {
            await recordSecurityEvent(uid, 'phone_changed', Object.assign(Object.assign({}, ctx), { details: { newDevice } }));
        }
        // tokensValidAfterTime moves when the password changes (or sessions are revoked).
        if (snap.validAfter && user.tokensValidAfterTime && snap.validAfter !== user.tokensValidAfterTime &&
            new Date(user.tokensValidAfterTime).getTime() > revokedAt + 5000) {
            await recordSecurityEvent(uid, 'password_changed', Object.assign(Object.assign({}, ctx), { details: { newDevice } }));
        }
    }
    // Remember this session and device.
    const keep = Object.entries(sessions)
        .filter(([, v]) => now - v.t < 30 * 86400000)
        .sort((a, b) => b[1].t - a[1].t)
        .slice(0, 20);
    const nextSessions = Object.fromEntries(keep);
    if (authTime > 0)
        nextSessions[String(authTime)] = { d: deviceId, c: (_v = geo.country) !== null && _v !== void 0 ? _v : null, t: now };
    await Promise.all([
        deviceRef.set(Object.assign({ label,
            platform,
            appVersion, lastSeenAt: firestore_2.FieldValue.serverTimestamp(), lastCountry: (_w = geo.country) !== null && _w !== void 0 ? _w : null, lastCity: (_x = geo.city) !== null && _x !== void 0 ? _x : null, lastIpMasked: maskIp(ip), lastProvider: provider, revoked: false }, (device.exists ? {} : { firstSeenAt: firestore_2.FieldValue.serverTimestamp() })), { merge: true }),
        stateRef.set(Object.assign(Object.assign({ sessions: nextSessions, knownCountries: geo.country ? firestore_2.FieldValue.arrayUnion(geo.country) : knownCountries, authSnapshot: {
                email: (_y = user.email) !== null && _y !== void 0 ? _y : null,
                phone: (_z = user.phoneNumber) !== null && _z !== void 0 ? _z : null,
                validAfter: (_0 = user.tokensValidAfterTime) !== null && _0 !== void 0 ? _0 : null,
            } }, (isNewSession ? { lastLogin: { at: now, lat: (_1 = geo.lat) !== null && _1 !== void 0 ? _1 : null, lng: (_2 = geo.lng) !== null && _2 !== void 0 ? _2 : null, country: (_3 = geo.country) !== null && _3 !== void 0 ? _3 : null } } : {})), { updatedAt: firestore_2.FieldValue.serverTimestamp() }), { merge: true }),
    ]);
    // Once the password lives in Firebase Auth, the old hash is not needed.
    if (user.providerData.some((p) => p.providerId === 'password')) {
        await db().collection('legacy_password_hashes').doc(uid).delete().catch(() => undefined);
    }
    return { loggedOut: false };
});
/**
 * Failed password / SMS code, reported by a signed-out device. Rate limited
 * per IP so it can't be used to flood someone with alerts.
 */
exports.guardReportAuthFailure = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const phone = String((_b = data.phone) !== null && _b !== void 0 ? _b : '');
    const kind = data.kind === 'otp' ? 'otp' : 'password';
    if (!/^\+[1-9]\d{6,14}$/.test(phone))
        throw new https_1.HttpsError('invalid-argument', 'Bad number.');
    const ip = clientIp(request);
    if (!(await allowFromIp(ip, 'fail', 30)))
        return { ok: true };
    const user = await db().collection('users').where('phoneNumber', '==', phone).limit(1).get();
    if (user.empty)
        return { ok: true };
    await countFailure(user.docs[0].id, kind, false, ip, str(data.deviceLabel));
    return { ok: true };
});
/** Simple fixed-window limiter per IP (30 calls / 15 min by default). */
async function allowFromIp(ip, bucket, max) {
    if (!ip)
        return true;
    const ref = db().collection('security_rate').doc(`${bucket}_${sha256(ip).slice(0, 32)}`);
    return db().runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(ref);
        const start = Number((_a = snap.get('start')) !== null && _a !== void 0 ? _a : 0);
        const count = Date.now() - start < 15 * 60000 ? Number((_b = snap.get('count')) !== null && _b !== void 0 ? _b : 0) : 0;
        if (count >= max)
            return false;
        tx.set(ref, {
            start: count === 0 ? Date.now() : start,
            count: count + 1,
            expiresAt: firestore_2.Timestamp.fromMillis(Date.now() + 86400000),
        });
        return true;
    });
}
/** Counts failures in a 15-minute window and records an event at 5 and 10. */
async function countFailure(uid, kind, verified, ip, deviceLabel) {
    const ref = db().collection('security_counters').doc(uid);
    const count = await db().runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(ref);
        const start = Number((_a = snap.get('failWindowStart')) !== null && _a !== void 0 ? _a : 0);
        const fresh = Date.now() - start >= 15 * 60000;
        const n = (fresh ? 0 : Number((_b = snap.get('failCount')) !== null && _b !== void 0 ? _b : 0)) + 1;
        tx.set(ref, { failWindowStart: fresh ? Date.now() : start, failCount: n }, { merge: true });
        return n;
    });
    if (count === 5 || count === 10) {
        await recordSecurityEvent(uid, 'auth_failures', {
            ip,
            deviceLabel,
            details: { count, kind, verified },
        });
    }
}
/**
 * Checks a password against an old in-profile hash on the server, so clients
 * never need to read password hashes. Works signed out (by phone) or signed
 * in (own account).
 */
exports.checkLegacyPassword = (0, https_1.onCall)(async (request) => {
    var _a;
    var _b, _c, _d, _e, _f, _g, _h;
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const password = String((_c = data.password) !== null && _c !== void 0 ? _c : '');
    const phone = String((_d = data.phone) !== null && _d !== void 0 ? _d : '');
    if (!password || password.length > 256)
        throw new https_1.HttpsError('invalid-argument', 'Bad password.');
    const ip = clientIp(request);
    if (!(await allowFromIp(ip, 'legacy', 20))) {
        throw new https_1.HttpsError('resource-exhausted', 'Too many attempts. Try again in 15 minutes.');
    }
    let uid = null;
    if (/^\+[1-9]\d{6,14}$/.test(phone)) {
        const q = await db().collection('users').where('phoneNumber', '==', phone).limit(1).get();
        uid = q.empty ? null : q.docs[0].id;
    }
    if (!uid && request.auth && ((_a = request.auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) !== 'anonymous')
        uid = request.auth.uid;
    if (!uid)
        return { match: false };
    if ((await recentFailures(uid)) >= 10) {
        throw new https_1.HttpsError('resource-exhausted', 'Too many attempts. Try again in 15 minutes.');
    }
    const [legacy, profile] = await Promise.all([
        db().collection('legacy_password_hashes').doc(uid).get(),
        db().collection('users').doc(uid).get(),
    ]);
    const hash = String((_f = (_e = legacy.get('passwordHash')) !== null && _e !== void 0 ? _e : profile.get('passwordHash')) !== null && _f !== void 0 ? _f : '');
    const plain = String((_h = (_g = legacy.get('password')) !== null && _g !== void 0 ? _g : profile.get('password')) !== null && _h !== void 0 ? _h : '');
    let match = false;
    if (hash)
        match = safeEqualStr(hash, sha256(password));
    else if (plain)
        match = safeEqualStr(plain, password);
    if (!match)
        await countFailure(uid, 'password', true, ip, null);
    return { match };
});
/**
 * Secure my account: end every session, drop every fingerprint key and every
 * remembered device, so each phone must pass the two checks again. Shared by
 * guardRespond and the e-mail "Secure my account" link (securityMail.ts).
 */
async function secureAccount(uid, eventId) {
    var _a, _b, _c, _d;
    const keys = await db().collection('biometric_keys').where('uid', '==', uid).get();
    const devices = await devicesCol(uid).get();
    const trusted = await trustedCol(uid).get();
    const events = db().collection('security_events').doc(uid).collection('events');
    const open = await events.where('status', '==', 'open').get();
    const batch = db().batch();
    keys.docs.forEach((d) => batch.delete(d.ref));
    [...devices.docs, ...trusted.docs].forEach((d) => batch.set(d.ref, { revoked: true, revokedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true }));
    open.docs.forEach((d) => batch.update(d.ref, { status: 'secured', answeredAt: firestore_2.FieldValue.serverTimestamp() }));
    batch.set(db().collection('security_state').doc(uid), { sessionsRevokedAt: firestore_2.FieldValue.serverTimestamp(), sessions: {}, openHighRisk: 0 }, { merge: true });
    await batch.commit();
    const user = await (0, auth_1.getAuth)().getUser(uid);
    const claims = Object.assign({}, ((_a = user.customClaims) !== null && _a !== void 0 ? _a : {}));
    delete claims.mfaSessions;
    await (0, auth_1.getAuth)().setCustomUserClaims(uid, claims);
    await (0, auth_1.getAuth)().revokeRefreshTokens(uid);
    // Keep the snapshot in step so the revoke isn't reported as a password change.
    const after = await (0, auth_1.getAuth)().getUser(uid);
    await db().collection('security_state').doc(uid).set({ authSnapshot: { email: (_b = after.email) !== null && _b !== void 0 ? _b : null, phone: (_c = after.phoneNumber) !== null && _c !== void 0 ? _c : null, validAfter: (_d = after.tokensValidAfterTime) !== null && _d !== void 0 ? _d : null } }, { merge: true });
    await recordSecurityEvent(uid, 'account_secured', {
        details: { biometricKeysRemoved: keys.size, devicesSignedOut: devices.size, eventId: eventId !== null && eventId !== void 0 ? eventId : null },
    });
    return { biometricKeysRemoved: keys.size, devicesSignedOut: devices.size };
}
/** Answers an alert: "Yes, it was me" or "Secure my account". */
exports.guardRespond = (0, https_1.onCall)(async (request) => {
    var _a;
    const auth = requireUser(request);
    const uid = auth.uid;
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const eventId = str(data.eventId, 40);
    const action = data.action === 'secure' ? 'secure' : 'confirm';
    const events = db().collection('security_events').doc(uid).collection('events');
    if (action === 'confirm') {
        if (!eventId)
            throw new https_1.HttpsError('invalid-argument', 'Missing event.');
        const ref = events.doc(eventId);
        const snap = await ref.get();
        if (!snap.exists)
            throw new https_1.HttpsError('not-found', 'Event not found.');
        await ref.update({ status: 'confirmed', answeredAt: firestore_2.FieldValue.serverTimestamp() });
        // A confirmed new device or country becomes known.
        const country = snap.get('geo.country');
        if (country) {
            await db().collection('security_state').doc(uid).set({ knownCountries: firestore_2.FieldValue.arrayUnion(country) }, { merge: true });
        }
        await refreshRiskLevel(uid);
        return { ok: true };
    }
    return Object.assign({ ok: true }, (await secureAccount(uid, eventId)));
});
/**
 * "Log out" one device. Its fingerprint keys are deleted at once; the device
 * signs itself out when it next reaches Oneova (it watches its own entry).
 */
exports.guardRevokeDevice = (0, https_1.onCall)(async (request) => {
    var _a;
    const auth = requireUser(request);
    const deviceId = deviceIdFrom((_a = request.data) === null || _a === void 0 ? void 0 : _a.deviceId);
    const keys = await db().collection('biometric_keys').where('uid', '==', auth.uid).where('deviceId', '==', deviceId).get();
    const batch = db().batch();
    keys.docs.forEach((d) => batch.delete(d.ref));
    for (const ref of [devicesCol(auth.uid).doc(deviceId), trustedCol(auth.uid).doc(deviceId)]) {
        batch.set(ref, { revoked: true, revokedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
    }
    await batch.commit();
    return { ok: true };
});
/**
 * Plain-language explanation of one event by Gemini. The model only sees the
 * event's type, rule reasons, device and country (never messages), and its
 * text is advisory: risk and alerts come from the rules above.
 */
exports.guardExplainEvent = (0, https_1.onCall)({ secrets: [geminiSecret] }, async (request) => {
    var _a, _b, _c;
    var _d, _e, _f, _g;
    const auth = requireUser(request);
    const eventId = str((_a = request.data) === null || _a === void 0 ? void 0 : _a.eventId, 40);
    if (!eventId)
        throw new https_1.HttpsError('invalid-argument', 'Missing event.');
    const ref = db().collection('security_events').doc(auth.uid).collection('events').doc(eventId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'Event not found.');
    const cached = snap.get('aiSummary');
    if (cached)
        return { summary: cached };
    const apiKey = geminiSecret.value();
    if (!apiKey)
        throw new https_1.HttpsError('failed-precondition', 'AI is not configured.');
    const e = (_d = snap.data()) !== null && _d !== void 0 ? _d : {};
    const facts = {
        event: e.title,
        risk: e.risk,
        score: e.score,
        reasons: e.reasons,
        device: e.deviceLabel,
        platform: e.platform,
        country: (_e = (_b = e.geo) === null || _b === void 0 ? void 0 : _b.country) !== null && _e !== void 0 ? _e : null,
        city: (_f = (_c = e.geo) === null || _c === void 0 ? void 0 : _c.city) !== null && _f !== void 0 ? _f : null,
        status: e.status,
    };
    const ai = new genai_1.GoogleGenAI({ apiKey });
    const res = await ai.models.generateContent({
        model: 'gemini-2.5-flash',
        contents: [{ role: 'user', parts: [{ text: JSON.stringify(facts) }] }],
        config: {
            systemInstruction: 'You are Ova Guard, the security helper in the Oneova app. Explain this account security event to the account owner ' +
                'in 2-3 short, calm sentences, then one sentence on what to do if it was not them (tap "Secure my account"). ' +
                'Use only the facts given. Do not change the risk level, do not guess causes, no markdown.',
            maxOutputTokens: 200,
            temperature: 0.2,
        },
    });
    const summary = String((_g = res.text) !== null && _g !== void 0 ? _g : '').trim().slice(0, 800);
    if (summary)
        await ref.update({ aiSummary: summary });
    return { summary };
});
// ─────────────────────────── Activity triggers ───────────────────────────
/** Bumps a windowed counter; returns the new count and distinct targets. */
async function bumpWindow(ref, prefix, windowMs, target) {
    return db().runTransaction(async (tx) => {
        var _a, _b, _c, _d;
        const snap = await tx.get(ref);
        const start = Number((_a = snap.get(`${prefix}Start`)) !== null && _a !== void 0 ? _a : 0);
        const fresh = Date.now() - start >= windowMs;
        const count = (fresh ? 0 : Number((_b = snap.get(`${prefix}Count`)) !== null && _b !== void 0 ? _b : 0)) + 1;
        const targets = new Set(fresh ? [] : ((_c = snap.get(`${prefix}Targets`)) !== null && _c !== void 0 ? _c : []));
        if (target && targets.size < 200)
            targets.add(target);
        tx.set(ref, {
            [`${prefix}Start`]: fresh ? Date.now() : start,
            [`${prefix}Count`]: count,
            [`${prefix}Targets`]: [...targets],
        }, { merge: true });
        return { count, targets: targets.size, alertedAt: Number((_d = snap.get(`${prefix}AlertedAt`)) !== null && _d !== void 0 ? _d : 0) };
    });
}
async function markAlerted(ref, prefix) {
    await ref.set({ [`${prefix}AlertedAt`]: Date.now() }, { merge: true });
}
/** Message bursts: 80+ messages in 5 minutes, or 25+ different chats in 10. */
exports.guardOnMessage = (0, firestore_1.onDocumentCreated)('chats/{chatId}/messages/{messageId}', async (event) => {
    var _a;
    var _b;
    const senderId = String((_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.get('senderId')) !== null && _b !== void 0 ? _b : '');
    if (!senderId || senderId === 'guest')
        return;
    const ref = db().collection('security_counters').doc(senderId);
    const w = await bumpWindow(ref, 'msg', 10 * 60000, event.params.chatId);
    const spike = w.count >= 80 || w.targets >= 25;
    if (!spike || Date.now() - w.alertedAt < 30 * 60000)
        return;
    await markAlerted(ref, 'msg');
    await recordSecurityEvent(senderId, 'message_spike', { details: { count: w.count, chats: w.targets } });
});
/** Follow / unfollow bursts: 60+ changes in 10 minutes. */
exports.guardOnRelationship = (0, firestore_1.onDocumentWritten)('relationships/{relId}', async (event) => {
    var _a, _b, _c, _d;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    const wasFollow = (before === null || before === void 0 ? void 0 : before.status) === 'accepted' || (before === null || before === void 0 ? void 0 : before.status) === 'pending';
    const isFollow = (after === null || after === void 0 ? void 0 : after.status) === 'accepted' || (after === null || after === void 0 ? void 0 : after.status) === 'pending';
    if (wasFollow === isFollow)
        return;
    const relId = event.params.relId;
    const cut = relId.indexOf('_');
    if (cut <= 0)
        return;
    const actor = relId.slice(0, cut);
    const ref = db().collection('security_counters').doc(actor);
    const w = await bumpWindow(ref, 'follow', 10 * 60000, relId.slice(cut + 1));
    if (w.count < 60 || Date.now() - w.alertedAt < 30 * 60000)
        return;
    await markAlerted(ref, 'follow');
    await recordSecurityEvent(actor, 'follow_spike', { details: { count: w.count } });
});
// ─────────────────────────── Legacy password hashes ───────────────────────────
/**
 * Moves old password hashes out of the public `users` docs into
 * `legacy_password_hashes/{uid}` (no client access). The profile keeps only
 * `legacyPasswordPending: true` so the login screen knows to ask the server.
 */
async function moveLegacyPasswordHashes() {
    let moved = 0;
    for (const field of ['passwordHash', 'password']) {
        const snap = await db().collection('users').where(field, '!=', null).limit(2000).get();
        const writer = db().bulkWriter();
        for (const doc of snap.docs) {
            const d = doc.data();
            writer.set(db().collection('legacy_password_hashes').doc(doc.id), Object.assign(Object.assign(Object.assign({}, (d.passwordHash ? { passwordHash: String(d.passwordHash) } : {})), (d.password ? { password: String(d.password) } : {})), { movedAt: firestore_2.FieldValue.serverTimestamp() }), { merge: true });
            writer.update(doc.ref, {
                passwordHash: firestore_2.FieldValue.delete(),
                password: firestore_2.FieldValue.delete(),
                legacyPasswordPending: true,
            });
            moved++;
        }
        await writer.close();
    }
    return moved;
}
exports.moveLegacyPasswordHashesDaily = (0, scheduler_1.onSchedule)('every 24 hours', async () => {
    const moved = await moveLegacyPasswordHashes();
    logger.info('legacy password hashes moved', { moved });
});
/** Admin-only: run the move right after deploying. */
exports.moveLegacyPasswordHashesNow = (0, https_1.onCall)(async (request) => {
    const auth = requireUser(request);
    const me = await db().collection('users').doc(auth.uid).get();
    if (me.get('role') !== 'admin')
        throw new https_1.HttpsError('permission-denied', 'Admins only.');
    return { moved: await moveLegacyPasswordHashes() };
});
//# sourceMappingURL=security.js.map