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
exports.revokeBiometricKey = exports.biometricSignIn = exports.registerBiometricKey = void 0;
/**
 * Fingerprint / Face quick re-login.
 *
 * When a signed-in user turns on biometric sign-in, the app generates a
 * 256-bit random secret, keeps it in the device's secure storage (Android
 * Keystore / iOS Keychain) and registers only its SHA-256 hash here. Later,
 * after a local biometric check, the app sends the key id + secret to
 * `biometricSignIn`, which returns a Firebase custom token for that user.
 *
 * Passwords are never stored. `biometric_keys` must not be readable or
 * writable by clients (Firestore rules: deny all); only this code touches it.
 *
 * Needs: the functions' service account must have
 * "Service Account Token Creator" so createCustomToken can sign.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const security_1 = require("./security");
const KEYS = 'biometric_keys';
const MAX_KEYS_PER_USER = 5;
const KEY_TTL_DAYS = 90;
function sha256(v) {
    return crypto.createHash('sha256').update(v).digest('hex');
}
function safeEqual(a, b) {
    const ab = Buffer.from(a, 'hex');
    const bb = Buffer.from(b, 'hex');
    return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}
/** Registers this device's biometric key for the signed-in user. */
exports.registerBiometricKey = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    var _k, _l, _m, _o;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid || ((_d = (_c = (_b = request.auth) === null || _b === void 0 ? void 0 : _b.token) === null || _c === void 0 ? void 0 : _c.firebase) === null || _d === void 0 ? void 0 : _d.sign_in_provider) === 'anonymous') {
        throw new https_1.HttpsError('unauthenticated', 'Sign in to your account first.');
    }
    const secretHash = String((_k = (_e = request.data) === null || _e === void 0 ? void 0 : _e.secretHash) !== null && _k !== void 0 ? _k : '');
    const deviceLabel = String((_l = (_f = request.data) === null || _f === void 0 ? void 0 : _f.deviceLabel) !== null && _l !== void 0 ? _l : '').slice(0, 80);
    const deviceId = String((_m = (_g = request.data) === null || _g === void 0 ? void 0 : _g.deviceId) !== null && _m !== void 0 ? _m : '');
    if (deviceId && !/^[0-9a-f]{32}$/.test(deviceId)) {
        throw new https_1.HttpsError('invalid-argument', 'Bad device.');
    }
    if (!/^[0-9a-f]{64}$/.test(secretHash)) {
        throw new https_1.HttpsError('invalid-argument', 'Bad key.');
    }
    const db = (0, firestore_1.getFirestore)();
    // Keep at most a few devices per user; drop the oldest.
    const existing = await db.collection(KEYS).where('uid', '==', uid).get();
    const sorted = existing.docs.sort((a, b) => { var _a, _b, _c, _d; var _e, _f; return ((_e = (_b = (_a = a.get('createdAt')) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _e !== void 0 ? _e : 0) - ((_f = (_d = (_c = b.get('createdAt')) === null || _c === void 0 ? void 0 : _c.toMillis) === null || _d === void 0 ? void 0 : _d.call(_c)) !== null && _f !== void 0 ? _f : 0); });
    const batch = db.batch();
    for (const d of sorted.slice(0, Math.max(0, sorted.length - (MAX_KEYS_PER_USER - 1)))) {
        batch.delete(d.ref);
    }
    const ref = db.collection(KEYS).doc();
    batch.set(ref, {
        uid,
        secretHash,
        deviceLabel,
        deviceId: deviceId || null,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + KEY_TTL_DAYS * 86400000),
        lastUsedAt: null,
    });
    await batch.commit();
    // Ova Guard: a new fingerprint key is worth knowing about, more so on a
    // device that first appeared in the last day.
    let newDevice = true;
    if (deviceId) {
        const seen = await db.collection('security_state').doc(uid).collection('devices').doc(deviceId).get();
        const first = (_o = (_j = (_h = seen.get('firstSeenAt')) === null || _h === void 0 ? void 0 : _h.toMillis) === null || _j === void 0 ? void 0 : _j.call(_h)) !== null && _o !== void 0 ? _o : Date.now();
        newDevice = !seen.exists || Date.now() - first < 86400000;
    }
    await (0, security_1.recordSecurityEvent)(uid, 'biometric_key_added', {
        deviceId: deviceId || null,
        deviceLabel: deviceLabel || null,
        details: { newDevice },
    }).catch((e) => console.warn('guard event failed', e));
    return { keyId: ref.id };
});
/** Exchanges a device key for a custom token. Called while signed out. */
exports.biometricSignIn = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h;
    const keyId = String((_e = (_a = request.data) === null || _a === void 0 ? void 0 : _a.keyId) !== null && _e !== void 0 ? _e : '');
    const secret = String((_f = (_b = request.data) === null || _b === void 0 ? void 0 : _b.secret) !== null && _f !== void 0 ? _f : '');
    if (!/^[A-Za-z0-9]{10,40}$/.test(keyId) || secret.length < 32 || secret.length > 256) {
        throw new https_1.HttpsError('invalid-argument', 'Bad key.');
    }
    const db = (0, firestore_1.getFirestore)();
    const ref = db.collection(KEYS).doc(keyId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'This device is no longer enrolled.');
    const data = snap.data();
    const expires = (_g = (_c = data.expiresAt) === null || _c === void 0 ? void 0 : _c.toMillis()) !== null && _g !== void 0 ? _g : 0;
    if (expires < Date.now()) {
        await ref.delete();
        throw new https_1.HttpsError('deadline-exceeded', 'Biometric sign-in expired. Sign in again.');
    }
    if (!safeEqual(sha256(secret), String(data.secretHash))) {
        throw new https_1.HttpsError('permission-denied', 'This device is no longer enrolled.');
    }
    // The key only works on the device it was registered from.
    if (data.deviceId && String((_h = (_d = request.data) === null || _d === void 0 ? void 0 : _d.deviceId) !== null && _h !== void 0 ? _h : '') !== String(data.deviceId)) {
        throw new https_1.HttpsError('permission-denied', 'This device is no longer enrolled.');
    }
    const uid = String(data.uid);
    try {
        const user = await (0, auth_1.getAuth)().getUser(uid);
        if (user.disabled)
            throw new https_1.HttpsError('permission-denied', 'Account disabled.');
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        await ref.delete();
        throw new https_1.HttpsError('not-found', 'Account not found.');
    }
    // Sliding expiry: each successful use extends the key.
    await ref.update({
        lastUsedAt: firestore_1.FieldValue.serverTimestamp(),
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + KEY_TTL_DAYS * 86400000),
    });
    const token = await (0, auth_1.getAuth)().createCustomToken(uid, { biometric: true });
    return { token };
});
/** Removes a device key (turning biometric sign-in off). */
exports.revokeBiometricKey = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    var _c;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const keyId = String((_c = (_b = request.data) === null || _b === void 0 ? void 0 : _b.keyId) !== null && _c !== void 0 ? _c : '');
    const db = (0, firestore_1.getFirestore)();
    if (keyId) {
        const ref = db.collection(KEYS).doc(keyId);
        const snap = await ref.get();
        if (snap.exists && snap.get('uid') === uid)
            await ref.delete();
    }
    return { ok: true };
});
//# sourceMappingURL=biometric.js.map