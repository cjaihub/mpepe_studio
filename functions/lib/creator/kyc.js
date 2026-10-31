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
exports.creatorStripeWebhook = exports.kycRefresh = exports.kycStart = void 0;
/**
 * Identity verification (KYC) before a creator's first withdrawal, with
 * Stripe Identity: government ID + live selfie, captured on Stripe's hosted
 * page. Oneova never receives or stores the images; `kyc/{uid}` keeps only the
 * status, the name and country on the ID, and the document type.
 *
 *   app → kycStart            VerificationSession → hosted url
 *   app → kycRefresh          re-reads the session (after returning to the app)
 *   Stripe → creatorStripeWebhook  identity.verification_session.* and transfer.reversed
 *
 * Secrets: STRIPE_SECRET_KEY, STRIPE_PAYOUTS_WEBHOOK_SECRET (a separate
 * webhook endpoint from Biz commerce, so each has its own signing secret).
 */
const stripe_1 = __importDefault(require("stripe"));
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const optionalSecrets_1 = require("../optionalSecrets");
const payouts_1 = require("./payouts");
const db = () => (0, firestore_1.getFirestore)();
const RETURN_URL = 'https://mpepe-2b4bd.web.app/';
async function stripe() {
    const key = await (0, optionalSecrets_1.optionalSecret)('STRIPE_SECRET_KEY');
    if (!key)
        throw new https_1.HttpsError('failed-precondition', 'Identity checks are being set up. Please try again soon.');
    return new stripe_1.default(key, { apiVersion: '2025-02-24.acacia' });
}
const STATUS = {
    verified: 'verified', processing: 'processing', requires_input: 'requires_input', canceled: 'canceled',
};
async function store(uid, s) {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h, _j;
    const out = s.verified_outputs;
    const name = [out === null || out === void 0 ? void 0 : out.first_name, out === null || out === void 0 ? void 0 : out.last_name].filter(Boolean).join(' ').trim();
    const report = typeof s.last_verification_report === 'object' ? s.last_verification_report : null;
    const idCountry = (_f = (_e = (_a = report === null || report === void 0 ? void 0 : report.document) === null || _a === void 0 ? void 0 : _a.issuing_country) !== null && _e !== void 0 ? _e : (_b = out === null || out === void 0 ? void 0 : out.address) === null || _b === void 0 ? void 0 : _b.country) !== null && _f !== void 0 ? _f : null;
    await db().doc(`kyc/${uid}`).set(Object.assign(Object.assign({ uid, provider: 'stripe_identity', sessionId: s.id, status: (_g = STATUS[s.status]) !== null && _g !== void 0 ? _g : 'processing', lastError: (_h = (_c = s.last_error) === null || _c === void 0 ? void 0 : _c.reason) !== null && _h !== void 0 ? _h : null }, (s.status === 'verified' ? {
        verifiedName: name || null,
        country: idCountry,
        documentType: (_j = (_d = report === null || report === void 0 ? void 0 : report.document) === null || _d === void 0 ? void 0 : _d.type) !== null && _j !== void 0 ? _j : null,
        verifiedAt: firestore_1.FieldValue.serverTimestamp(),
    } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
}
exports.kycStart = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const current = (await db().doc(`kyc/${uid}`).get()).data();
    if ((current === null || current === void 0 ? void 0 : current.status) === 'verified')
        return { status: 'verified' };
    const s = await stripe();
    // Reuse an open session so a second tap continues the same check.
    if ((current === null || current === void 0 ? void 0 : current.sessionId) && ['requires_input', 'processing'].includes(current.status)) {
        const old = await s.identity.verificationSessions.retrieve(current.sessionId);
        if (old.status === 'requires_input' && old.url)
            return { status: old.status, url: old.url };
        if (old.status === 'processing')
            return { status: 'processing' };
    }
    const session = await s.identity.verificationSessions.create({
        type: 'document',
        options: { document: { require_live_capture: true, require_matching_selfie: true, allowed_types: ['passport', 'id_card', 'driving_license'] } },
        metadata: { uid },
        return_url: RETURN_URL,
    });
    await db().doc(`kyc/${uid}`).set({
        uid, provider: 'stripe_identity', sessionId: session.id, status: 'requires_input',
        startedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { status: 'requires_input', url: session.url };
});
exports.kycRefresh = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const current = (await db().doc(`kyc/${uid}`).get()).data();
    if (!(current === null || current === void 0 ? void 0 : current.sessionId))
        return { status: 'none' };
    if (current.status === 'verified')
        return { status: 'verified' };
    const session = await (await stripe()).identity.verificationSessions.retrieve(current.sessionId, { expand: ['verified_outputs', 'last_verification_report'] });
    await store(uid, session);
    return { status: (_b = STATUS[session.status]) !== null && _b !== void 0 ? _b : 'processing' };
});
exports.creatorStripeWebhook = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b;
    var _c, _d;
    const secret = await (0, optionalSecrets_1.optionalSecret)('STRIPE_PAYOUTS_WEBHOOK_SECRET');
    if (!secret) {
        res.status(503).send('not configured');
        return;
    }
    let event;
    try {
        event = (await stripe()).webhooks.constructEvent(req.rawBody, String((_c = req.headers['stripe-signature']) !== null && _c !== void 0 ? _c : ''), secret);
    }
    catch (e) {
        logger.warn('creator webhook signature failed', e === null || e === void 0 ? void 0 : e.message);
        res.status(400).send('bad signature');
        return;
    }
    try {
        if (event.type.startsWith('identity.verification_session.')) {
            const s = event.data.object;
            const uid = (_a = s.metadata) === null || _a === void 0 ? void 0 : _a.uid;
            if (uid) {
                const full = await (await stripe()).identity.verificationSessions.retrieve(s.id, { expand: ['verified_outputs', 'last_verification_report'] });
                await store(uid, full);
                if (full.status === 'verified') {
                    await db().collection('notifications').doc(`kyc_ok_${uid}`).set({
                        userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
                        title: 'You’re verified ✅', body: 'You can now withdraw your earnings.', deepLink: '/wallet/withdraw',
                        isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
                    });
                }
            }
        }
        else if (event.type === 'transfer.reversed') {
            const t = event.data.object;
            const wid = (_b = t.metadata) === null || _b === void 0 ? void 0 : _b.withdrawalId;
            if (wid)
                await (0, payouts_1.settleWithdrawal)(wid, 'failed', { failureReason: 'The transfer was reversed.' });
        }
        res.status(200).send('ok');
    }
    catch (e) {
        logger.error('creator webhook failed', event.type, (_d = e === null || e === void 0 ? void 0 : e.message) !== null && _d !== void 0 ? _d : e);
        res.status(500).send('error');
    }
});
//# sourceMappingURL=kyc.js.map