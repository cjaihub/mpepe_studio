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
exports.kycLinkAccount = exports.MAX_LINKED = void 0;
exports.normalizeIdNumber = normalizeIdNumber;
exports.idHash = idHash;
exports.idStatusFor = idStatusFor;
exports.lookupId = lookupId;
exports.claimId = claimId;
/**
 * One ID, one person (with linked accounts).
 *
 * The ID number read from the document is never stored. It is turned into an
 * HMAC-SHA256 with a secret pepper (`KYC_ID_PEPPER`, Secret Manager), so the
 * index can't be reversed or matched against a leaked list without the key.
 *
 *   kyc_id_index/{hash} = { primaryUid, linkedUids: [...] }   (server only)
 *
 * - The first verified account owns the ID.
 * - Another account submitting the same ID is flagged as a duplicate and can't
 *   be approved, unless the owner linked it first (`kycLinkAccount`), for
 *   example a business or creator second account. At most [MAX_LINKED].
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("../guard/protect");
exports.MAX_LINKED = 3;
const db = () => (0, firestore_1.getFirestore)();
/** Letters and digits only, upper case: "AB 12-34" → "AB1234". */
function normalizeIdNumber(raw) {
    if (typeof raw !== 'string')
        return null;
    const n = raw.normalize('NFKC').toUpperCase().replace(/[^A-Z0-9]/g, '');
    return n.length >= 5 && n.length <= 24 ? n : null;
}
function idHash(pepper, country, docType, number) {
    return crypto.createHmac('sha256', pepper).update(`${country.toUpperCase()}|${docType}|${number}`).digest('hex');
}
function idStatusFor(index, uid) {
    var _a;
    if (!(index === null || index === void 0 ? void 0 : index.primaryUid))
        return 'new';
    if (index.primaryUid === uid)
        return 'same';
    return ((_a = index.linkedUids) !== null && _a !== void 0 ? _a : []).includes(uid) ? 'linked' : 'duplicate';
}
async function lookupId(hash, uid) {
    const s = await db().collection('kyc_id_index').doc(hash).get();
    const d = s.data();
    return { status: idStatusFor(d, uid), primaryUid: d === null || d === void 0 ? void 0 : d.primaryUid };
}
/** On approval: the ID becomes this person's, or this account joins as linked. Throws on a duplicate. */
async function claimId(hash, uid) {
    const ref = db().collection('kyc_id_index').doc(hash);
    return db().runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const d = s.data();
        const st = idStatusFor(d, uid);
        if (st === 'duplicate')
            throw new https_1.HttpsError('already-exists', 'This ID is already verified on another Oneova account.');
        if (st === 'new')
            tx.set(ref, { primaryUid: uid, linkedUids: [], createdAt: firestore_1.FieldValue.serverTimestamp() });
        return st;
    });
}
/**
 * The verified owner of an ID allows one more of their own accounts (by
 * @username) to verify with the same ID.
 */
exports.kycLinkAccount = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    await (0, protect_1.limit)(uid, 'kyc_link', 10, 24 * 3600000);
    const handle = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.username) !== null && _d !== void 0 ? _d : '').trim().replace(/^@/, '').toLowerCase();
    if (!/^[a-z0-9._]{2,30}$/.test(handle))
        throw new https_1.HttpsError('invalid-argument', 'Enter the other account’s @username.');
    const mine = (await db().doc(`kyc/${uid}`).get()).data();
    if ((mine === null || mine === void 0 ? void 0 : mine.status) !== 'verified' || typeof mine.idHash !== 'string') {
        throw new https_1.HttpsError('failed-precondition', 'Verify your own ID first, then you can link your other accounts.');
    }
    const q = await db().collection('users').where('username', '==', handle).limit(1).get();
    const target = (_c = q.docs[0]) === null || _c === void 0 ? void 0 : _c.id;
    if (!target)
        throw new https_1.HttpsError('not-found', 'No account with that @username.');
    if (target === uid)
        throw new https_1.HttpsError('invalid-argument', 'That’s this account.');
    const ref = db().collection('kyc_id_index').doc(mine.idHash);
    await db().runTransaction(async (tx) => {
        var _a;
        const s = await tx.get(ref);
        const d = s.data();
        if ((d === null || d === void 0 ? void 0 : d.primaryUid) !== uid)
            throw new https_1.HttpsError('permission-denied', 'Only the first account verified with this ID can link others.');
        const linked = (_a = d.linkedUids) !== null && _a !== void 0 ? _a : [];
        if (linked.includes(target))
            return;
        if (linked.length >= exports.MAX_LINKED)
            throw new https_1.HttpsError('resource-exhausted', `You can link up to ${exports.MAX_LINKED} accounts.`);
        tx.update(ref, { linkedUids: firestore_1.FieldValue.arrayUnion(target), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
    return { ok: true, linked: handle };
});
//# sourceMappingURL=kycIdentity.js.map