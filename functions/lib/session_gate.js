"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scrubLegacyPasswordHashes = exports.lookupAccountByPhone = exports.revokeTrustedDevice = exports.confirmSignInChecks = exports.recordSignInCheck = void 0;
/**
 * Server-side two-check sign-in gate (PROPOSAL — not exported from index.ts,
 * so nothing here is deployed until the user approves it).
 *
 * Why: the app's LoginSecurity gate runs on the phone. A modified client
 * could skip it. These functions let the SERVER decide whether a sign-in
 * passed two checks, and mark that session with a custom claim that the
 * Firestore rules require for writes and private reads.
 *
 * Flow (client changes come with the approval):
 *   1. After every proof (password sign-in, SMS code, Google/Facebook,
 *      fingerprint device key) the app calls `recordSignInCheck({deviceId})`
 *      with its fresh ID token. The server reads the proof from the token
 *      itself (sign_in_provider + auth_time), so it cannot be faked.
 *      An SMS proof also marks this device as known (server-written).
 *   2. The app calls `confirmSignInChecks({deviceId})`. If the proofs meet the
 *      policy, the server adds this session's auth_time to the
 *      `mfaSessions` custom claim (last 5 sessions = up to 5 phones).
 *   3. The app refreshes its token (getIdToken(true)). Rules accept writes
 *      only when token.auth_time is in token.mfaSessions. Any new sign-in
 *      gets a new auth_time, so it is blocked until it passes again.
 *
 * Policy (same as LoginSecurity.missingFactor on the phone):
 *   - unknown device -> an SMS proof is required (then the device is known);
 *   - at least 2 different proofs among phone, password, federated,
 *     deviceKey (fingerprint key) and knownDevice;
 *   - at least one of password / federated / deviceKey.
 * Fingerprint and PIN are checked on the phone; the server counts the
 * fingerprint only through its server-issued device key.
 */
const https_1 = require("firebase-functions/v2/https");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const PROOF_WINDOW_MS = 15 * 60 * 1000; // proofs older than this don't count
const FRESH_TOKEN_MS = 10 * 60 * 1000; // token must come from a recent sign-in
const MAX_SESSIONS = 5;
function requireUser(request) {
    var _a;
    const auth = request.auth;
    if (!auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const provider = (_a = auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider;
    if (provider === 'anonymous')
        throw new https_1.HttpsError('permission-denied', 'Guests cannot sign in this way.');
    return auth;
}
function deviceIdFrom(data) {
    var _a;
    const id = String((_a = data === null || data === void 0 ? void 0 : data.deviceId) !== null && _a !== void 0 ? _a : '');
    if (!/^[0-9a-f]{32}$/.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Bad device.');
    return id;
}
/** Maps the token's sign-in method to a proof, or null if it isn't one. */
function proofFromToken(token) {
    var _a;
    var _b;
    const p = (_b = (_a = token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) !== null && _b !== void 0 ? _b : '';
    if (p === 'phone')
        return 'phone';
    if (p === 'password')
        return 'password';
    if (p === 'google.com' || p === 'facebook.com' || p.startsWith('oidc.'))
        return 'federated';
    if (p === 'custom' && token.biometric === true)
        return 'deviceKey';
    return null;
}
const checksDoc = (uid, deviceId) => (0, firestore_1.getFirestore)().collection('auth_checks').doc(`${uid}_${deviceId}`);
const deviceDoc = (uid, deviceId) => (0, firestore_1.getFirestore)().collection('users').doc(uid).collection('trusted_devices').doc(deviceId);
/** Step 1: record the proof carried by the caller's (fresh) ID token. */
exports.recordSignInCheck = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    const auth = requireUser(request);
    const deviceId = deviceIdFrom(request.data);
    const authTimeMs = Number(auth.token.auth_time) * 1000;
    if (!authTimeMs || Date.now() - authTimeMs > FRESH_TOKEN_MS) {
        throw new https_1.HttpsError('failed-precondition', 'Please sign in again.');
    }
    const proof = proofFromToken(auth.token);
    if (!proof)
        throw new https_1.HttpsError('invalid-argument', 'This sign-in method does not count as a check.');
    await checksDoc(auth.uid, deviceId).set({ uid: auth.uid, deviceId, proofs: { [proof]: authTimeMs }, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    if (proof === 'phone') {
        // A fresh SMS proof on this device makes it a known device.
        await deviceDoc(auth.uid, deviceId).set({ trustedAt: firestore_1.FieldValue.serverTimestamp(), trustedVia: 'sms', lastSeenAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    }
    return { recorded: proof };
});
/** Step 2: if the recorded proofs meet the policy, mark this session. */
exports.confirmSignInChecks = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    var _a, _b;
    const auth = requireUser(request);
    const deviceId = deviceIdFrom(request.data);
    const db = (0, firestore_1.getFirestore)();
    const [checks, device] = await Promise.all([checksDoc(auth.uid, deviceId).get(), deviceDoc(auth.uid, deviceId).get()]);
    const now = Date.now();
    const proofs = new Set();
    const recorded = ((_a = checks.get('proofs')) !== null && _a !== void 0 ? _a : {});
    for (const [k, t] of Object.entries(recorded))
        if (now - Number(t) <= PROOF_WINDOW_MS)
            proofs.add(k);
    const known = device.exists && device.get('revoked') !== true;
    if (known)
        proofs.add('knownDevice');
    if (!known && !proofs.has('phone')) {
        return { ok: false, needs: 'smsOtp' };
    }
    if (!proofs.has('password') && !proofs.has('federated') && !proofs.has('deviceKey')) {
        return { ok: false, needs: 'password' };
    }
    if (proofs.size < 2) {
        return { ok: false, needs: 'smsOtp' };
    }
    // Mark THIS session (auth_time) as verified, keeping other claims.
    const user = await (0, auth_1.getAuth)().getUser(auth.uid);
    const claims = Object.assign({}, ((_b = user.customClaims) !== null && _b !== void 0 ? _b : {}));
    const sessions = Array.isArray(claims.mfaSessions) ? claims.mfaSessions : [];
    const authTime = Number(auth.token.auth_time);
    claims.mfaSessions = [...sessions.filter((s) => s !== authTime), authTime].slice(-MAX_SESSIONS);
    await (0, auth_1.getAuth)().setCustomUserClaims(auth.uid, claims);
    // Old accounts kept a password hash in the public profile; once the
    // password lives in Firebase Auth, remove it.
    if (user.providerData.some((p) => p.providerId === 'password')) {
        await db.collection('users').doc(auth.uid).set({ passwordHash: firestore_1.FieldValue.delete(), password: firestore_1.FieldValue.delete() }, { merge: true });
    }
    await Promise.all([
        checks.ref.delete(),
        deviceDoc(auth.uid, deviceId).set({ lastSeenAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true }),
        db.collection('users').doc(auth.uid).collection('security_events').add({
            type: 'sign_in',
            proofs: [...proofs].sort(),
            deviceId,
            newDevice: !known,
            at: firestore_1.FieldValue.serverTimestamp(),
        }),
    ]);
    return { ok: true };
});
/** "Sign out this phone": forget a known device and end all marked sessions. */
exports.revokeTrustedDevice = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    var _a;
    const auth = requireUser(request);
    const deviceId = deviceIdFrom(request.data);
    await deviceDoc(auth.uid, deviceId).delete();
    const user = await (0, auth_1.getAuth)().getUser(auth.uid);
    const claims = Object.assign({}, ((_a = user.customClaims) !== null && _a !== void 0 ? _a : {}));
    delete claims.mfaSessions;
    await (0, auth_1.getAuth)().setCustomUserClaims(auth.uid, claims);
    await (0, auth_1.getAuth)().revokeRefreshTokens(auth.uid);
    return { ok: true };
});
/**
 * Login screen account lookup without public phone numbers: returns only
 * what the sign-in header shows. Replaces the client query on users.phoneNumber.
 */
exports.lookupAccountByPhone = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    var _a;
    var _b, _c, _d, _e, _f;
    const phone = String((_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.phone) !== null && _b !== void 0 ? _b : '');
    if (!/^\+[1-9]\d{6,14}$/.test(phone))
        throw new https_1.HttpsError('invalid-argument', 'Bad number.');
    const snap = await (0, firestore_1.getFirestore)().collection('users').where('phoneNumber', '==', phone).limit(1).get();
    if (snap.empty)
        return { found: false };
    const d = snap.docs[0].data();
    return {
        found: true,
        uid: snap.docs[0].id,
        displayName: (_c = d.displayName) !== null && _c !== void 0 ? _c : null,
        username: (_d = d.username) !== null && _d !== void 0 ? _d : null,
        photoUrl: (_f = (_e = d.photoUrl) !== null && _e !== void 0 ? _e : d.avatarUrl) !== null && _f !== void 0 ? _f : null,
    };
});
/** One-off, admin only: strip legacy password hashes from every profile. */
exports.scrubLegacyPasswordHashes = (0, https_1.onCall)(async (request) => {
    const auth = requireUser(request);
    const db = (0, firestore_1.getFirestore)();
    const me = await db.collection('users').doc(auth.uid).get();
    if (me.get('role') !== 'admin')
        throw new https_1.HttpsError('permission-denied', 'Admins only.');
    let cleaned = 0;
    for (const field of ['passwordHash', 'password']) {
        const snap = await db.collection('users').where(field, '!=', null).get();
        const writer = db.bulkWriter();
        for (const doc of snap.docs) {
            writer.update(doc.ref, { passwordHash: firestore_1.FieldValue.delete(), password: firestore_1.FieldValue.delete() });
            cleaned++;
        }
        await writer.close();
    }
    return { cleaned };
});
//# sourceMappingURL=session_gate.js.map