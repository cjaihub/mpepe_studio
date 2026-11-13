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
exports.payReturn = exports.isIntentReference = exports.payWebhookMomo = exports.payWebhookMpesa = exports.payReconcileIntents = exports.payCancel = exports.payStatus = exports.payCreate = exports.payMethods = void 0;
exports.countryOf = countryOf;
exports.refreshIntent = refreshIntent;
exports.refundIntent = refundIntent;
/**
 * Oneova Pay pay-ins (`pay_intents/{id}`, id = UUID).
 *
 *   app → payMethods     ways to pay in the payer's country
 *   app → payCreate      server prices it (order / top-up), asks the partner:
 *                        a prompt on the payer's phone, a partner's secure page
 *                        (redirectUrl), or the Oneova balance (instant)
 *   app → payStatus      live status (the app also listens to the intent doc)
 *   app → payCancel      stop waiting (a late approval is still honoured)
 *   partners → webhooks  never trusted on their own: they only trigger a
 *                        status check against the partner's API
 *   payReconcileIntents  asks partners about intents still waiting
 *
 * Money safety:
 *   - The amount always comes from the server (order doc / validated top-up).
 *   - A pay-in is applied once: the ledger posting `payin_{id}` is the lock.
 *   - If the partner reports a different amount or currency, nothing is
 *     applied; the intent goes to review.
 *   - Money that arrives after a cancel / expiry is still recorded.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const auth_1 = require("firebase-admin/auth");
const provider_1 = require("../payments/provider");
const payoutLogic_1 = require("../creator/payoutLogic");
const payLogic_1 = require("./payLogic");
const ledger_1 = require("./ledger");
const payConfig_1 = require("./payConfig");
const orderEscrow_1 = require("../commerce/orderEscrow");
const db = () => (0, firestore_1.getFirestore)();
const intentRef = (id) => db().doc(`pay_intents/${id}`);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function me(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
const cc = (v) => (typeof v === 'string' && /^[A-Za-z]{2}$/.test(v) ? v.toUpperCase() : null);
/**
 * The account's payment country — one source of truth for currency:
 * verified ID, then the payout profile (location / SIM), then the profile,
 * then what the app sent. Exported for commerce pricing.
 */
async function countryOf(uid, hint) {
    var _a, _b, _c, _d, _e;
    const [pp, kyc, user] = await Promise.all([
        db().doc(`payout_profiles/${uid}`).get(), db().doc(`kyc/${uid}`).get(), db().doc(`users/${uid}`).get(),
    ]);
    return (_e = (_d = (_c = (_b = (_a = cc(kyc.get('status') === 'verified' ? kyc.get('country') : null)) !== null && _a !== void 0 ? _a : cc(pp.get('detectedCountry'))) !== null && _b !== void 0 ? _b : cc(user.get('country'))) !== null && _c !== void 0 ? _c : cc(user.get('countryCode'))) !== null && _d !== void 0 ? _d : cc(hint)) !== null && _e !== void 0 ? _e : 'KE';
}
/** Public view of an intent for the app. */
function view(id, d) {
    var _a, _b;
    return {
        intentId: id,
        status: d.status,
        purpose: d.purpose,
        refId: d.refId,
        amountMinor: d.amountMinor,
        amount: (0, provider_1.toMajor)(Number(d.amountMinor), String(d.currency)),
        currency: d.currency,
        method: d.method,
        redirectUrl: (_a = d.redirectUrl) !== null && _a !== void 0 ? _a : null,
        failureReason: (_b = d.failureReason) !== null && _b !== void 0 ? _b : null,
        sandbox: d.sandbox === true,
    };
}
// ───────────────────────────── Methods ─────────────────────────────
exports.payMethods = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d, _e;
    const uid = me(req);
    const country = await countryOf(uid, (_a = req.data) === null || _a === void 0 ? void 0 : _a.country);
    const rt = await (0, payConfig_1.payRuntime)();
    const bal = rt.cfg.wallet ? (await (0, ledger_1.balanceRef)(uid).get()).data() : undefined;
    const currency = (0, payLogic_1.currencyFor)(country);
    return {
        country,
        countryName: (_d = (_b = payoutLogic_1.AFRICA[country]) === null || _b === void 0 ? void 0 : _b.name) !== null && _d !== void 0 ? _d : null,
        currency,
        dial: (_e = (_c = payoutLogic_1.AFRICA[country]) === null || _c === void 0 ? void 0 : _c.dial) !== null && _e !== void 0 ? _e : null,
        methods: (0, payLogic_1.methodsFor)(country, rt.cfg),
        sandbox: rt.cfg.sandbox,
        walletEnabled: rt.cfg.wallet,
        balanceMinor: rt.cfg.wallet ? (0, ledger_1.bucketOf)(bal, currency, 'available') : null,
        live: rt.cfg.mpesa || rt.cfg.momo || rt.cfg.flutterwave || rt.cfg.paystack,
    };
});
// ───────────────────────────── Create ─────────────────────────────
exports.payCreate = (0, https_1.onCall)({ timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    var _j, _k, _l, _m, _o, _p, _q, _r, _s, _t;
    const uid = me(req);
    const purpose = String((_j = (_a = req.data) === null || _a === void 0 ? void 0 : _a.purpose) !== null && _j !== void 0 ? _j : '');
    if (purpose !== 'order' && purpose !== 'topup' && purpose !== 'merchant')
        throw new https_1.HttpsError('invalid-argument', 'Unknown payment.');
    const rt = await (0, payConfig_1.payRuntime)();
    // Scan to pay: the merchant's code decides who is paid, the currency and (if set) the amount.
    let qr;
    let qrCode = '';
    if (purpose === 'merchant') {
        if (!rt.cfg.wallet)
            throw new https_1.HttpsError('failed-precondition', 'Scan to pay opens soon in your country.');
        qrCode = (_l = (0, payLogic_1.qrCodeFrom)(String((_k = (_b = req.data) === null || _b === void 0 ? void 0 : _b.refId) !== null && _k !== void 0 ? _k : ''))) !== null && _l !== void 0 ? _l : '';
        qr = qrCode ? (await db().doc(`pay_qr/${qrCode}`).get()).data() : undefined;
        const problem = (0, payLogic_1.qrProblem)(qr);
        if (problem)
            throw new https_1.HttpsError('failed-precondition', problem);
        if (qr.merchantUid === uid)
            throw new https_1.HttpsError('failed-precondition', 'This is your own code.');
    }
    // A merchant code is paid with the merchant country's methods (you pay where you are).
    const country = purpose === 'merchant' ? String(qr.country) : await countryOf(uid, (_c = req.data) === null || _c === void 0 ? void 0 : _c.country);
    const method = (0, payLogic_1.methodsFor)(country, rt.cfg).find((m) => { var _a; var _b; return m.id === String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.methodId) !== null && _b !== void 0 ? _b : ''); });
    if (!method)
        throw new https_1.HttpsError('failed-precondition', 'This way to pay isn’t open in your country yet.');
    // Too many attempts in a short time is either a bug or abuse.
    const recent = await db().collection('pay_intents').where('uid', '==', uid).where('createdAt', '>', firestore_1.Timestamp.fromMillis(Date.now() - 10 * 60000)).get();
    if (recent.size >= 10)
        throw new https_1.HttpsError('resource-exhausted', 'Too many payment attempts. Wait a few minutes and try again.');
    let amountMinor;
    let currency;
    let refId;
    let narration;
    if (purpose === 'order') {
        refId = String((_m = (_d = req.data) === null || _d === void 0 ? void 0 : _d.refId) !== null && _m !== void 0 ? _m : '');
        if (!refId || refId.includes('/'))
            throw new https_1.HttpsError('invalid-argument', 'Missing order.');
        const o = (await db().doc(`orders/${refId}`).get()).data();
        if (!o || o.buyerId !== uid)
            throw new https_1.HttpsError('not-found', 'Order not found.');
        if (!['awaiting_payment', 'payment_failed'].includes(o.status))
            throw new https_1.HttpsError('failed-precondition', 'This order is already paid or closed.');
        // A second tap while a prompt is still open returns the same payment.
        if (o.payIntentId) {
            const open = (await intentRef(o.payIntentId).get()).data();
            if (open && (0, payLogic_1.isOpenIntent)(open.status) && ((_e = open.method) === null || _e === void 0 ? void 0 : _e.id) === method.id)
                return view(o.payIntentId, open);
        }
        const m = (0, orderEscrow_1.orderMinor)(o);
        amountMinor = m.total;
        currency = (0, orderEscrow_1.orderCurrency)(o);
        narration = `Oneova order ${refId.slice(0, 6)}`;
    }
    else if (purpose === 'merchant') {
        currency = String(qr.currency);
        if (typeof qr.amountMinor === 'number')
            amountMinor = qr.amountMinor;
        else {
            const amount = Number((_f = req.data) === null || _f === void 0 ? void 0 : _f.amount);
            amountMinor = Number.isFinite(amount) ? (0, provider_1.toMinor)(amount, currency) : 0;
            if (amountMinor < (0, provider_1.toMinor)(1, currency) || amountMinor > (0, provider_1.toMinor)(1000000, currency))
                throw new https_1.HttpsError('invalid-argument', 'Enter the amount to pay.');
        }
        refId = qrCode;
        narration = `Oneova Pay ${String((_o = qr.label) !== null && _o !== void 0 ? _o : 'merchant').slice(0, 20)}`;
    }
    else {
        if (!rt.cfg.wallet)
            throw new https_1.HttpsError('failed-precondition', 'Oneova balance top-ups open soon.');
        if (method.rail === 'balance')
            throw new https_1.HttpsError('invalid-argument', 'Choose how to top up.');
        currency = (0, payLogic_1.currencyFor)(country);
        const amount = Number((_g = req.data) === null || _g === void 0 ? void 0 : _g.amount);
        amountMinor = Number.isFinite(amount) ? (0, provider_1.toMinor)(amount, currency) : 0;
        const minMinor = (0, provider_1.toMinor)(1, currency);
        if (amountMinor < minMinor || amountMinor > (0, provider_1.toMinor)(1000000, currency))
            throw new https_1.HttpsError('invalid-argument', 'Enter an amount to add.');
        refId = uid;
        narration = 'Oneova top-up';
    }
    if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0)
        throw new https_1.HttpsError('failed-precondition', 'Nothing to pay.');
    let msisdn = null;
    if (method.needsPhone) {
        msisdn = (0, payoutLogic_1.normalizeMsisdn)(String((_p = (_h = req.data) === null || _h === void 0 ? void 0 : _h.msisdn) !== null && _p !== void 0 ? _p : ''), country);
        if (!msisdn)
            throw new https_1.HttpsError('invalid-argument', `Enter the phone number for ${method.label}.`);
    }
    const id = crypto.randomUUID();
    const ref = intentRef(id);
    const base = Object.assign(Object.assign({ uid, purpose, refId, amountMinor, currency, country }, (purpose === 'merchant' ? { merchantUid: String(qr.merchantUid) } : {})), { method: { id: method.id, rail: method.rail, provider: method.provider, kind: method.kind, label: method.label, network: (_q = method.network) !== null && _q !== void 0 ? _q : null }, provider: method.provider, msisdnMasked: msisdn ? (0, payLogic_1.maskMsisdn)(msisdn) : null, sandbox: method.sandbox === true, status: 'created', checks: 0, createdAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(), expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + (0, payLogic_1.intentTtlMs)(method.kind)) });
    await ref.set(base);
    if (purpose === 'order')
        await db().doc(`orders/${refId}`).update({ payIntentId: id, status: 'awaiting_payment', updatedAt: firestore_1.FieldValue.serverTimestamp() });
    // Oneova balance: settles at once, in one transaction.
    if (method.rail === 'balance') {
        if (purpose === 'merchant')
            await payMerchantFromBalance(id);
        else
            await payFromBalance(id);
        return view(id, (await ref.get()).data());
    }
    const collector = rt.collectors[method.provider];
    if (!collector || !collector.supports(country, method.rail, currency, method.network)) {
        await ref.update({ status: 'failed', failureReason: `${method.label} can’t take ${currency} payments.`, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        throw new https_1.HttpsError('failed-precondition', `${method.label} can’t take ${currency} payments.`);
    }
    const user = await (0, auth_1.getAuth)().getUser(uid).catch(() => null);
    const outcome = await collector.collect({
        reference: id, country, rail: method.rail, currency, amountMinor,
        msisdn: msisdn !== null && msisdn !== void 0 ? msisdn : undefined, network: method.network,
        email: (_r = user === null || user === void 0 ? void 0 : user.email) !== null && _r !== void 0 ? _r : `pay+${uid}@oneova.app`, payerName: (_s = user === null || user === void 0 ? void 0 : user.displayName) !== null && _s !== void 0 ? _s : undefined,
        returnUrl: `${(0, payConfig_1.returnUrl)()}?intent=${id}`, narration,
    });
    if (outcome.kind === 'accepted') {
        await ref.update({
            status: 'pending_payer', providerRef: outcome.providerRef || null, redirectUrl: (_t = outcome.redirectUrl) !== null && _t !== void 0 ? _t : null,
            sentAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    else if (outcome.kind === 'rejected') {
        await ref.update({ status: 'failed', failureReason: outcome.reason.slice(0, 200), updatedAt: firestore_1.FieldValue.serverTimestamp() });
        if (purpose === 'order')
            await db().doc(`orders/${refId}`).update({ status: 'payment_failed', updatedAt: firestore_1.FieldValue.serverTimestamp() });
    }
    else {
        // We can't tell if the prompt went out. Keep it open; the status check decides.
        logger.warn('pay-in outcome unknown', id, outcome.reason);
        await ref.update({ status: 'pending_payer', lastCheckNote: outcome.reason.slice(0, 200), sentAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    }
    return view(id, (await ref.get()).data());
});
/**
 * Credits a merchant for a confirmed scan-to-pay intent, inside the caller's
 * transaction ([qrSnap] read before any write): net to the merchant's balance,
 * the merchant fee to the platform, the code marked paid (one-time codes).
 */
function creditMerchant(tx, id, i, from, qrSnap, extra) {
    const fee = (0, payLogic_1.merchantFee)(Number(i.amountMinor));
    (0, ledger_1.writeLedger)(tx, `payin_${id}`, false, 'merchant_payin', (0, payLogic_1.merchantLines)(from, String(i.merchantUid), i.currency, Number(i.amountMinor), fee), Object.assign({ intentId: id, code: i.refId, merchantUid: i.merchantUid, fee }, extra));
    if (qrSnap.exists) {
        tx.update(qrSnap.ref, Object.assign(Object.assign({ paidCount: firestore_1.FieldValue.increment(1), receivedMinor: firestore_1.FieldValue.increment(Number(i.amountMinor) - fee) }, (qrSnap.get('oneTime') === true ? { paid: true, paidBy: i.uid, paidIntentId: id } : {})), { lastPaidAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() }));
    }
    const money = `${i.currency} ${(0, provider_1.toMajor)(Number(i.amountMinor) - fee, i.currency).toLocaleString('en-US')}`;
    tx.set(db().collection('notifications').doc(`merchant_paid_${id}`), {
        userId: i.merchantUid, recipientId: i.merchantUid, actorId: i.uid, category: 'system', priority: 'high', type: 'payment',
        title: 'Payment received', body: `${money} is in your Oneova balance.`, deepLink: '/wallet', isRead: false,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
}
/** Scan to pay from the payer's Oneova balance: settles at once. */
async function payMerchantFromBalance(id) {
    const ref = intentRef(id);
    await db().runTransaction(async (tx) => {
        const i = (await tx.get(ref)).data();
        if (!i || i.purpose !== 'merchant' || !(0, payLogic_1.isOpenIntent)(i.status))
            return;
        const [bal, posted, qrSnap] = await Promise.all([tx.get((0, ledger_1.balanceRef)(i.uid)), tx.get((0, ledger_1.ledgerRef)(`payin_${id}`)), tx.get(db().doc(`pay_qr/${i.refId}`))]);
        if (posted.exists)
            return;
        const problem = (0, payLogic_1.qrProblem)(qrSnap.data());
        if (problem) {
            tx.update(ref, { status: 'failed', failureReason: problem, updatedAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        if ((0, ledger_1.bucketOf)(bal.data(), i.currency, 'available') < i.amountMinor) {
            tx.update(ref, { status: 'failed', failureReason: 'Not enough in your Oneova balance.', updatedAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        creditMerchant(tx, id, i, `user:${i.uid}`, qrSnap, { provider: 'oneova' });
        tx.update(ref, { status: 'succeeded', paidAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
}
/** Pays an intent from the payer's Oneova balance (orders only). */
async function payFromBalance(id) {
    const ref = intentRef(id);
    await db().runTransaction(async (tx) => {
        const i = (await tx.get(ref)).data();
        if (!i || i.purpose !== 'order' || !(0, payLogic_1.isOpenIntent)(i.status))
            return;
        const orderRef = db().doc(`orders/${i.refId}`);
        const [o, bal, posted] = await Promise.all([tx.get(orderRef), tx.get((0, ledger_1.balanceRef)(i.uid)), tx.get((0, ledger_1.ledgerRef)(`payin_${id}`))]);
        const order = o.data();
        const product = order ? (await tx.get(db().doc(`products/${order.productId}`))).data() : undefined;
        if (!order || !['awaiting_payment', 'payment_failed'].includes(order.status)) {
            tx.update(ref, { status: 'failed', failureReason: 'This order is closed.', updatedAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        if ((0, ledger_1.bucketOf)(bal.data(), i.currency, 'available') < i.amountMinor) {
            tx.update(ref, { status: 'failed', failureReason: 'Not enough in your Oneova balance.', updatedAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        (0, ledger_1.writeLedger)(tx, `payin_${id}`, posted.exists, 'order_payin', [
            { account: `user:${i.uid}`, currency: i.currency, amountMinor: -i.amountMinor, bucket: 'available' },
            { account: `escrow:${i.refId}`, currency: i.currency, amountMinor: i.amountMinor },
        ], { intentId: id, orderId: i.refId, provider: 'oneova' });
        (0, orderEscrow_1.applyOrderPaid)(tx, i.refId, order, product, id);
        tx.update(ref, { status: 'succeeded', paidAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
}
// ───────────────────────────── Finishing ─────────────────────────────
/** Applies a confirmed pay-in once: ledger + the purpose's effect. */
async function applySuccess(id, check) {
    const ref = intentRef(id);
    await db().runTransaction(async (tx) => {
        var _a, _b, _c, _d;
        const snap = await tx.get(ref);
        const i = snap.data();
        if (!i)
            return;
        const posted = await tx.get((0, ledger_1.ledgerRef)(`payin_${id}`));
        if (posted.exists || !(0, payLogic_1.canMoveIntent)(i.status, 'succeeded'))
            return;
        const orderRef = i.purpose === 'order' ? db().doc(`orders/${i.refId}`) : null;
        const order = orderRef ? (await tx.get(orderRef)).data() : undefined;
        const product = order ? (await tx.get(db().doc(`products/${order.productId}`))).data() : undefined;
        const qrSnap = i.purpose === 'merchant' ? await tx.get(db().doc(`pay_qr/${i.refId}`)) : null;
        // --- writes ---
        const clearing = `clearing:${i.provider}`;
        const mismatch = (check.amountMinor != null && check.amountMinor !== i.amountMinor)
            || (check.currency != null && check.currency !== '' && check.currency.toUpperCase() !== i.currency);
        if (mismatch) {
            logger.error('pay-in amount mismatch', id, check.amountMinor, check.currency, i.amountMinor, i.currency);
            tx.update(ref, {
                status: 'review', reviewReason: 'amount_mismatch', paidAmountMinor: (_a = check.amountMinor) !== null && _a !== void 0 ? _a : null, paidCurrency: (_b = check.currency) !== null && _b !== void 0 ? _b : null,
                providerRef: (_d = (_c = check.providerRef) !== null && _c !== void 0 ? _c : i.providerRef) !== null && _d !== void 0 ? _d : null, updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            if (orderRef)
                tx.update(orderRef, { status: 'payment_mismatch', updatedAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        const providerRef = check.providerRef || i.providerRef || null;
        if (i.purpose === 'order') {
            const payable = !!order && ['awaiting_payment', 'payment_failed'].includes(order.status) && (!order.payIntentId || order.payIntentId === id);
            if (!payable) {
                // Paid, but the order can't take it (closed, or paid by another attempt): hold it for a person to return.
                (0, ledger_1.writeLedger)(tx, `payin_${id}`, false, 'payin_unmatched', [
                    { account: clearing, currency: i.currency, amountMinor: -i.amountMinor },
                    { account: `suspense:${id}`, currency: i.currency, amountMinor: i.amountMinor },
                ], { intentId: id, provider: i.provider, sandbox: i.sandbox === true });
                tx.update(ref, { status: 'review', reviewReason: 'order_not_payable', providerRef, paidAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
                return;
            }
            (0, ledger_1.writeLedger)(tx, `payin_${id}`, false, 'order_payin', [
                { account: clearing, currency: i.currency, amountMinor: -i.amountMinor },
                { account: `escrow:${i.refId}`, currency: i.currency, amountMinor: i.amountMinor },
            ], { intentId: id, orderId: i.refId, provider: i.provider, sandbox: i.sandbox === true });
            (0, orderEscrow_1.applyOrderPaid)(tx, i.refId, order, product, id);
        }
        else if (i.purpose === 'merchant' && qrSnap) {
            // The money arrived, so the merchant is credited even if the code expired meanwhile.
            creditMerchant(tx, id, i, clearing, qrSnap, { provider: i.provider, sandbox: i.sandbox === true });
        }
        else {
            (0, ledger_1.writeLedger)(tx, `payin_${id}`, false, 'topup', [
                { account: clearing, currency: i.currency, amountMinor: -i.amountMinor },
                { account: `user:${i.uid}`, currency: i.currency, amountMinor: i.amountMinor, bucket: 'available' },
            ], { intentId: id, provider: i.provider, sandbox: i.sandbox === true });
            tx.set(db().collection('notifications').doc(`topup_${id}`), {
                userId: i.uid, recipientId: i.uid, category: 'system', priority: 'normal', type: 'payment',
                title: 'Money added', body: `${i.currency} ${(0, provider_1.toMajor)(i.amountMinor, i.currency).toLocaleString('en-US')} is in your Oneova balance.`,
                deepLink: '/wallet', isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        tx.update(ref, { status: 'succeeded', providerRef, paidAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
}
async function markFailed(id, reason) {
    await db().runTransaction(async (tx) => {
        const i = (await tx.get(intentRef(id))).data();
        if (!i || !(0, payLogic_1.canMoveIntent)(i.status, 'failed'))
            return;
        const orderRef = i.purpose === 'order' ? db().doc(`orders/${i.refId}`) : null;
        const order = orderRef ? (await tx.get(orderRef)).data() : undefined;
        tx.update(intentRef(id), { status: 'failed', failureReason: reason.slice(0, 200), updatedAt: firestore_1.FieldValue.serverTimestamp() });
        if (orderRef && (order === null || order === void 0 ? void 0 : order.status) === 'awaiting_payment' && order.payIntentId === id) {
            tx.update(orderRef, { status: 'payment_failed', updatedAt: firestore_1.FieldValue.serverTimestamp() });
        }
    });
}
/**
 * Asks the partner about one intent and applies the answer. Safe to call any
 * number of times (webhooks, the app, the reconcile job). Returns the status.
 */
async function refreshIntent(id) {
    var _a, _b;
    var _c, _d, _e, _f, _g;
    if (!UUID.test(id))
        return null;
    const ref = intentRef(id);
    const i = (await ref.get()).data();
    if (!i)
        return null;
    const lateWindow = ['expired', 'cancelled'].includes(i.status)
        && Date.now() - ((_c = (_a = i.updatedAt) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _c !== void 0 ? _c : 0) < 6 * 3600000;
    if (!(0, payLogic_1.isOpenIntent)(i.status) && !lateWindow)
        return i.status;
    if (i.provider === 'oneova')
        return i.status;
    const rt = await (0, payConfig_1.payRuntime)();
    const collector = rt.collectors[i.provider];
    if (!collector)
        return i.status; // keys missing right now; try later
    const check = await collector.check(id, (_d = i.providerRef) !== null && _d !== void 0 ? _d : undefined).catch((e) => { var _a; return ({ status: 'unknown', reason: String((_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e) }); });
    await ref.update({ checks: firestore_1.FieldValue.increment(1), lastCheckedAt: firestore_1.FieldValue.serverTimestamp(), lastCheckNote: check.status });
    if (check.status === 'paid') {
        await applySuccess(id, check);
    }
    else if (check.status === 'failed') {
        await markFailed(id, (_e = check.reason) !== null && _e !== void 0 ? _e : 'The payment was not completed.');
    }
    else if ((0, payLogic_1.isOpenIntent)(i.status) && i.expiresAt.toMillis() < Date.now()) {
        if (check.status === 'unknown') {
            // Can't tell: a person looks after a day; until then we keep asking.
            const age = Date.now() - ((_f = (_b = i.createdAt) === null || _b === void 0 ? void 0 : _b.toMillis()) !== null && _f !== void 0 ? _f : Date.now());
            if (age > 24 * 3600000)
                await ref.update({ status: 'review', reviewReason: 'status_unknown', updatedAt: firestore_1.FieldValue.serverTimestamp() });
        }
        else {
            await ref.update({ status: 'expired', updatedAt: firestore_1.FieldValue.serverTimestamp() });
            if (i.purpose === 'order') {
                await db().runTransaction(async (tx) => {
                    const oref = db().doc(`orders/${i.refId}`);
                    const o = (await tx.get(oref)).data();
                    if ((o === null || o === void 0 ? void 0 : o.status) === 'awaiting_payment' && o.payIntentId === id)
                        tx.update(oref, { status: 'payment_failed', updatedAt: firestore_1.FieldValue.serverTimestamp() });
                });
            }
        }
    }
    return (_g = (await ref.get()).get('status')) !== null && _g !== void 0 ? _g : null;
}
exports.payStatus = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c, _d;
    const uid = me(req);
    const id = String((_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.intentId) !== null && _c !== void 0 ? _c : '');
    if (!UUID.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Missing payment.');
    let d = (await intentRef(id).get()).data();
    if (!d || d.uid !== uid)
        throw new https_1.HttpsError('not-found', 'Payment not found.');
    const last = (_d = (_b = d.lastCheckedAt) === null || _b === void 0 ? void 0 : _b.toMillis()) !== null && _d !== void 0 ? _d : 0;
    if ((0, payLogic_1.isOpenIntent)(d.status) && Date.now() - last > 3000) {
        await refreshIntent(id);
        d = (await intentRef(id).get()).data();
    }
    return view(id, d);
});
exports.payCancel = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = me(req);
    const id = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.intentId) !== null && _b !== void 0 ? _b : '');
    if (!UUID.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Missing payment.');
    await db().runTransaction(async (tx) => {
        const d = (await tx.get(intentRef(id))).data();
        if (!d || d.uid !== uid)
            throw new https_1.HttpsError('not-found', 'Payment not found.');
        if ((0, payLogic_1.isOpenIntent)(d.status))
            tx.update(intentRef(id), { status: 'cancelled', updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
    return { ok: true };
});
// ───────────────────────────── Refunds ─────────────────────────────
/**
 * Gives a succeeded order pay-in back to the buyer:
 *   Oneova balance          → straight back to the balance
 *   partner with refunds    → the partner refunds the card / wallet
 *   otherwise               → the Oneova balance when the wallet is on,
 *                             else a person sends it back ('review').
 */
async function refundIntent(id, key) {
    var _a;
    if (!UUID.test(id))
        return 'none';
    const i = (await intentRef(id).get()).data();
    if (!i || i.status !== 'succeeded')
        return 'none';
    const rt = await (0, payConfig_1.payRuntime)();
    // Where the money sits now: the order's escrow, the merchant's balance, or the payer's own (top-up).
    const escrow = i.purpose === 'order' ? `escrow:${i.refId}` : i.purpose === 'merchant' ? `biz:${i.merchantUid}` : `user:${i.uid}`;
    const toBuyerBalance = async (via) => {
        await db().runTransaction(async (tx) => {
            const posted = await tx.get((0, ledger_1.ledgerRef)(`refund_${id}`));
            (0, ledger_1.writeLedger)(tx, `refund_${id}`, posted.exists, 'refund_to_balance', [
                { account: escrow, currency: i.currency, amountMinor: -i.amountMinor },
                { account: `user:${i.uid}`, currency: i.currency, amountMinor: i.amountMinor, bucket: 'available' },
            ], { intentId: id, key });
            tx.update(intentRef(id), { status: 'refunded', refundedTo: via, refundedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
        });
        return 'refunded';
    };
    if (i.provider === 'oneova')
        return notifyRefund(i, id, await toBuyerBalance('balance'));
    const collector = rt.collectors[i.provider];
    if (collector === null || collector === void 0 ? void 0 : collector.refund) {
        const r = await collector.refund(id, String((_a = i.providerRef) !== null && _a !== void 0 ? _a : ''), i.amountMinor, i.currency);
        if (r.kind === 'accepted') {
            await db().runTransaction(async (tx) => {
                const posted = await tx.get((0, ledger_1.ledgerRef)(`refund_${id}`));
                (0, ledger_1.writeLedger)(tx, `refund_${id}`, posted.exists, 'refund_to_payer', [
                    { account: escrow, currency: i.currency, amountMinor: -i.amountMinor },
                    { account: `clearing:${i.provider}`, currency: i.currency, amountMinor: i.amountMinor },
                ], { intentId: id, key, providerRef: r.providerRef });
                tx.update(intentRef(id), { status: 'refunded', refundedTo: 'payer', refundRef: r.providerRef, refundedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
            });
            return notifyRefund(i, id, 'refunded');
        }
        if (r.kind === 'unknown') {
            // It may have gone through: never send a second refund on a guess.
            await intentRef(id).update({ status: 'review', reviewReason: 'refund_unknown', updatedAt: firestore_1.FieldValue.serverTimestamp() });
            return 'review';
        }
    }
    if (rt.cfg.wallet)
        return notifyRefund(i, id, await toBuyerBalance('balance'));
    await intentRef(id).update({ status: 'review', reviewReason: 'refund_manual', updatedAt: firestore_1.FieldValue.serverTimestamp() });
    return notifyRefund(i, id, 'review');
}
/** Tells the payer their money is coming back (or is being sent back by our team). */
async function notifyRefund(i, id, r) {
    const money = `${i.currency} ${(0, provider_1.toMajor)(i.amountMinor, i.currency).toLocaleString('en-US')}`;
    await db().collection('notifications').doc(`refund_${id}`).set({
        userId: i.uid, recipientId: i.uid, category: 'system', priority: 'high', type: 'payment',
        title: r === 'refunded' ? 'Refund sent' : 'Refund on its way',
        body: r === 'refunded'
            ? `${money} is on its way back to you.`
            : `We’re sending ${money} back to you. It can take up to 2 working days.`,
        deepLink: '/wallet/payments', isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    }).catch(() => undefined);
    return r;
}
// ───────────────────────────── Reconcile & webhooks ─────────────────────────────
/** Intents still waiting on the payer, and recent late approvals. */
exports.payReconcileIntents = (0, scheduler_1.onSchedule)('every 5 minutes', async () => {
    var _a;
    const [open, late] = await Promise.all([
        db().collection('pay_intents').where('status', '==', 'pending_payer').limit(200).get(),
        db().collection('pay_intents').where('status', '==', 'expired').where('updatedAt', '>', firestore_1.Timestamp.fromMillis(Date.now() - 6 * 3600000)).limit(100).get(),
    ]);
    const due = [...open.docs, ...late.docs].filter((d) => { var _a; var _b; return Date.now() - ((_b = (_a = d.get('lastCheckedAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : 0) > 60000; }).slice(0, 80);
    for (const d of due) {
        try {
            await refreshIntent(d.id);
        }
        catch (e) {
            logger.error('pay reconcile failed', d.id, (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e);
        }
    }
});
/** M-Pesa STK callback: only a hint; the status comes from the STK query. */
exports.payWebhookMpesa = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c;
    var _d, _e;
    try {
        const checkout = String((_d = (_c = (_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.Body) === null || _b === void 0 ? void 0 : _b.stkCallback) === null || _c === void 0 ? void 0 : _c.CheckoutRequestID) !== null && _d !== void 0 ? _d : '');
        if (checkout) {
            const q = await db().collection('pay_intents').where('providerRef', '==', checkout).limit(1).get();
            if (!q.empty)
                await refreshIntent(q.docs[0].id);
        }
    }
    catch (e) {
        logger.error('mpesa callback failed', (_e = e === null || e === void 0 ? void 0 : e.message) !== null && _e !== void 0 ? _e : e);
    }
    res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
});
/** MTN MoMo callback: only a hint; the status comes from the API. */
exports.payWebhookMomo = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b;
    var _c, _d, _e;
    try {
        const ref = String((_d = (_c = (_a = req.body) === null || _a === void 0 ? void 0 : _a.externalId) !== null && _c !== void 0 ? _c : (_b = req.body) === null || _b === void 0 ? void 0 : _b.referenceId) !== null && _d !== void 0 ? _d : '');
        if (UUID.test(ref))
            await refreshIntent(ref);
    }
    catch (e) {
        logger.error('momo callback failed', (_e = e === null || e === void 0 ? void 0 : e.message) !== null && _e !== void 0 ? _e : e);
    }
    res.status(200).send('ok');
});
const isIntentReference = (ref) => UUID.test(ref);
exports.isIntentReference = isIntentReference;
const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
/**
 * Where a partner's secure page sends the payer back. Checks the payment with
 * the partner, shows the result and offers a way back into the app (where the
 * pay sheet already updates by itself).
 */
exports.payReturn = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c, _d, _e;
    const id = String((_d = (_c = (_b = (_a = req.query.intent) !== null && _a !== void 0 ? _a : req.query.tx_ref) !== null && _b !== void 0 ? _b : req.query.reference) !== null && _c !== void 0 ? _c : req.query.trxref) !== null && _d !== void 0 ? _d : '');
    let status = null;
    let amount = '';
    try {
        if (UUID.test(id)) {
            status = await refreshIntent(id);
            const d = (await intentRef(id).get()).data();
            if (d)
                amount = `${d.currency} ${(0, provider_1.toMajor)(Number(d.amountMinor), String(d.currency)).toLocaleString('en-US')}`;
        }
    }
    catch (e) {
        logger.warn('pay return check failed', id, (_e = e === null || e === void 0 ? void 0 : e.message) !== null && _e !== void 0 ? _e : e);
    }
    const done = status === 'succeeded';
    const waiting = status === 'created' || status === 'pending_payer' || status === null && UUID.test(id);
    const title = done ? 'Payment received' : waiting ? 'Finishing your payment…' : 'Payment didn’t go through';
    const body = done
        ? `${amount ? `${esc(amount)} is paid. ` : ''}You can go back to Oneova now.`
        : waiting
            ? 'This page updates by itself in a few seconds.'
            : 'Nothing was charged. Go back to Oneova to try again.';
    const appLink = 'intent://app/wallet/payments#Intent;scheme=oneova;package=com.oneova.app;end';
    res.set('Cache-Control', 'no-store');
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.status(200).send(`<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
${waiting ? '<meta http-equiv="refresh" content="4">' : ''}
<title>Oneova Pay</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;
font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;color:#fff;
background:radial-gradient(120% 80% at 50% 0%,#0E1630 0%,#07090F 70%)}
.card{width:100%;max-width:380px;text-align:center;padding:32px 24px;border-radius:24px;
background:rgba(255,255,255,.05);border:1px solid rgba(45,123,255,.25)}
.dot{width:72px;height:72px;margin:0 auto 18px;border-radius:50%;display:flex;align-items:center;justify-content:center;
font-size:34px;background:linear-gradient(135deg,#0C4FA8,#FF2D87)}
h1{font-size:22px;margin:0 0 8px}p{margin:0 0 22px;color:rgba(255,255,255,.7)}
a.btn{display:block;padding:15px;border-radius:999px;color:#fff;text-decoration:none;font-weight:800;
background:linear-gradient(90deg,#0C4FA8,#FF2D87)}
small{display:block;margin-top:16px;color:rgba(255,255,255,.4)}
</style></head><body><main class="card">
<div class="dot">${done ? '✓' : waiting ? '…' : '!'}</div>
<h1>${title}</h1><p>${body}</p>
<a class="btn" href="${appLink}">Back to Oneova</a>
<small>Oneova Pay · protected payment</small>
</main></body></html>`);
});
//# sourceMappingURL=intents.js.map