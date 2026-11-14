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
exports.payDeviceRevoke = exports.payDeviceList = exports.payDeviceVerify = exports.payDeviceTrust = exports.payDeviceRegister = exports.payDeviceChallenge = void 0;
exports.verifyDeviceApproval = verifyDeviceApproval;
/**
 * Trusted payment devices (build log D1).
 *
 *   payDeviceChallenge({ purpose: 'register' | 'verify' })  -> { challengeId, challenge, expiresAt }
 *   payDeviceRegister({ challengeId, publicKey, attestation[], label, signature }) -> { deviceId, trusted }
 *   payDeviceTrust({ deviceId })            after a fresh email code (purpose sensitive_action)
 *   payDeviceVerify({ challengeId, deviceId, signature }) -> { ok, trusted, coolDownUntil }
 *   payDeviceList()                         -> { devices }
 *   payDeviceRevoke({ deviceId })
 *
 * Collections (deny-all to clients): pay_devices/{deviceId}, pay_device_challenges/{id}.
 * The private key never leaves the phone and only signs after a fingerprint or
 * face check. `verifyDeviceApproval()` is what payment approvals (D2) call.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const security_1 = require("../security");
const protect_1 = require("../guard/protect");
const devicesLogic_1 = require("./devicesLogic");
const db = () => (0, firestore_1.getFirestore)();
const DEVICES = 'pay_devices';
const CHALLENGES = 'pay_device_challenges';
const GOOGLE_ROOTS_URL = 'https://android.googleapis.com/attestation/root';
const GOOGLE_STATUS_URL = 'https://android.googleapis.com/attestation/status';
const CACHE_MS = 3600000;
let rootsCache = null;
let statusCache = null;
async function googleRoots() {
    if (rootsCache && Date.now() - rootsCache.at < CACHE_MS)
        return rootsCache.pems;
    const r = await fetch(GOOGLE_ROOTS_URL, { signal: AbortSignal.timeout(8000) });
    if (!r.ok)
        throw new Error(`roots ${r.status}`);
    const pems = (await r.json());
    if (!Array.isArray(pems) || pems.length === 0 || !pems.every((p) => typeof p === 'string'))
        throw new Error('roots format');
    rootsCache = { at: Date.now(), pems: pems };
    return rootsCache.pems;
}
async function revokedSerials() {
    if (statusCache && Date.now() - statusCache.at < CACHE_MS)
        return statusCache.revoked;
    const r = await fetch(GOOGLE_STATUS_URL, { signal: AbortSignal.timeout(8000) });
    if (!r.ok)
        throw new Error(`status ${r.status}`);
    const body = (await r.json());
    if (!body || typeof body.entries !== 'object')
        throw new Error('status format');
    const revoked = new Set();
    for (const [serial, e] of Object.entries(body.entries)) {
        if ((e === null || e === void 0 ? void 0 : e.status) === 'REVOKED')
            revoked.add(serial.toLowerCase().replace(/^0+(?=.)/, ''));
    }
    statusCache = { at: Date.now(), revoked };
    return revoked;
}
function uidOf(request) {
    var _a;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return uid;
}
function dataOf(request) {
    const d = request.data;
    return d && typeof d === 'object' ? d : {};
}
function idOf(v, what) {
    if (typeof v !== 'string' || !/^[A-Za-z0-9_-]{16,64}$/.test(v))
        throw new https_1.HttpsError('invalid-argument', `Missing ${what}.`);
    return v;
}
const ms = (v) => (v instanceof firestore_1.Timestamp ? v.toMillis() : typeof v === 'number' ? v : null);
/** Takes a challenge once: right owner, right purpose, not expired, not used. */
async function consumeChallenge(uid, challengeId, purpose) {
    const ref = db().collection(CHALLENGES).doc(challengeId);
    const out = await db().runTransaction(async (tx) => {
        var _a;
        const s = await tx.get(ref);
        if (!s.exists || s.get('uid') !== uid || s.get('purpose') !== purpose)
            return null;
        if (s.get('usedAt') || ((_a = ms(s.get('expiresAt'))) !== null && _a !== void 0 ? _a : 0) < Date.now())
            return null;
        tx.update(ref, { usedAt: firestore_1.FieldValue.serverTimestamp() });
        return String(s.get('challenge'));
    });
    if (!out)
        throw new https_1.HttpsError('deadline-exceeded', 'This check expired. Try again.');
    return out;
}
exports.payDeviceChallenge = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const purpose = dataOf(request).purpose === 'register' ? 'register' : 'verify';
    await (0, protect_1.limit)(uid, 'pay_device_challenge', 30, 3600000);
    const challenge = crypto.randomBytes(32).toString('base64url');
    const ref = db().collection(CHALLENGES).doc();
    const expiresAt = Date.now() + devicesLogic_1.CHALLENGE_TTL_MS;
    await ref.set({ uid, purpose, challenge, expiresAt: firestore_1.Timestamp.fromMillis(expiresAt), createdAt: firestore_1.FieldValue.serverTimestamp() });
    return { challengeId: ref.id, challenge, expiresAt };
});
exports.payDeviceRegister = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const data = dataOf(request);
    await (0, protect_1.limit)(uid, 'pay_device_register', 10, 24 * 3600000);
    await (0, protect_1.limit)((0, protect_1.callerIp)(request), 'pay_device_register_ip', 30, 3600000);
    const challengeId = idOf(data.challengeId, 'check');
    const publicKey = (0, devicesLogic_1.b64)(data.publicKey, 512);
    const signature = (0, devicesLogic_1.b64)(data.signature, 128);
    if (!publicKey || !(0, devicesLogic_1.p256Key)(publicKey) || !signature)
        throw new https_1.HttpsError('invalid-argument', 'This phone’s security key isn’t supported.');
    const chainIn = Array.isArray(data.attestation) ? data.attestation : [];
    const chain = chainIn.map((c) => (0, devicesLogic_1.b64)(c, 8192));
    if (chain.length === 0 || chain.some((c) => !c)) {
        throw new https_1.HttpsError('failed-precondition', 'This phone can’t prove its security chip. Payments need a phone with a hardware security key.');
    }
    const label = typeof data.label === 'string' ? data.label.replace(/[^\p{L}\p{N} ._()'-]/gu, '').slice(0, 60) : '';
    const challenge = await consumeChallenge(uid, challengeId, 'register');
    // Proof the user passed a biometric: the key only signs after one.
    if (!(0, devicesLogic_1.verifySignature)(publicKey, (0, devicesLogic_1.proofPayload)({ purpose: 'register', uid, challengeId, challenge }), signature)) {
        throw new https_1.HttpsError('permission-denied', 'We couldn’t confirm it’s you on this phone. Try again.');
    }
    let roots;
    let revoked;
    try {
        [roots, revoked] = await Promise.all([googleRoots(), revokedSerials()]);
    }
    catch (_a) {
        throw new https_1.HttpsError('unavailable', 'We couldn’t check this phone right now. Try again in a minute.');
    }
    const att = (0, devicesLogic_1.verifyAndroidAttestation)({ chain: chain, publicKey, challenge: Buffer.from(challenge, 'base64url'), rootPems: roots, revokedSerials: revoked });
    if (!att.ok) {
        console.warn('[payDeviceRegister] attestation refused', { uid, reason: att.reason });
        throw new https_1.HttpsError('failed-precondition', 'This phone’s security chip couldn’t be verified, so it can’t be used for payments.');
    }
    const keyHash = crypto.createHash('sha256').update(publicKey).digest('hex');
    const active = await db().collection(DEVICES).where('uid', '==', uid).where('revokedAt', '==', null).get();
    if (active.docs.some((d) => d.get('keyHash') === keyHash))
        throw new https_1.HttpsError('already-exists', 'This phone is already registered.');
    if (active.size >= devicesLogic_1.MAX_ACTIVE_DEVICES)
        throw new https_1.HttpsError('resource-exhausted', `You can have ${devicesLogic_1.MAX_ACTIVE_DEVICES} payment phones. Remove one first.`);
    const ref = db().collection(DEVICES).doc();
    await ref.set({
        uid,
        publicKey: publicKey.toString('base64'),
        keyHash,
        platform: 'android',
        hardware: att.hardware,
        label,
        trustedAt: null,
        coolDownUntil: null,
        revokedAt: null,
        lastUsedAt: null,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await (0, security_1.recordSecurityEvent)(uid, 'pay_device_added', { deviceId: ref.id, deviceLabel: label, platform: 'android', ip: (0, protect_1.callerIp)(request), details: { hardware: att.hardware } });
    return { deviceId: ref.id, trusted: false, hardware: att.hardware };
});
/** After a fresh email code: the device may approve money. Extra phones wait 24 h for large amounts. */
exports.payDeviceTrust = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const deviceId = idOf(dataOf(request).deviceId, 'device');
    const devRef = db().collection(DEVICES).doc(deviceId);
    const stateRef = db().collection('security_state').doc(uid);
    const others = await db().collection(DEVICES).where('uid', '==', uid).where('revokedAt', '==', null).get();
    const hasOtherTrusted = others.docs.some((d) => d.id !== deviceId && d.get('trustedAt'));
    const result = await db().runTransaction(async (tx) => {
        const [dev, state] = await Promise.all([tx.get(devRef), tx.get(stateRef)]);
        if (!dev.exists || dev.get('uid') !== uid || dev.get('revokedAt'))
            return { error: 'missing' };
        if (dev.get('trustedAt'))
            return { error: null, coolDownUntil: ms(dev.get('coolDownUntil')) };
        const now = Date.now();
        if (!(0, devicesLogic_1.stepUpUsable)(ms(state.get('stepUpAt')), ms(state.get('payDeviceStepUpUsedAt')), now))
            return { error: 'step_up' };
        const coolDownUntil = hasOtherTrusted ? now + devicesLogic_1.NEW_DEVICE_COOL_DOWN_MS : null;
        tx.update(devRef, { trustedAt: firestore_1.Timestamp.fromMillis(now), coolDownUntil: coolDownUntil ? firestore_1.Timestamp.fromMillis(coolDownUntil) : null });
        tx.set(stateRef, { payDeviceStepUpUsedAt: firestore_1.Timestamp.fromMillis(now) }, { merge: true });
        return { error: null, coolDownUntil };
    });
    if (result.error === 'missing')
        throw new https_1.HttpsError('not-found', 'This phone isn’t registered.');
    if (result.error === 'step_up')
        throw new https_1.HttpsError('failed-precondition', 'Confirm with the code we email you first.');
    await (0, security_1.recordSecurityEvent)(uid, 'pay_device_trusted', { deviceId, ip: (0, protect_1.callerIp)(request), details: { otherDevices: hasOtherTrusted } });
    return { trusted: true, coolDownUntil: result.coolDownUntil };
});
/**
 * For payment approvals: the payload must be signed by an active device of [uid].
 * [large] amounts also need the new-device cool-down to be over.
 */
async function verifyDeviceApproval(uid, deviceId, payload, signature, large) {
    const snap = await db().collection(DEVICES).doc(deviceId).get();
    if (!snap.exists || snap.get('uid') !== uid)
        return { ok: false, reason: 'unknown_device' };
    const can = (0, devicesLogic_1.deviceCanApprove)({ revokedAt: ms(snap.get('revokedAt')), trustedAt: ms(snap.get('trustedAt')), coolDownUntil: ms(snap.get('coolDownUntil')) }, Date.now(), large);
    if (!can.ok)
        return { ok: false, reason: can.reason, coolDownUntil: ms(snap.get('coolDownUntil')) };
    const key = Buffer.from(String(snap.get('publicKey')), 'base64');
    if (!(0, devicesLogic_1.verifySignature)(key, payload, signature))
        return { ok: false, reason: 'bad_signature' };
    await snap.ref.update({ lastUsedAt: firestore_1.FieldValue.serverTimestamp() });
    return { ok: true, coolDownUntil: ms(snap.get('coolDownUntil')) };
}
/** "Check it's me": a full round trip with the device key, used by the face card. */
exports.payDeviceVerify = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const data = dataOf(request);
    await (0, protect_1.limit)(uid, 'pay_device_verify', 60, 3600000);
    const challengeId = idOf(data.challengeId, 'check');
    const deviceId = idOf(data.deviceId, 'device');
    const signature = (0, devicesLogic_1.b64)(data.signature, 128);
    if (!signature)
        throw new https_1.HttpsError('invalid-argument', 'Missing signature.');
    const challenge = await consumeChallenge(uid, challengeId, 'verify');
    const snap = await db().collection(DEVICES).doc(deviceId).get();
    if (!snap.exists || snap.get('uid') !== uid || snap.get('revokedAt'))
        return { ok: false, registered: false };
    const key = Buffer.from(String(snap.get('publicKey')), 'base64');
    const ok = (0, devicesLogic_1.verifySignature)(key, (0, devicesLogic_1.proofPayload)({ purpose: 'verify', uid, challengeId, challenge, deviceId }), signature);
    if (ok)
        await snap.ref.update({ lastUsedAt: firestore_1.FieldValue.serverTimestamp() });
    return { ok, registered: true, trusted: !!snap.get('trustedAt'), coolDownUntil: ms(snap.get('coolDownUntil')) };
});
exports.payDeviceList = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const q = await db().collection(DEVICES).where('uid', '==', uid).where('revokedAt', '==', null).get();
    const devices = q.docs.map((d) => { var _a, _b, _c; return ({
        id: d.id,
        label: String((_a = d.get('label')) !== null && _a !== void 0 ? _a : ''),
        platform: String((_b = d.get('platform')) !== null && _b !== void 0 ? _b : ''),
        hardware: String((_c = d.get('hardware')) !== null && _c !== void 0 ? _c : ''),
        trusted: !!d.get('trustedAt'),
        coolDownUntil: ms(d.get('coolDownUntil')),
        createdAt: ms(d.get('createdAt')),
        lastUsedAt: ms(d.get('lastUsedAt')),
    }); });
    devices.sort((a, b) => { var _a, _b; return ((_a = b.createdAt) !== null && _a !== void 0 ? _a : 0) - ((_b = a.createdAt) !== null && _b !== void 0 ? _b : 0); });
    return { devices };
});
exports.payDeviceRevoke = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const deviceId = idOf(dataOf(request).deviceId, 'device');
    const ref = db().collection(DEVICES).doc(deviceId);
    const done = await db().runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists || s.get('uid') !== uid)
            return false;
        if (!s.get('revokedAt'))
            tx.update(ref, { revokedAt: firestore_1.FieldValue.serverTimestamp() });
        return true;
    });
    if (!done)
        throw new https_1.HttpsError('not-found', 'This phone isn’t registered.');
    await (0, security_1.recordSecurityEvent)(uid, 'pay_device_revoked', { deviceId, ip: (0, protect_1.callerIp)(request) });
    return { ok: true };
});
//# sourceMappingURL=devices.js.map