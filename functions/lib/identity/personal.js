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
exports.kycDelete = exports.idShareRevoke = exports.idShare = exports.idCredential = exports.claimsFor = void 0;
exports.onPersonalVerified = onPersonalVerified;
exports.onPersonalRejected = onPersonalRejected;
exports.onPersonalSubmitted = onPersonalSubmitted;
/**
 * Oneova ID for people. The check itself is the payments KYC (creator/kyc.ts);
 * this file reacts to its decisions and gives the person a reusable,
 * shareable credential, plus "delete my identity data".
 *
 *   kycReview approve → onPersonalVerified  (badge, audit, notification)
 *   app → idCredential   signed SD-JWT VC, returned once to be kept on the phone
 *   app → idShare        short-lived QR token with only the chosen fields
 *   app → idShareRevoke  stops a share
 *   app → kycDelete      deletes photos + record, revokes everything
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const common_1 = require("./common");
const credentials_1 = require("./credentials");
const monthOf = (t) => {
    const d = t instanceof firestore_1.Timestamp ? t.toDate() : new Date();
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
};
/** Called from kycReview after an approval. */
async function onPersonalVerified(uid, reviewer) {
    await (0, common_1.db)().doc(`identity/${uid}`).set({
        uid, level: 2, status: 'verified', credentialReady: true, verifiedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    await (0, common_1.syncBadges)(uid);
    await (0, common_1.audit)(uid, 'id.verified', 'reviewer', reviewer ? 'Approved by the review team' : '');
    await (0, common_1.notify)(uid, `id_ok_${uid}`, 'Your Oneova ID is ready', 'Your identity is verified. You can now share it with a QR code.', '/id');
}
async function onPersonalRejected(uid, reason) {
    await (0, common_1.db)().doc(`identity/${uid}`).set({ uid, status: 'rejected', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    await (0, common_1.audit)(uid, 'id.rejected', 'reviewer', reason);
}
async function onPersonalSubmitted(uid) {
    await (0, common_1.db)().doc(`identity/${uid}`).set({ uid, status: 'review', consentAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    await (0, common_1.audit)(uid, 'id.submitted', 'you', 'Photos sent for review');
}
async function personClaims(uid) {
    var _a, _b, _c, _d;
    const [k, u] = await Promise.all([(0, common_1.db)().doc(`kyc/${uid}`).get(), (0, common_1.db)().doc(`users/${uid}`).get()]);
    if (k.get('status') !== 'verified')
        throw new https_1.HttpsError('failed-precondition', 'Verify your identity first.');
    return {
        verified: true,
        level: 2,
        name: String((_a = k.get('verifiedName')) !== null && _a !== void 0 ? _a : ''),
        country: String((_b = k.get('country')) !== null && _b !== void 0 ? _b : ''),
        document: String((_c = k.get('documentType')) !== null && _c !== void 0 ? _c : ''),
        since: monthOf(k.get('verifiedAt')),
        handle: String((_d = u.get('username')) !== null && _d !== void 0 ? _d : ''),
    };
}
async function businessClaims(uid) {
    var _a, _b, _c, _d, _e;
    const b = await (0, common_1.db)().doc(`business_identity/${uid}`).get();
    if (b.get('status') !== 'verified')
        throw new https_1.HttpsError('failed-precondition', 'Your business is not verified yet.');
    return {
        verified: true,
        level: Number((_a = b.get('level')) !== null && _a !== void 0 ? _a : 1),
        name: String((_b = b.get('legalName')) !== null && _b !== void 0 ? _b : ''),
        country: String((_c = b.get('country')) !== null && _c !== void 0 ? _c : ''),
        type: String((_d = b.get('businessType')) !== null && _d !== void 0 ? _d : ''),
        registration: String((_e = b.get('registrationNumber')) !== null && _e !== void 0 ? _e : ''),
        since: monthOf(b.get('verifiedAt')),
    };
}
const claimsFor = (uid, kind) => (kind === 'person' ? personClaims(uid) : businessClaims(uid));
exports.claimsFor = claimsFor;
const kindOf = (v) => (v === 'business' ? 'business' : 'person');
exports.idCredential = (0, https_1.onCall)({ secrets: [credentials_1.signingJwk] }, async (req) => {
    var _a;
    const uid = (0, common_1.callerUid)(req);
    const kind = kindOf((_a = req.data) === null || _a === void 0 ? void 0 : _a.kind);
    const claims = await (0, exports.claimsFor)(uid, kind);
    const { id, token, expiresAt } = await (0, credentials_1.issueCredential)(uid, kind, claims, kind === 'person' ? 2 : 1);
    await (0, common_1.audit)(uid, `${kind === 'person' ? 'id' : 'business'}.credential_issued`, 'you', 'Saved to this phone');
    return { id, token, expiresAt: expiresAt.toISOString() };
});
const SHARE_FIELDS = {
    person: ['name', 'country', 'document', 'since', 'handle'],
    business: ['name', 'country', 'type', 'registration', 'since'],
};
exports.idShare = (0, https_1.onCall)({ secrets: [credentials_1.signingJwk] }, async (req) => {
    var _a, _b, _c;
    const uid = (0, common_1.callerUid)(req);
    const kind = kindOf((_a = req.data) === null || _a === void 0 ? void 0 : _a.kind);
    const asked = Array.isArray((_b = req.data) === null || _b === void 0 ? void 0 : _b.fields) ? req.data.fields.map(String) : [];
    const fields = SHARE_FIELDS[kind].filter((f) => asked.includes(f));
    const minutes = Math.min(Math.max(Number((_c = req.data) === null || _c === void 0 ? void 0 : _c.minutes) || 10, 5), 60 * 24 * 30);
    const doc = (await (0, common_1.db)().doc(kind === 'person' ? `identity/${uid}` : `business_identity/${uid}`).get());
    let credentialId = doc.get('credentialId');
    const all = await (0, exports.claimsFor)(uid, kind);
    if (!credentialId)
        credentialId = (await (0, credentials_1.issueCredential)(uid, kind, all, kind === 'person' ? 2 : 1)).id;
    const claims = { verified: true, level: all.level };
    for (const f of fields)
        claims[f] = all[f];
    const shareId = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + minutes * 60000);
    await (0, common_1.db)().doc(`identity/${uid}/shares/${shareId}`).set({
        kind, fields, credentialId, createdAt: firestore_1.FieldValue.serverTimestamp(), expiresAt: firestore_1.Timestamp.fromDate(expiresAt), revokedAt: null, views: 0,
    });
    await (0, common_1.audit)(uid, `${kind === 'person' ? 'id' : 'business'}.shared`, 'you', fields.length ? `Shared: ${fields.join(', ')}` : 'Shared: verified only');
    const token = (0, credentials_1.signShare)(shareId, credentialId, kind, claims, minutes * 60);
    return { shareId, token, url: `${credentials_1.VERIFY_URL}#t=${token}`, expiresAt: expiresAt.toISOString() };
});
exports.idShareRevoke = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = (0, common_1.callerUid)(req);
    const shareId = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.shareId) !== null && _b !== void 0 ? _b : '');
    if (!/^[0-9a-f-]{36}$/.test(shareId))
        throw new https_1.HttpsError('invalid-argument', 'Unknown share.');
    const ref = (0, common_1.db)().doc(`identity/${uid}/shares/${shareId}`);
    if (!(await ref.get()).exists)
        throw new https_1.HttpsError('not-found', 'Unknown share.');
    await ref.update({ revokedAt: firestore_1.FieldValue.serverTimestamp() });
    await (0, common_1.audit)(uid, 'id.share_stopped', 'you');
    return { ok: true };
});
/** Deletes the ID photos and the check record; payouts stop until verified again. */
exports.kycDelete = (0, https_1.onCall)({ timeoutSeconds: 120 }, async (req) => {
    var _a;
    const uid = (0, common_1.callerUid)(req);
    if (((_a = req.data) === null || _a === void 0 ? void 0 : _a.confirm) !== true)
        throw new https_1.HttpsError('failed-precondition', 'Confirm first.');
    const removed = await (0, common_1.deleteFolder)(`kyc/${uid}/`);
    await (0, common_1.db)().doc(`kyc/${uid}`).delete();
    await (0, credentials_1.revokeCredential)(uid, 'person');
    await (0, common_1.db)().doc(`identity/${uid}`).set({
        level: 0, status: 'deleted', credentialId: firestore_1.FieldValue.delete(), credentialReady: false, deletedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    // A verified business needs a verified owner.
    const biz = (0, common_1.db)().doc(`business_identity/${uid}`);
    if ((await biz.get()).get('status') === 'verified') {
        await biz.set({ status: 'expired', expiredReason: 'The owner’s identity was deleted.', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        await (0, credentials_1.revokeCredential)(uid, 'business');
    }
    await (0, common_1.syncBadges)(uid);
    await (0, common_1.audit)(uid, 'id.deleted', 'you', `Identity data deleted (${removed} photos)`);
    return { ok: true, photosDeleted: removed };
});
//# sourceMappingURL=personal.js.map