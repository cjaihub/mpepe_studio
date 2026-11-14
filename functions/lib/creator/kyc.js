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
exports.kycReview = exports.kycRefresh = exports.kycSubmit = exports.kycStart = void 0;
/**
 * Identity verification (KYC) before anyone is paid out: Oneova's own check.
 *
 *   app → kycStart     opens a check; returns the private Storage folder
 *                      `kyc/{uid}/{sessionId}/` for the photos
 *   app                uploads id_front.jpg, id_back.jpg (optional), selfie.jpg
 *                      (only the owner can write there; nobody can read them
 *                      from the app — see storage.rules)
 *   app → kycSubmit    status "review"; an AI pre-check (Vertex AI) reads the
 *                      ID and compares the faces for the reviewer. It never
 *                      approves anyone on its own.
 *   admin → kycReview  verified (with the name on the ID) or rejected
 *   app → kycRefresh   current status
 *
 * `kyc/{uid}` (server-written) keeps the status, the verified name, country
 * and document type, and the pre-check summary for the reviewer.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const vertexAi_1 = require("../vertexAi");
const personal_1 = require("../identity/personal");
const kycSignals_1 = require("./kycSignals");
const db = () => (0, firestore_1.getFirestore)();
const DOC_TYPES = ['passport', 'id_card', 'driving_license'];
function me(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
exports.kycStart = (0, https_1.onCall)(async (req) => {
    const uid = me(req);
    const current = (await db().doc(`kyc/${uid}`).get()).data();
    if ((current === null || current === void 0 ? void 0 : current.status) === 'verified')
        return { status: 'verified' };
    if ((current === null || current === void 0 ? void 0 : current.status) === 'review')
        return { status: 'review' };
    // Reuse an open check so a second tap continues it.
    const sessionId = (current === null || current === void 0 ? void 0 : current.status) === 'collecting' && current.sessionId ? String(current.sessionId) : crypto.randomUUID();
    await db().doc(`kyc/${uid}`).set({
        uid, provider: 'oneova', sessionId, status: 'collecting',
        startedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { status: 'collecting', sessionId, path: `kyc/${uid}/${sessionId}` };
});
/** Reads the ID and compares the faces for the reviewer. Best effort. */
async function aiPreCheck(path, hasBack) {
    var _a, _b;
    try {
        const bucket = (0, storage_1.getStorage)().bucket();
        const load = async (name) => (await bucket.file(`${path}/${name}`).download())[0].toString('base64');
        const [front, selfie, back] = await Promise.all([load('id_front.jpg'), load('selfie.jpg'), hasBack ? load('id_back.jpg') : Promise.resolve(null)]);
        const res = await (0, vertexAi_1.generateVertexContent)({
            contents: [{
                    role: 'user',
                    parts: [
                        { text: 'Image 1 is the front of an identity document. Image 2 is a selfie.' + (back ? ' Image 3 is the back of the document.' : '') },
                        { inlineData: { mimeType: 'image/jpeg', data: front } },
                        { inlineData: { mimeType: 'image/jpeg', data: selfie } },
                        ...(back ? [{ inlineData: { mimeType: 'image/jpeg', data: back } }] : []),
                    ],
                }],
            config: {
                systemInstruction: 'You help a human reviewer check identity documents. Reply ONLY with JSON: ' +
                    '{"documentType":"passport|id_card|driving_license|other|unreadable","fullName":"name as printed or empty",' +
                    '"country":"ISO-3166 alpha-2 of the issuing country or empty","expired":true|false|null,' +
                    '"faceMatch":"likely|unlikely|unclear","readable":true|false,"concerns":["short notes, e.g. screen photo, cropped, edited"]}. ' +
                    'Never guess a name you cannot read.',
                responseMimeType: 'application/json',
                temperature: 0,
                maxOutputTokens: 400,
                thinkingConfig: { thinkingBudget: 0 },
            },
        });
        return JSON.parse((_a = res.text) !== null && _a !== void 0 ? _a : '{}');
    }
    catch (e) {
        logger.warn('kyc pre-check failed', (_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : e);
        return null;
    }
}
exports.kycSubmit = (0, https_1.onCall)({ timeoutSeconds: 120, memory: '512MiB' }, async (req) => {
    var _a, _b, _c, _d, _e;
    var _f, _g;
    const uid = me(req);
    const current = (await db().doc(`kyc/${uid}`).get()).data();
    const sessionId = String((_f = (_a = req.data) === null || _a === void 0 ? void 0 : _a.sessionId) !== null && _f !== void 0 ? _f : '');
    if (!current || current.status !== 'collecting' || current.sessionId !== sessionId) {
        throw new https_1.HttpsError('failed-precondition', 'Start the identity check again.');
    }
    const documentType = DOC_TYPES.includes(String((_b = req.data) === null || _b === void 0 ? void 0 : _b.documentType)) ? String(req.data.documentType) : null;
    const country = typeof ((_c = req.data) === null || _c === void 0 ? void 0 : _c.country) === 'string' && /^[A-Za-z]{2}$/.test(req.data.country) ? req.data.country.toUpperCase() : null;
    const fullName = String((_g = (_d = req.data) === null || _d === void 0 ? void 0 : _d.fullName) !== null && _g !== void 0 ? _g : '').trim().replace(/\s+/g, ' ').slice(0, 120);
    if (!documentType || !country || fullName.length < 3)
        throw new https_1.HttpsError('invalid-argument', 'Fill in your name, country and ID type.');
    const path = `kyc/${uid}/${sessionId}`;
    const bucket = (0, storage_1.getStorage)().bucket();
    const [[front], [selfie], [back]] = await Promise.all([
        bucket.file(`${path}/id_front.jpg`).exists(), bucket.file(`${path}/selfie.jpg`).exists(), bucket.file(`${path}/id_back.jpg`).exists(),
    ]);
    if (!front || !selfie)
        throw new https_1.HttpsError('failed-precondition', 'Add a photo of your ID and a selfie.');
    const countrySignals = (0, kycSignals_1.cleanCountrySignals)((_e = req.data) === null || _e === void 0 ? void 0 : _e.countrySignals);
    await db().doc(`kyc/${uid}`).set({
        status: 'review', documentType, country, submittedName: fullName, hasBack: back,
        countrySignals, countryMismatch: (0, kycSignals_1.countryMismatch)(country, countrySignals),
        submittedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    await (0, personal_1.onPersonalSubmitted)(uid);
    const ai = await aiPreCheck(path, back);
    if (ai)
        await db().doc(`kyc/${uid}`).set({ aiCheck: ai, aiCheckedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    return { status: 'review' };
});
exports.kycRefresh = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    const uid = me(req);
    const k = (await db().doc(`kyc/${uid}`).get()).data();
    return { status: (_a = k === null || k === void 0 ? void 0 : k.status) !== null && _a !== void 0 ? _a : 'none', reason: (_b = k === null || k === void 0 ? void 0 : k.rejectReason) !== null && _b !== void 0 ? _b : null, verifiedName: (_c = k === null || k === void 0 ? void 0 : k.verifiedName) !== null && _c !== void 0 ? _c : null };
});
/** Admin decision (from the admin dashboard). */
exports.kycReview = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e;
    var _f, _g, _h, _j, _k;
    const admin = me(req);
    if ((await db().doc(`users/${admin}`).get()).get('role') !== 'admin')
        throw new https_1.HttpsError('permission-denied', 'Admins only.');
    const uid = String((_f = (_a = req.data) === null || _a === void 0 ? void 0 : _a.uid) !== null && _f !== void 0 ? _f : '');
    if (!uid || uid.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Missing user.');
    const k = (await db().doc(`kyc/${uid}`).get()).data();
    if (!k || k.status !== 'review')
        throw new https_1.HttpsError('failed-precondition', 'Nothing to review for this user.');
    if (((_b = req.data) === null || _b === void 0 ? void 0 : _b.approve) === true) {
        const name = String((_h = (_g = (_c = req.data) === null || _c === void 0 ? void 0 : _c.verifiedName) !== null && _g !== void 0 ? _g : k.submittedName) !== null && _h !== void 0 ? _h : '').trim().slice(0, 120);
        if (name.length < 3)
            throw new https_1.HttpsError('invalid-argument', 'Enter the name exactly as on the ID.');
        await db().doc(`kyc/${uid}`).set({
            status: 'verified', verifiedName: name, country: String((_j = (_d = req.data) === null || _d === void 0 ? void 0 : _d.country) !== null && _j !== void 0 ? _j : k.country), documentType: k.documentType,
            reviewedBy: admin, verifiedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        await db().collection('notifications').doc(`kyc_ok_${uid}`).set({
            userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
            title: 'You’re verified ✅', body: 'You can now withdraw your earnings.', deepLink: '/wallet/withdraw',
            isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        await (0, personal_1.onPersonalVerified)(uid, admin);
    }
    else {
        const reason = String((_k = (_e = req.data) === null || _e === void 0 ? void 0 : _e.reason) !== null && _k !== void 0 ? _k : 'We couldn’t confirm your ID. Please try again with clear photos.').slice(0, 200);
        await db().doc(`kyc/${uid}`).set({
            status: 'rejected', rejectReason: reason, reviewedBy: admin, updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        await db().collection('notifications').doc(`kyc_no_${uid}_${Date.now()}`).set({
            userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
            title: 'Identity check needs another try', body: reason, deepLink: '/wallet/verify',
            isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        await (0, personal_1.onPersonalRejected)(uid, reason);
    }
    return { ok: true };
});
//# sourceMappingURL=kyc.js.map