"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.roomName = exports.db = exports.LIVEKIT_SECRETS = exports.LIVEKIT_URL = exports.LIVEKIT_API_SECRET = exports.LIVEKIT_API_KEY = void 0;
exports.setStudioDenialHook = setStudioDenialHook;
exports.roomService = roomService;
exports.requireUid = requireUid;
exports.requireString = requireString;
exports.loadState = loadState;
exports.isBlocked = isBlocked;
exports.roleOf = roleOf;
exports.requireRole = requireRole;
exports.requireLive = requireLive;
exports.patchState = patchState;
exports.broadcast = broadcast;
exports.rateLimit = rateLimit;
/**
 * LIVE STUDIO v2 — server helpers shared by every liveStudio/* module
 * (integrator-owned). Auth, role lookup, state transactions and LiveKit
 * fan-out live here so the authorization rules are written once.
 */
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const firestore_1 = require("firebase-admin/firestore");
const livekit_server_sdk_1 = require("livekit-server-sdk");
const contracts_1 = require("./contracts");
exports.LIVEKIT_API_KEY = (0, params_1.defineSecret)('LIVEKIT_API_KEY');
exports.LIVEKIT_API_SECRET = (0, params_1.defineSecret)('LIVEKIT_API_SECRET');
exports.LIVEKIT_URL = (0, params_1.defineString)('LIVEKIT_URL', { default: 'wss://unset.livekit.cloud' });
/** Secrets every callable that talks to LiveKit must declare. */
exports.LIVEKIT_SECRETS = [exports.LIVEKIT_API_KEY, exports.LIVEKIT_API_SECRET];
const db = () => (0, firestore_1.getFirestore)();
exports.db = db;
let denialHook = null;
function setStudioDenialHook(fn) {
    denialHook = fn;
}
function reportDenial(streamId, uid, err, bucket) {
    try {
        denialHook === null || denialHook === void 0 ? void 0 : denialHook(streamId, uid, err, bucket);
    }
    catch (_a) {
        /* never mask the real error */
    }
}
/** LiveKit room name for a stream (1:1). */
const roomName = (streamId) => `studio_${streamId}`;
exports.roomName = roomName;
function roomService() {
    const url = exports.LIVEKIT_URL.value().replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
    return new livekit_server_sdk_1.RoomServiceClient(url, exports.LIVEKIT_API_KEY.value(), exports.LIVEKIT_API_SECRET.value());
}
function requireUid(req) {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return uid;
}
function requireString(v, name, max = 200) {
    if (typeof v !== 'string' || v.trim().length === 0 || v.length > max) {
        throw new https_1.HttpsError('invalid-argument', `${name} is required (≤ ${max} chars).`);
    }
    return v.trim();
}
async function loadState(streamId, tx) {
    const ref = (0, exports.db)().doc(contracts_1.Paths.state(streamId));
    const snap = tx ? await tx.get(ref) : await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'This live does not exist.');
    return snap.data();
}
async function isBlocked(streamId, uid) {
    return (await (0, exports.db)().doc(`${contracts_1.Paths.blocks(streamId)}/${uid}`).get()).exists;
}
/** Role of [uid] in [streamId]: host from state, others from members/. */
async function roleOf(streamId, uid, state) {
    var _a;
    const s = state !== null && state !== void 0 ? state : (await loadState(streamId));
    if (s.hostId === uid)
        return 'host';
    const m = await (0, exports.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`).get();
    return m.exists ? ((_a = m.data().role) !== null && _a !== void 0 ? _a : 'viewer') : 'viewer';
}
/** Throws unless [uid] has one of [allowed] roles and is not blocked. */
async function requireRole(streamId, uid, allowed, state) {
    if (await isBlocked(streamId, uid)) {
        const err = new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
        reportDenial(streamId, uid, err, 'role');
        throw err;
    }
    const r = await roleOf(streamId, uid, state);
    if (!allowed.includes(r)) {
        const err = new https_1.HttpsError('permission-denied', `Requires role: ${allowed.join(' or ')}.`);
        reportDenial(streamId, uid, err, 'role');
        throw err;
    }
    return r;
}
function requireLive(s) {
    if (s.status === 'ended')
        throw new https_1.HttpsError('failed-precondition', 'This live has ended.');
}
/**
 * Atomically mutates one top-level section of studio/state, bumps `seq`,
 * then broadcasts a `state.patch`. [mutate] returns the new section value,
 * or `undefined` for "no change" (nothing is written or sent).
 */
async function patchState(streamId, path, mutate) {
    const ref = (0, exports.db)().doc(contracts_1.Paths.state(streamId));
    const result = await (0, exports.db)().runTransaction(async (tx) => {
        var _a;
        const s = await loadState(streamId, tx);
        const value = await mutate(s, tx);
        if (value === undefined)
            return null;
        const seq = ((_a = s.seq) !== null && _a !== void 0 ? _a : 0) + 1;
        tx.update(ref, { [path]: value, seq, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        return Object.assign(Object.assign({}, s), { [path]: value, seq });
    });
    if (result) {
        await broadcast(streamId, 'studio.state', {
            v: 1, type: 'state.patch', seq: result.seq, path, value: result[path], ts: Date.now(),
        });
    }
    return result;
}
/**
 * Sends a data message to everyone in the room (or [to] identities only).
 * Failures are logged, never thrown: Firestore stays the source of record and
 * clients resync with `lsStateFull` when they see a `seq` gap.
 */
async function broadcast(streamId, topic, event, opts = {}) {
    try {
        const data = new TextEncoder().encode(JSON.stringify(event));
        await roomService().sendData((0, exports.roomName)(streamId), data, opts.lossy ? livekit_server_sdk_1.DataPacket_Kind.LOSSY : livekit_server_sdk_1.DataPacket_Kind.RELIABLE, { topic, destinationIdentities: opts.to });
    }
    catch (e) {
        console.warn(`[liveStudio] broadcast ${topic} failed for ${streamId}:`, e.message);
    }
}
/**
 * Fixed-window rate limiter stored in Firestore
 * (`studio_rate/{uid}_{bucket}`). Throws `resource-exhausted` when exceeded.
 */
async function rateLimit(streamId, uid, bucket, max, windowMs) {
    const ref = (0, exports.db)().doc(`${contracts_1.Paths.rate(streamId)}/${uid}_${bucket}`);
    try {
        await rateLimitTx(ref, max, windowMs);
    }
    catch (e) {
        reportDenial(streamId, uid, e, bucket);
        throw e;
    }
}
async function rateLimitTx(ref, max, windowMs) {
    await (0, exports.db)().runTransaction(async (tx) => {
        const now = Date.now();
        const snap = await tx.get(ref);
        const d = snap.exists ? snap.data() : { start: now, count: 0 };
        const fresh = now - d.start >= windowMs;
        const next = fresh ? { start: now, count: 1 } : { start: d.start, count: d.count + 1 };
        if (!fresh && next.count > max)
            throw new https_1.HttpsError('resource-exhausted', 'Slow down a little.');
        tx.set(ref, next);
    });
}
//# sourceMappingURL=shared.js.map