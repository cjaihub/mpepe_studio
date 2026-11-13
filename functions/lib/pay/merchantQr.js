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
exports.payQrDisable = exports.payQrList = exports.payQrResolve = exports.payQrCreate = exports.qrRef = void 0;
exports.viewOf = viewOf;
/**
 * Scan to pay: merchant QR codes (`pay_qr/{code}`, server-only).
 *
 *   merchant → payQrCreate    a shop code (payer types the amount) or a one-time
 *                             code with an amount (15 minutes, paid once)
 *   payer    → payQrResolve   who is being paid and how much, before paying
 *   payer    → payCreate({ purpose: 'merchant', refId: code, amount? })
 *   merchant → payQrList / payQrDisable
 *
 * The QR holds only an unguessable code; the merchant, amount and currency
 * come from the server. Receiving money needs a verified identity (KYC), and
 * lands in the merchant's Oneova balance minus the merchant fee, so it is open
 * only where the stored balance is (PAY_WALLET_ENABLED / sandbox).
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("../guard/protect");
const provider_1 = require("../payments/provider");
const payLogic_1 = require("./payLogic");
const payConfig_1 = require("./payConfig");
const intents_1 = require("./intents");
const db = () => (0, firestore_1.getFirestore)();
const qrRef = (code) => db().doc(`pay_qr/${code}`);
exports.qrRef = qrRef;
function me(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
/** Upper bound for one QR payment, in major units of the currency (anti-abuse, KYC tier 1). */
const MAX_MAJOR = 1000000;
async function merchantProfile(uid) {
    var _a, _b;
    const [u, kyc] = await Promise.all([db().doc(`users/${uid}`).get(), db().doc(`kyc/${uid}`).get()]);
    const p = (_a = u.data()) !== null && _a !== void 0 ? _a : {};
    const avatar = (_b = [p.avatarUrl, p.photoUrl, p.photoURL].find((v) => typeof v === 'string' && v.startsWith('http'))) !== null && _b !== void 0 ? _b : null;
    return {
        name: String(p.businessName || p.fullName || p.displayName || p.username || 'Oneova merchant').slice(0, 80),
        avatarUrl: avatar,
        verified: kyc.get('status') === 'verified',
    };
}
function viewOf(code, q, m) {
    var _a;
    const amountMinor = typeof q.amountMinor === 'number' ? q.amountMinor : null;
    return {
        code, merchantUid: q.merchantUid, name: m.name, avatarUrl: m.avatarUrl, verified: m.verified,
        label: (_a = q.label) !== null && _a !== void 0 ? _a : null, currency: q.currency, amountMinor,
        amount: amountMinor == null ? null : (0, provider_1.toMajor)(amountMinor, q.currency), oneTime: q.oneTime === true,
    };
}
exports.payQrCreate = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = me(req);
    await (0, protect_1.limit)(uid, 'pay_qr_create', 30, 3600000);
    const rt = await (0, payConfig_1.payRuntime)();
    if (!rt.cfg.wallet)
        throw new https_1.HttpsError('failed-precondition', 'Receiving payments opens soon in your country.');
    const kyc = await db().doc(`kyc/${uid}`).get();
    if (kyc.get('status') !== 'verified')
        throw new https_1.HttpsError('failed-precondition', 'Verify your identity first to receive payments.');
    const country = await (0, intents_1.countryOf)(uid);
    const currency = (0, payLogic_1.currencyFor)(country);
    const raw = (_a = req.data) === null || _a === void 0 ? void 0 : _a.amount;
    let amountMinor = null;
    if (raw != null && raw !== '') {
        const amount = Number(raw);
        amountMinor = Number.isFinite(amount) ? (0, provider_1.toMinor)(amount, currency) : 0;
        if (amountMinor < (0, provider_1.toMinor)(1, currency) || amountMinor > (0, provider_1.toMinor)(MAX_MAJOR, currency))
            throw new https_1.HttpsError('invalid-argument', 'Enter an amount to receive.');
    }
    const label = typeof ((_b = req.data) === null || _b === void 0 ? void 0 : _b.label) === 'string' ? req.data.label.trim().slice(0, 60) || null : null;
    const oneTime = amountMinor != null;
    const code = crypto.randomBytes(16).toString('base64url').slice(0, 22);
    await (0, exports.qrRef)(code).set({
        merchantUid: uid, country, currency, amountMinor, label, oneTime, active: true, paid: false,
        paidCount: 0, receivedMinor: 0,
        expiresAt: oneTime ? firestore_1.Timestamp.fromMillis(Date.now() + payLogic_1.QR_ONE_TIME_TTL_MS) : null,
        createdAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    const m = await merchantProfile(uid);
    return Object.assign(Object.assign({}, viewOf(code, (await (0, exports.qrRef)(code).get()).data(), m)), { qr: `${payLogic_1.PAY_QR_PREFIX}${code}` });
});
exports.payQrResolve = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c, _d;
    const uid = me(req);
    await (0, protect_1.limit)(uid, 'pay_qr_resolve', 60, 600000);
    const code = (0, payLogic_1.qrCodeFrom)(String((_d = (_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.qr) !== null && _c !== void 0 ? _c : (_b = req.data) === null || _b === void 0 ? void 0 : _b.code) !== null && _d !== void 0 ? _d : ''));
    if (!code)
        throw new https_1.HttpsError('invalid-argument', 'This isn’t an Oneova Pay code.');
    const q = (await (0, exports.qrRef)(code).get()).data();
    const problem = (0, payLogic_1.qrProblem)(q);
    if (problem)
        throw new https_1.HttpsError('failed-precondition', problem);
    if (q.merchantUid === uid)
        throw new https_1.HttpsError('failed-precondition', 'This is your own code.');
    return viewOf(code, q, await merchantProfile(q.merchantUid));
});
exports.payQrList = (0, https_1.onCall)(async (req) => {
    const uid = me(req);
    const snap = await db().collection('pay_qr').where('merchantUid', '==', uid).orderBy('createdAt', 'desc').limit(30).get();
    const m = await merchantProfile(uid);
    return {
        codes: snap.docs.map((d) => { var _a, _b; return (Object.assign(Object.assign({}, viewOf(d.id, d.data(), m)), { qr: `${payLogic_1.PAY_QR_PREFIX}${d.id}`, active: d.get('active') === true && !(0, payLogic_1.qrProblem)(d.data()), paidCount: Number((_a = d.get('paidCount')) !== null && _a !== void 0 ? _a : 0), receivedMinor: Number((_b = d.get('receivedMinor')) !== null && _b !== void 0 ? _b : 0) })); }),
    };
});
exports.payQrDisable = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = me(req);
    const code = (0, payLogic_1.qrCodeFrom)(String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : ''));
    if (!code)
        throw new https_1.HttpsError('invalid-argument', 'Missing code.');
    await db().runTransaction(async (tx) => {
        const q = (await tx.get((0, exports.qrRef)(code))).data();
        if (!q || q.merchantUid !== uid)
            throw new https_1.HttpsError('not-found', 'Code not found.');
        tx.update((0, exports.qrRef)(code), { active: false, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
    return { ok: true };
});
//# sourceMappingURL=merchantQr.js.map