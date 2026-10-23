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
exports.sweepStaleCalls = exports.onCallFinished = exports.onCallParticipantWritten = void 0;
/**
 * Calling push fan-out.
 *
 * The app writes `calls/{callId}` plus one `participants/{uid}` doc per
 * person. These triggers turn those writes into pushes so a phone rings even
 * when Oneova is killed or the screen is locked:
 *   - Android: FCM high-priority *data* message → app's background handler →
 *     full-screen incoming-call UI (flutter_callkit_incoming).
 *   - iOS: APNs VoIP push (PushKit) → CallKit. Needs the APNS_* secrets below;
 *     without them iOS falls back to a normal alert notification.
 *
 * No server keys live in the app. Secrets (set once, before deploying):
 *   firebase functions:secrets:set APNS_KEY_P8    (contents of AuthKey_XXXX.p8, or "unset")
 *   firebase functions:secrets:set APNS_KEY_ID    (10-char key id, or "unset")
 *   firebase functions:secrets:set APNS_TEAM_ID   (Apple team id, or "unset")
 */
const http2 = __importStar(require("http2"));
const crypto = __importStar(require("crypto"));
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const apnsKey = (0, params_1.defineSecret)('APNS_KEY_P8');
const apnsKeyId = (0, params_1.defineSecret)('APNS_KEY_ID');
const apnsTeamId = (0, params_1.defineSecret)('APNS_TEAM_ID');
const apnsTopic = (0, params_1.defineString)('APNS_VOIP_TOPIC', { default: 'com.oneova.app.voip' });
const apnsProduction = (0, params_1.defineBoolean)('APNS_PRODUCTION', { default: false });
const RING_MS = 45000;
const FINAL = ['ended', 'missed', 'declined', 'busy'];
const db = () => (0, firestore_2.getFirestore)();
async function tokensFor(uid) {
    var _a;
    const [fcm, voip] = await Promise.all([
        db().collection('users').doc(uid).collection('device_tokens').get(),
        db().collection('users').doc(uid).collection('voip_tokens').get(),
    ]);
    const android = [];
    const iosFcm = [];
    for (const d of fcm.docs) {
        const platform = String((_a = d.get('platform')) !== null && _a !== void 0 ? _a : '').toLowerCase();
        (platform === 'ios' ? iosFcm : android).push(d.id);
    }
    return { android, iosFcm, voip: voip.docs.map((d) => d.id) };
}
function callData(callId, call, type, extra = {}) {
    var _a, _b, _c;
    return Object.assign({ type,
        callId, callkitId: call.callkitId || callId, hostId: (_a = call.hostId) !== null && _a !== void 0 ? _a : '', callerName: (call.isGroup && call.title) ? call.title : ((_b = call.callerName) !== null && _b !== void 0 ? _b : ''), callerAvatar: (_c = call.callerAvatar) !== null && _c !== void 0 ? _c : '', isVideo: String(call.isVideo === true), isGroup: String(call.isGroup === true), sentAt: String(Date.now()) }, extra);
}
async function sendFcm(uid, tokens, data, iosAlert) {
    if (tokens.length === 0)
        return;
    const res = await (0, messaging_1.getMessaging)().sendEachForMulticast({
        tokens,
        data,
        android: { priority: 'high', ttl: RING_MS },
        apns: iosAlert
            ? {
                headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
                payload: { aps: { alert: iosAlert, sound: 'default' } },
            }
            : undefined,
    });
    // Drop tokens FCM says are dead.
    await Promise.all(res.responses.map(async (r, i) => {
        var _a;
        var _b;
        const code = (_b = (_a = r.error) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : '';
        if (code.includes('registration-token-not-registered') || code.includes('invalid-registration-token')) {
            await db().collection('users').doc(uid).collection('device_tokens').doc(tokens[i]).delete().catch(() => undefined);
        }
    }));
}
// ───────────────────────── APNs VoIP ─────────────────────────
function secretValue(s) {
    try {
        const v = s.value();
        return v && v !== 'unset' ? v : '';
    }
    catch (_a) {
        return '';
    }
}
let cachedJwt = null;
function apnsJwt() {
    const key = secretValue(apnsKey);
    const keyId = secretValue(apnsKeyId);
    const teamId = secretValue(apnsTeamId);
    if (!key || !keyId || !teamId)
        return null;
    if (cachedJwt && Date.now() - cachedJwt.at < 50 * 60 * 1000)
        return cachedJwt.token;
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${b64({ alg: 'ES256', kid: keyId })}.${b64({ iss: teamId, iat: Math.floor(Date.now() / 1000) })}`;
    const sig = crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    cachedJwt = { token: `${unsigned}.${sig}`, at: Date.now() };
    return cachedJwt.token;
}
async function sendVoip(uid, tokens, payload) {
    const jwt = apnsJwt();
    if (!jwt || tokens.length === 0)
        return false;
    const host = apnsProduction.value() ? 'https://api.push.apple.com' : 'https://api.development.push.apple.com';
    const client = http2.connect(host);
    const body = JSON.stringify(payload);
    let delivered = false;
    try {
        await Promise.all(tokens.map((token) => new Promise((resolve) => {
            const req = client.request({
                ':method': 'POST',
                ':path': `/3/device/${token}`,
                authorization: `bearer ${jwt}`,
                'apns-topic': apnsTopic.value(),
                'apns-push-type': 'voip',
                'apns-priority': '10',
                'apns-expiration': String(Math.floor((Date.now() + RING_MS) / 1000)),
            });
            let status = 0;
            req.on('response', (h) => {
                status = Number(h[':status']);
            });
            req.on('data', () => undefined);
            req.on('end', async () => {
                if (status === 200)
                    delivered = true;
                if (status === 410 || status === 400) {
                    await db().collection('users').doc(uid).collection('voip_tokens').doc(token).delete().catch(() => undefined);
                }
                resolve();
            });
            req.on('error', (e) => {
                logger.warn('APNs request failed', e);
                resolve();
            });
            req.end(body);
        })));
    }
    finally {
        client.close();
    }
    return delivered;
}
// ───────────────────────── Triggers ─────────────────────────
/** Rings a participant (and stops the ringing on their other devices). */
exports.onCallParticipantWritten = (0, firestore_1.onDocumentWritten)({ document: 'calls/{callId}/participants/{uid}', secrets: [apnsKey, apnsKeyId, apnsTeamId] }, async (event) => {
    var _a, _b;
    var _c, _d, _e;
    const { callId, uid } = event.params;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    const callSnap = await db().collection('calls').doc(callId).get();
    const call = callSnap.data();
    if (!call || uid === call.hostId)
        return;
    const startedRinging = (after === null || after === void 0 ? void 0 : after.status) === 'ringing' && (before === null || before === void 0 ? void 0 : before.status) !== 'ringing';
    const stoppedRinging = (before === null || before === void 0 ? void 0 : before.status) === 'ringing' && (after === null || after === void 0 ? void 0 : after.status) !== 'ringing';
    if (startedRinging) {
        if (call.status && FINAL.includes(call.status))
            return;
        const t = await tokensFor(uid);
        const data = callData(callId, call, 'incoming_call');
        const voipSent = await sendVoip(uid, t.voip, {
            aps: {},
            id: data.callkitId,
            nameCaller: data.callerName,
            handle: call.isVideo ? 'Video call' : 'Voice call',
            isVideo: call.isVideo === true,
            avatar: data.callerAvatar,
            extra: { callId, isVideo: call.isVideo === true, isGroup: call.isGroup === true, hostId: (_c = call.hostId) !== null && _c !== void 0 ? _c : '' },
        });
        await sendFcm(uid, t.android, data);
        if (!voipSent) {
            await sendFcm(uid, t.iosFcm, data, {
                title: data.callerName || 'Oneova',
                body: `Incoming ${call.isVideo ? 'video' : 'voice'} call`,
            });
        }
        logger.info('Rang participant', { callId, uid, android: t.android.length, voip: voipSent });
        return;
    }
    if (stoppedRinging) {
        const reason = (after === null || after === void 0 ? void 0 : after.status) === 'missed' ? 'missed' : 'stopped';
        const t = await tokensFor(uid);
        await sendFcm(uid, [...t.android, ...t.iosFcm], callData(callId, call, 'call_cancel', { reason }));
        if (reason === 'missed') {
            await db().collection('notifications').add({
                userId: uid,
                actorId: (_d = call.hostId) !== null && _d !== void 0 ? _d : null,
                category: 'missedCall',
                priority: 'high',
                title: 'Missed call',
                body: `${call.callerName || 'Someone'} tried to ${call.isVideo ? 'video ' : ''}call you`,
                groupId: `call_${callId}`,
                payload: { callId, hostId: (_e = call.hostId) !== null && _e !== void 0 ? _e : '' },
                isRead: false,
                createdAt: firestore_2.FieldValue.serverTimestamp(),
            });
        }
    }
});
/** When a call finishes: per-user history, and anyone still ringing is missed. */
exports.onCallFinished = (0, firestore_1.onDocumentUpdated)('calls/{callId}', async (event) => {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    if (FINAL.includes((_e = before.status) !== null && _e !== void 0 ? _e : '') || !FINAL.includes((_f = after.status) !== null && _f !== void 0 ? _f : ''))
        return;
    const { callId } = event.params;
    const participants = await event.data.after.ref.collection('participants').get();
    const batch = db().batch();
    const answered = (_c = after.answeredAt) === null || _c === void 0 ? void 0 : _c.toMillis();
    const ended = (_g = (_d = after.endedAt) === null || _d === void 0 ? void 0 : _d.toMillis()) !== null && _g !== void 0 ? _g : Date.now();
    const durationSec = answered ? Math.max(0, Math.round((ended - answered) / 1000)) : 0;
    for (const p of participants.docs) {
        const status = String((_h = p.get('status')) !== null && _h !== void 0 ? _h : '');
        if (status === 'ringing')
            batch.update(p.ref, { status: 'missed', updatedAt: firestore_2.FieldValue.serverTimestamp() });
        const outgoing = p.id === after.hostId;
        const outcome = outgoing
            ? (answered ? 'completed' : after.status)
            : (status === 'joined' || status === 'left' ? 'completed' : status === 'ringing' ? 'missed' : status);
        batch.set(db().collection('users').doc(p.id).collection('call_history').doc(callId), {
            callId,
            direction: outgoing ? 'outgoing' : 'incoming',
            outcome,
            isVideo: after.isVideo === true,
            isGroup: after.isGroup === true,
            hostId: (_j = after.hostId) !== null && _j !== void 0 ? _j : '',
            participantIds: (_k = after.participantIds) !== null && _k !== void 0 ? _k : [],
            title: after.isGroup ? ((_l = after.title) !== null && _l !== void 0 ? _l : null) : (outgoing ? null : ((_m = after.callerName) !== null && _m !== void 0 ? _m : null)),
            durationSec,
            startedAt: (_o = after.startedAt) !== null && _o !== void 0 ? _o : firestore_2.FieldValue.serverTimestamp(),
            endedAt: (_p = after.endedAt) !== null && _p !== void 0 ? _p : firestore_2.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
});
/** Ends calls left ringing after the caller's app died. */
exports.sweepStaleCalls = (0, scheduler_1.onSchedule)('every 5 minutes', async () => {
    const cutoff = firestore_2.Timestamp.fromMillis(Date.now() - 2 * 60 * 1000);
    const stale = await db()
        .collection('calls')
        .where('status', '==', 'ringing')
        .where('startedAt', '<', cutoff)
        .limit(200)
        .get();
    await Promise.all(stale.docs.map((d) => d.ref.update({ status: 'missed', endReason: 'noAnswer', endedAt: firestore_2.FieldValue.serverTimestamp() })));
    if (!stale.empty)
        logger.info(`Swept ${stale.size} stale ringing calls`);
});
//# sourceMappingURL=calls.js.map