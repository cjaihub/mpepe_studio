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
exports.payBalanceReconcile = exports.payWithdraw = exports.isPayPayoutReference = void 0;
exports.settlePayPayout = settlePayPayout;
/**
 * Withdrawals from the Oneova balance (`pay_balances`) — what sellers and
 * riders earn from orders — to the payout methods saved in the creator
 * payout flow (`payout_methods/{uid}/methods`, verified name from KYC).
 *
 *   app → payWithdraw     locks the amount (available → locked), sends it
 *   partner webhooks      → settlePayPayout (references start with "pp_")
 *   payBalanceReconcile   asks the partner about payouts with no answer yet
 *
 * Same safety rule as every payout: on an unclear reply nothing is returned
 * or re-sent until the partner's status says what happened.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const provider_1 = require("../payments/provider");
const adapters_1 = require("../payments/adapters");
const mockProvider_1 = require("../payments/mockProvider");
const router_1 = require("../payments/router");
const payouts_1 = require("../creator/payouts");
const payLogic_1 = require("./payLogic");
const ledger_1 = require("./ledger");
const payConfig_1 = require("./payConfig");
const db = () => (0, firestore_1.getFirestore)();
const payoutRef = (id) => db().doc(`pay_payouts/${id}`);
const isPayPayoutReference = (ref) => /^pp_[0-9a-f]{32}$/.test(ref);
exports.isPayPayoutReference = isPayPayoutReference;
function me(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
async function notify(uid, id, title, body) {
    await db().collection('notifications').doc(id).set({
        userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
        title, body, deepLink: '/biz/payouts', isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    }).catch(() => undefined);
}
/** The adapter for a payout; the sandbox uses the mock (no money moves). */
async function adapterForPayout(p) {
    if (p.sandbox === true)
        return new mockProvider_1.MockProvider({ id: 'mock' });
    const secretRef = db().doc(`payout_method_secrets/${p.uid}_${p.methodId}`);
    return (0, payouts_1.adapterFor)(p.provider, await (0, payouts_1.payoutsConfigured)(), secretRef);
}
function payoutRequest(id, p, s) {
    const momo = p.rail === 'mobile_money';
    return {
        reference: id, country: p.country, rail: p.rail, currency: p.currency, amountMinor: Number(p.netMinor),
        holderName: p.holderName, account: momo ? s.msisdn : s.accountNumber,
        bankCode: p.provider === 'paystack' ? (momo ? s.paystackBank : s.bankCode) : (momo ? s.flwBank : s.bankCode),
        narration: 'Oneova earnings',
    };
}
/** Finishes a balance payout once: paid (locked → out) or failed (locked → available). */
async function settlePayPayout(id, to, info = {}) {
    var _a;
    const ref = payoutRef(id);
    const done = await db().runTransaction(async (tx) => {
        const [snap, posted] = await Promise.all([tx.get(ref), tx.get((0, ledger_1.ledgerRef)(`ppdone_${id}`))]);
        const p = snap.data();
        if (!p || !['pending', 'processing'].includes(p.status) || posted.exists)
            return null;
        const lines = to === 'paid'
            ? [
                { account: (0, payLogic_1.ownerAccount)((0, payLogic_1.balanceKind)(p.balance), p.uid), currency: p.currency, amountMinor: -p.amountMinor, bucket: 'locked' },
                { account: `payout:${p.provider}`, currency: p.currency, amountMinor: p.netMinor },
                ...(p.feeMinor > 0 ? [{ account: 'platform:revenue', currency: p.currency, amountMinor: p.feeMinor }] : []),
            ]
            : [
                { account: (0, payLogic_1.ownerAccount)((0, payLogic_1.balanceKind)(p.balance), p.uid), currency: p.currency, amountMinor: -p.amountMinor, bucket: 'locked' },
                { account: (0, payLogic_1.ownerAccount)((0, payLogic_1.balanceKind)(p.balance), p.uid), currency: p.currency, amountMinor: p.amountMinor, bucket: 'available' },
            ];
        (0, ledger_1.writeLedger)(tx, `ppdone_${id}`, false, to === 'paid' ? 'balance_payout' : 'balance_payout_returned', lines, { payoutId: id });
        tx.update(ref, Object.assign(Object.assign({ status: to, needsCheck: false }, info), { updatedAt: firestore_1.FieldValue.serverTimestamp() }));
        return p;
    });
    if (!done)
        return false;
    const money = `${done.currency} ${(0, provider_1.toMajor)(Number(done.netMinor), done.currency).toLocaleString('en-US')}`;
    if (to === 'paid')
        await notify(done.uid, `pp_paid_${id}`, 'Money sent 🎉', `${money} is on its way to your ${done.methodLabel}.`);
    else
        await notify(done.uid, `pp_failed_${id}`, 'Withdrawal didn’t go through', `The money is back in your Oneova balance. ${(_a = info.failureReason) !== null && _a !== void 0 ? _a : ''}`.trim());
    return true;
}
async function dispatch(id) {
    const ref = payoutRef(id);
    const p = await db().runTransaction(async (tx) => {
        const d = (await tx.get(ref)).data();
        if (!d || d.status !== 'pending')
            return null;
        tx.update(ref, { status: 'processing', updatedAt: firestore_1.FieldValue.serverTimestamp() });
        return d;
    });
    if (!p)
        return;
    const s = (await db().doc(`payout_method_secrets/${p.uid}_${p.methodId}`).get()).data();
    if (!s && p.sandbox !== true) {
        await settlePayPayout(id, 'failed', { failureReason: 'The payout method was removed.' });
        return;
    }
    const adapter = await adapterForPayout(p);
    if (!adapter) {
        await settlePayPayout(id, 'failed', { failureReason: 'Payouts are paused for this method.' });
        return;
    }
    const { outcome } = await (0, router_1.routePayout)([adapter], payoutRequest(id, p, s !== null && s !== void 0 ? s : {}));
    if (outcome.kind === 'accepted') {
        if (p.sandbox === true) {
            await settlePayPayout(id, 'paid', { providerRef: outcome.providerRef, paidAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        await ref.update({ providerRef: outcome.providerRef, sentAt: firestore_1.FieldValue.serverTimestamp(), needsCheck: true, checkAfter: firestore_1.Timestamp.fromMillis(Date.now() + 6 * 3600000) });
    }
    else if (outcome.kind === 'rejected') {
        await settlePayPayout(id, 'failed', { failureReason: outcome.reason.slice(0, 200) });
    }
    else {
        logger.error('balance payout unknown; will reconcile', id, outcome.reason);
        await ref.update({ sentAt: firestore_1.FieldValue.serverTimestamp(), needsCheck: true, checkAfter: firestore_1.Timestamp.fromMillis(Date.now() + 10 * 60000), lastCheckNote: outcome.reason.slice(0, 200) });
    }
}
exports.payWithdraw = (0, https_1.onCall)({ timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c, _d, _e;
    var _f, _g, _h, _j;
    const uid = me(req);
    const key = String((_f = (_a = req.data) === null || _a === void 0 ? void 0 : _a.idempotencyKey) !== null && _f !== void 0 ? _f : '');
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(key))
        throw new https_1.HttpsError('invalid-argument', 'Missing request id.');
    const id = `pp_${crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 32)}`;
    const existing = (await payoutRef(id).get()).data();
    if (existing)
        return { id, status: existing.status };
    const rt = await (0, payConfig_1.payRuntime)();
    const kyc = (await db().doc(`kyc/${uid}`).get()).data();
    if ((kyc === null || kyc === void 0 ? void 0 : kyc.status) !== 'verified' && !rt.cfg.sandbox)
        throw new https_1.HttpsError('failed-precondition', 'Verify your identity first. It keeps your money safe.');
    const methodId = String((_g = (_b = req.data) === null || _b === void 0 ? void 0 : _b.methodId) !== null && _g !== void 0 ? _g : '');
    const method = methodId && !methodId.includes('/') ? (await db().doc(`payout_methods/${uid}/methods/${methodId}`).get()).data() : null;
    if (!method)
        throw new https_1.HttpsError('failed-precondition', 'Add a payout method first.');
    const currency = String((_j = (_h = (_c = req.data) === null || _c === void 0 ? void 0 : _c.currency) !== null && _h !== void 0 ? _h : method.currency) !== null && _j !== void 0 ? _j : '').toUpperCase();
    if (currency !== String(method.currency).toUpperCase()) {
        throw new https_1.HttpsError('failed-precondition', `This payout method pays in ${method.currency}. Choose a ${currency} method.`);
    }
    const amountMinor = Math.floor(Number((_d = req.data) === null || _d === void 0 ? void 0 : _d.amountMinor));
    if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0)
        throw new https_1.HttpsError('invalid-argument', 'Enter an amount.');
    const feeMinor = (0, payLogic_1.balancePayoutFee)(method.rail, amountMinor);
    const netMinor = amountMinor - feeMinor;
    if (netMinor <= 0)
        throw new https_1.HttpsError('failed-precondition', 'The amount is smaller than the payout fee.');
    const hold = (await db().doc(`payout_holds/${uid}`).get()).get('reasons');
    // Withdraw from the personal balance (default) or the business one (shop sales, scan to pay).
    const balance = (0, payLogic_1.balanceKind)((_e = req.data) === null || _e === void 0 ? void 0 : _e.balance);
    const acct = (0, payLogic_1.ownerAccount)(balance, uid);
    await db().runTransaction(async (tx) => {
        var _a, _b, _c;
        const [bal, cur, posted] = await Promise.all([tx.get((0, ledger_1.balanceRefOf)(balance, uid)), tx.get(payoutRef(id)), tx.get((0, ledger_1.ledgerRef)(`ppreq_${id}`))]);
        if (cur.exists)
            return;
        if ((0, ledger_1.bucketOf)(bal.data(), currency, 'available') < amountMinor) {
            throw new https_1.HttpsError('failed-precondition', `Not enough in your ${balance === 'business' ? 'business' : 'Oneova'} balance.`);
        }
        (0, ledger_1.writeLedger)(tx, `ppreq_${id}`, posted.exists, 'balance_payout_lock', [
            { account: acct, currency, amountMinor: -amountMinor, bucket: 'available' },
            { account: acct, currency, amountMinor, bucket: 'locked' },
        ], { payoutId: id, balance });
        tx.set(payoutRef(id), {
            uid, balance, methodId, methodLabel: (_a = method.label) !== null && _a !== void 0 ? _a : 'payout method', rail: method.rail, provider: method.provider,
            country: method.country, currency, holderName: (_c = (_b = method.holderName) !== null && _b !== void 0 ? _b : kyc === null || kyc === void 0 ? void 0 : kyc.verifiedName) !== null && _c !== void 0 ? _c : '',
            amountMinor, feeMinor, netMinor, status: 'pending', sandbox: rt.cfg.sandbox && (kyc === null || kyc === void 0 ? void 0 : kyc.status) !== 'verified',
            review: !!(hold === null || hold === void 0 ? void 0 : hold.length), reviewReasons: hold !== null && hold !== void 0 ? hold : [],
            createdAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    if (!(hold === null || hold === void 0 ? void 0 : hold.length))
        await dispatch(id);
    const p = (await payoutRef(id).get()).data();
    return { id, status: p.status, netMinor, feeMinor, currency, review: !!(hold === null || hold === void 0 ? void 0 : hold.length) };
});
exports.payBalanceReconcile = (0, scheduler_1.onSchedule)('every 15 minutes', async () => {
    var _a;
    var _b, _c, _d;
    const due = (await db().collection('pay_payouts').where('needsCheck', '==', true).limit(200).get())
        .docs.filter((d) => { var _a; var _b; return ((_b = (_a = d.get('checkAfter')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : 0) <= Date.now(); }).slice(0, 50);
    for (const d of due) {
        try {
            const p = d.data();
            const adapter = await adapterForPayout(p);
            if (!adapter)
                continue;
            const policy = (_b = adapters_1.POLICY[p.provider]) !== null && _b !== void 0 ? _b : { notFoundIsFinalAfterMs: null, idempotentRetry: false };
            const status = (await adapter.status(d.id)).status;
            const age = Date.now() - ((_c = (_a = p.sentAt) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _c !== void 0 ? _c : Date.now());
            const action = (0, router_1.reconcileAction)(status, age, { notFoundIsFinalAfterMs: policy.notFoundIsFinalAfterMs });
            if (action === 'settle_paid')
                await settlePayPayout(d.id, 'paid', { paidAt: firestore_1.FieldValue.serverTimestamp() });
            else if (action === 'settle_failed')
                await settlePayPayout(d.id, 'failed', { failureReason: 'The network didn’t complete it.' });
            else if (action === 'review')
                await d.ref.update({ needsCheck: false, review: true, reviewReasons: firestore_1.FieldValue.arrayUnion('provider_status_unknown') });
            else
                await d.ref.update({ checkAfter: firestore_1.Timestamp.fromMillis(Date.now() + 30 * 60000), checks: firestore_1.FieldValue.increment(1), lastCheckNote: status });
        }
        catch (e) {
            logger.error('balance payout reconcile failed', d.id, (_d = e === null || e === void 0 ? void 0 : e.message) !== null && _d !== void 0 ? _d : e);
        }
    }
});
//# sourceMappingURL=balancePayouts.js.map