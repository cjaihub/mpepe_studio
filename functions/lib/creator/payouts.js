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
exports.paystackWebhook = exports.flutterwaveWebhook = exports.reviewWithdrawal = exports.cancelWithdrawal = exports.requestWithdrawal = exports.deletePayoutMethod = exports.savePayoutMethod = exports.payoutBanks = exports.payoutOptions = exports.walletSync = void 0;
exports.settleWithdrawal = settle;
/**
 * Creator withdrawals: Diamonds (gift earnings) → mobile money, bank or Stripe.
 *
 *   app → walletSync          releases Diamonds past the hold into availableCoins
 *   app → payoutOptions       country (location → SIM → locale), rails, fees, FX
 *   app → payoutBanks         bank list for the country
 *   app → savePayoutMethod    KYC must be verified; the name on the ID is the payee
 *   app → requestWithdrawal   idempotent; fraud checks; locks Diamonds; sends it
 *   app → cancelWithdrawal    while it is still pending
 *   admin → reviewWithdrawal  approve / reject one held for review
 *   Flutterwave / Paystack → webhooks mark it paid or failed (failed refunds)
 *
 * Purchased coins (`balanceCoins`) are never touched here.
 *
 * Secrets (Secret Manager, read at run time; a missing one just turns its rail off):
 *   FLUTTERWAVE_SECRET_KEY, FLUTTERWAVE_WEBHOOK_HASH, PAYSTACK_SECRET_KEY,
 *   STRIPE_SECRET_KEY, GOOGLE_MAPS_SERVER_KEY (reverse geocoding)
 */
const crypto = __importStar(require("crypto"));
const stripe_1 = __importDefault(require("stripe"));
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const auth_1 = require("firebase-admin/auth");
const optionalSecrets_1 = require("../optionalSecrets");
const payoutLogic_1 = require("./payoutLogic");
const db = () => (0, firestore_1.getFirestore)();
const FLW = 'https://api.flutterwave.com/v3';
const PAYSTACK = 'https://api.paystack.co';
const EARNING_TYPES = new Set(['live_gift_received', 'user_gift_received']);
function me(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
const cc = (v) => (typeof v === 'string' && /^[A-Za-z]{2}$/.test(v) ? v.toUpperCase() : null);
async function configured() {
    const [flw, ps, st] = await Promise.all([
        (0, optionalSecrets_1.optionalSecret)('FLUTTERWAVE_SECRET_KEY'), (0, optionalSecrets_1.optionalSecret)('PAYSTACK_SECRET_KEY'), (0, optionalSecrets_1.optionalSecret)('STRIPE_SECRET_KEY'),
    ]);
    return { flutterwave: !!flw, paystack: !!ps, stripe: !!st, keys: { flw, ps, st } };
}
// ───────────────────────────── FX ─────────────────────────────
/** Units of [currency] per 1 USD, cached 6 h in `fx_rates/USD`. */
async function usdRate(currency) {
    var _a;
    if (currency === 'USD')
        return 1;
    const ref = db().doc('fx_rates/USD');
    const snap = await ref.get();
    const fresh = snap.exists && Date.now() - snap.get('fetchedAt').toMillis() < 6 * 3600000;
    let rates = snap.get('rates');
    if (!fresh) {
        try {
            const res = await fetch('https://open.er-api.com/v6/latest/USD').then((r) => r.json());
            if ((res === null || res === void 0 ? void 0 : res.result) === 'success' && res.rates) {
                rates = res.rates;
                await ref.set({ rates, fetchedAt: firestore_1.FieldValue.serverTimestamp(), source: 'open.er-api.com' });
            }
        }
        catch (e) {
            logger.warn('fx fetch failed', (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e);
        }
    }
    const r = rates === null || rates === void 0 ? void 0 : rates[currency];
    if (!r || !Number.isFinite(r))
        throw new https_1.HttpsError('unavailable', 'Exchange rates are not available right now. Try again in a minute.');
    return r;
}
// ───────────────────────────── Earnings release ─────────────────────────────
async function releaseMatured(uid) {
    const cutoff = Date.now() - payoutLogic_1.HOLD_DAYS * 86400000;
    const wallet = db().doc(`wallets/${uid}`);
    const pending = await wallet.collection('ledger').where('status', '==', 'pending').limit(400).get();
    const due = pending.docs.filter((d) => { var _a; var _b; return EARNING_TYPES.has(d.get('type')) && ((_b = (_a = d.get('createdAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : Infinity) <= cutoff; }).slice(0, 200);
    if (!due.length)
        return 0;
    return db().runTransaction(async (tx) => {
        var _a;
        const fresh = await Promise.all(due.map((d) => tx.get(d.ref)));
        let sum = 0;
        for (const d of fresh) {
            if (d.get('status') !== 'pending')
                continue;
            sum += Math.max(0, Number((_a = d.get('amount')) !== null && _a !== void 0 ? _a : 0));
            tx.update(d.ref, { status: 'available', releasedAt: firestore_1.FieldValue.serverTimestamp() });
        }
        if (sum > 0) {
            tx.set(wallet, {
                pendingCoins: firestore_1.FieldValue.increment(-sum), availableCoins: firestore_1.FieldValue.increment(sum),
                lifetimeEarnedCoins: firestore_1.FieldValue.increment(sum), updatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        return sum;
    });
}
/** Releases matured earnings and returns the wallet in Diamonds and USD. */
exports.walletSync = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = me(req);
    const released = await releaseMatured(uid);
    const w = (_a = (await db().doc(`wallets/${uid}`).get()).data()) !== null && _a !== void 0 ? _a : {};
    const n = (k) => { var _a; return Math.max(0, Number((_a = w[k]) !== null && _a !== void 0 ? _a : 0)); };
    return {
        released,
        coins: n('balanceCoins'),
        pendingDiamonds: n('pendingCoins'),
        availableDiamonds: n('availableCoins'),
        lockedDiamonds: n('lockedCoins'),
        withdrawnDiamonds: n('withdrawnCoins'),
        diamondUsd: payoutLogic_1.DIAMOND_USD,
        holdDays: payoutLogic_1.HOLD_DAYS,
        minUsd: payoutLogic_1.MIN_WITHDRAW_USD,
    };
});
// ───────────────────────────── Country & rails ─────────────────────────────
async function reverseGeocode(lat, lng) {
    var _a, _b, _c;
    const key = await (0, optionalSecrets_1.optionalSecret)('GOOGLE_MAPS_SERVER_KEY');
    if (!key)
        return null;
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('latlng', `${lat},${lng}`);
    url.searchParams.set('result_type', 'country');
    url.searchParams.set('key', key);
    const res = await fetch(url).then((r) => r.json()).catch(() => null);
    const comp = (_c = (_b = (_a = res === null || res === void 0 ? void 0 : res.results) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.address_components) === null || _c === void 0 ? void 0 : _c.find((c) => { var _a; return (_a = c.types) === null || _a === void 0 ? void 0 : _a.includes('country'); });
    return cc(comp === null || comp === void 0 ? void 0 : comp.short_name);
}
async function touchDevice(uid, deviceId) {
    if (typeof deviceId !== 'string' || deviceId.length < 6 || deviceId.length > 200)
        return null;
    // Top-level and server-only, so nobody can backdate their own device.
    const ref = db().doc(`payout_devices/${uid}_${crypto.createHash('sha256').update(deviceId).digest('hex').slice(0, 32)}`);
    const snap = await ref.get();
    if (!snap.exists) {
        await ref.set({ firstSeenAt: firestore_1.FieldValue.serverTimestamp(), lastSeenAt: firestore_1.FieldValue.serverTimestamp() });
        return 0;
    }
    await ref.update({ lastSeenAt: firestore_1.FieldValue.serverTimestamp() });
    return (Date.now() - snap.get('firstSeenAt').toMillis()) / 3600000;
}
exports.payoutOptions = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h, _j, _k;
    const uid = me(req);
    const lat = Number((_a = req.data) === null || _a === void 0 ? void 0 : _a.lat), lng = Number((_b = req.data) === null || _b === void 0 ? void 0 : _b.lng);
    let country = null;
    let source = 'none';
    if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
        country = await reverseGeocode(lat, lng);
        if (country)
            source = 'location';
    }
    for (const [k, s] of [['simCountry', 'sim'], ['phoneCountry', 'phone'], ['localeCountry', 'locale']]) {
        if (!country && cc((_c = req.data) === null || _c === void 0 ? void 0 : _c[k])) {
            country = cc(req.data[k]);
            source = s;
        }
    }
    const kyc = (_e = (await db().doc(`kyc/${uid}`).get()).data()) !== null && _e !== void 0 ? _e : {};
    if (!country && cc(kyc.country)) {
        country = cc(kyc.country);
        source = 'id';
    }
    if (!country)
        throw new https_1.HttpsError('failed-precondition', 'We could not tell which country you are in. Turn on location and try again.');
    await Promise.all([
        db().doc(`payout_profiles/${uid}`).set(Object.assign(Object.assign({ uid, detectedCountry: country, detectedSource: source }, (source === 'location' ? { locationCountry: country, locationAt: firestore_1.FieldValue.serverTimestamp() } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true }),
        touchDevice(uid, (_d = req.data) === null || _d === void 0 ? void 0 : _d.deviceId),
    ]);
    const cfg = await configured();
    const a = payoutLogic_1.AFRICA[country];
    const currency = (_f = a === null || a === void 0 ? void 0 : a.currency) !== null && _f !== void 0 ? _f : 'USD';
    const rate = await usdRate(currency).catch(() => null);
    const stripeAcct = (_g = (await db().doc(`payout_accounts/${uid}`).get()).data()) !== null && _g !== void 0 ? _g : {};
    return {
        country,
        countryName: (_h = a === null || a === void 0 ? void 0 : a.name) !== null && _h !== void 0 ? _h : null,
        source,
        africa: (0, payoutLogic_1.isAfrica)(country),
        currency,
        usdRate: rate,
        rails: (0, payoutLogic_1.railsFor)(country, cfg),
        minUsd: payoutLogic_1.MIN_WITHDRAW_USD,
        maxUsd: payoutLogic_1.MAX_WITHDRAW_USD,
        diamondUsd: payoutLogic_1.DIAMOND_USD,
        fees: { mobile_money: '1.5% (min $0.20)', bank: '1% (min $0.50)', stripe: '$0.25 + 0.25%' },
        kycStatus: (_j = kyc.status) !== null && _j !== void 0 ? _j : 'none',
        kycCountry: (_k = kyc.country) !== null && _k !== void 0 ? _k : null,
        stripe: { connected: !!stripeAcct.stripeAccountId, payoutsEnabled: stripeAcct.payoutsEnabled === true },
    };
});
exports.payoutBanks = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c, _d, _e, _f;
    me(req);
    const country = cc((_a = req.data) === null || _a === void 0 ? void 0 : _a.country);
    if (!country || !((_b = payoutLogic_1.AFRICA[country]) === null || _b === void 0 ? void 0 : _b.bank))
        return { banks: [] };
    const cfg = await configured();
    try {
        if (cfg.keys.flw) {
            const res = await fetch(`${FLW}/banks/${country}`, { headers: { Authorization: `Bearer ${cfg.keys.flw}` } }).then((r) => r.json());
            return { banks: ((_c = res === null || res === void 0 ? void 0 : res.data) !== null && _c !== void 0 ? _c : []).map((b) => ({ code: String(b.code), name: String(b.name) })) };
        }
        if (cfg.keys.ps) {
            const names = { NG: 'nigeria', GH: 'ghana', KE: 'kenya', ZA: 'south africa' };
            const res = await fetch(`${PAYSTACK}/bank?country=${encodeURIComponent((_d = names[country]) !== null && _d !== void 0 ? _d : '')}&perPage=200`, { headers: { Authorization: `Bearer ${cfg.keys.ps}` } }).then((r) => r.json());
            return { banks: ((_e = res === null || res === void 0 ? void 0 : res.data) !== null && _e !== void 0 ? _e : []).map((b) => ({ code: String(b.code), name: String(b.name) })) };
        }
    }
    catch (e) {
        logger.warn('bank list failed', country, (_f = e === null || e === void 0 ? void 0 : e.message) !== null && _f !== void 0 ? _f : e);
    }
    return { banks: [] };
});
// ───────────────────────────── Payout methods ─────────────────────────────
async function verifiedKyc(uid) {
    const k = (await db().doc(`kyc/${uid}`).get()).data();
    if (!k || k.status !== 'verified')
        throw new https_1.HttpsError('failed-precondition', 'Verify your identity first. It keeps your money safe.');
    return k;
}
exports.savePayoutMethod = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e, _f;
    var _g, _h, _j, _k, _l, _m, _o, _p;
    const uid = me(req);
    const kyc = await verifiedKyc(uid);
    const rail = String((_g = (_a = req.data) === null || _a === void 0 ? void 0 : _a.rail) !== null && _g !== void 0 ? _g : '');
    const country = cc((_b = req.data) === null || _b === void 0 ? void 0 : _b.country);
    if (!country || !['mobile_money', 'bank', 'stripe'].includes(rail))
        throw new https_1.HttpsError('invalid-argument', 'Choose how you want to be paid.');
    const cfg = await configured();
    const option = (0, payoutLogic_1.railsFor)(country, cfg).find((o) => o.rail === rail);
    if (!option)
        throw new https_1.HttpsError('failed-precondition', 'This payout method is not open in your country yet.');
    const holder = String((_h = kyc.verifiedName) !== null && _h !== void 0 ? _h : '').trim();
    const a = payoutLogic_1.AFRICA[country];
    const pub = {
        rail, provider: option.provider, country, currency: (_j = a === null || a === void 0 ? void 0 : a.currency) !== null && _j !== void 0 ? _j : 'USD', holderName: holder,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    };
    const secret = { uid };
    if (rail === 'stripe') {
        const acct = (await db().doc(`payout_accounts/${uid}`).get()).data();
        if (!(acct === null || acct === void 0 ? void 0 : acct.stripeAccountId) || acct.payoutsEnabled !== true) {
            throw new https_1.HttpsError('failed-precondition', 'Finish connecting your bank with Stripe first.');
        }
        Object.assign(pub, { label: 'Stripe payouts', last4: String(acct.stripeAccountId).slice(-4), currency: 'USD' });
        secret.stripeAccountId = acct.stripeAccountId;
    }
    else if (rail === 'mobile_money') {
        const net = a.networks.find((n) => { var _a; return n.id === ((_a = req.data) === null || _a === void 0 ? void 0 : _a.network); });
        const msisdn = (0, payoutLogic_1.normalizeMsisdn)(String((_k = (_c = req.data) === null || _c === void 0 ? void 0 : _c.msisdn) !== null && _k !== void 0 ? _k : ''), country);
        if (!net)
            throw new https_1.HttpsError('invalid-argument', 'Pick your mobile money network.');
        if (!msisdn)
            throw new https_1.HttpsError('invalid-argument', `Enter a valid ${a.name} phone number.`);
        Object.assign(pub, { network: net.id, label: net.label, last4: msisdn.slice(-4) });
        Object.assign(secret, { msisdn, flwBank: net.flw, paystackBank: (_l = net.paystack) !== null && _l !== void 0 ? _l : null });
    }
    else {
        const bankCode = String((_m = (_d = req.data) === null || _d === void 0 ? void 0 : _d.bankCode) !== null && _m !== void 0 ? _m : '').trim();
        const bankName = String((_o = (_e = req.data) === null || _e === void 0 ? void 0 : _e.bankName) !== null && _o !== void 0 ? _o : '').trim().slice(0, 80);
        const account = String((_p = (_f = req.data) === null || _f === void 0 ? void 0 : _f.accountNumber) !== null && _p !== void 0 ? _p : '').replace(/\s/g, '');
        if (!bankCode || !/^[0-9A-Za-z]{6,20}$/.test(account))
            throw new https_1.HttpsError('invalid-argument', 'Check your bank and account number.');
        Object.assign(pub, { bankCode, label: bankName || 'Bank account', last4: account.slice(-4) });
        Object.assign(secret, { bankCode, accountNumber: account });
    }
    const ref = db().collection(`payout_methods/${uid}/methods`).doc();
    const batch = db().batch();
    batch.set(ref, pub);
    batch.set(db().doc(`payout_method_secrets/${uid}_${ref.id}`), secret);
    await batch.commit();
    return Object.assign(Object.assign({ id: ref.id }, pub), { createdAt: null });
});
exports.deletePayoutMethod = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = me(req);
    const id = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : '');
    if (!id || id.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Missing method.');
    const batch = db().batch();
    batch.delete(db().doc(`payout_methods/${uid}/methods/${id}`));
    batch.delete(db().doc(`payout_method_secrets/${uid}_${id}`));
    await batch.commit();
    return { ok: true };
});
// ───────────────────────────── Withdrawals ─────────────────────────────
const now = () => firestore_1.Timestamp.now();
async function notify(uid, id, title, body) {
    await db().collection('notifications').doc(id).set({
        userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
        title, body, deepLink: '/wallet', isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    }).catch(() => undefined);
}
/** Moves a withdrawal to paid / failed / cancelled and settles the Diamonds. Idempotent. */
async function settle(wid, to, info = {}) {
    var _a;
    const ref = db().doc(`withdrawals/${wid}`);
    const done = await db().runTransaction(async (tx) => {
        const w = (await tx.get(ref)).data();
        if (!w || !(0, payoutLogic_1.canMove)(w.status, to))
            return null;
        const wallet = db().doc(`wallets/${w.uid}`);
        const d = Number(w.diamonds);
        tx.update(ref, Object.assign(Object.assign({ status: to }, info), { updatedAt: firestore_1.FieldValue.serverTimestamp(), timeline: firestore_1.FieldValue.arrayUnion({ status: to, at: now() }) }));
        tx.update(wallet.collection('ledger').doc(`withdraw_${wid}`), { status: to === 'paid' ? 'completed' : to });
        if (to === 'paid') {
            tx.set(wallet, { lockedCoins: firestore_1.FieldValue.increment(-d), withdrawnCoins: firestore_1.FieldValue.increment(d), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        }
        else if (to === 'failed' || to === 'cancelled') {
            tx.set(wallet, { lockedCoins: firestore_1.FieldValue.increment(-d), availableCoins: firestore_1.FieldValue.increment(d), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
            tx.set(wallet.collection('ledger').doc(`withdraw_${wid}_back`), {
                amount: d, type: 'withdrawal_returned', status: 'completed', referenceId: wid, createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        return w;
    });
    if (!done)
        return false;
    const money = `${done.currency} ${Number(done.localAmount).toLocaleString('en-US')}`;
    if (to === 'paid')
        await notify(done.uid, `payout_paid_${wid}`, 'Money sent 🎉', `${money} is on its way to your ${done.methodLabel}. Keep creating!`);
    if (to === 'failed')
        await notify(done.uid, `payout_failed_${wid}`, 'Withdrawal didn’t go through', `Your Diamonds are back in your wallet. ${(_a = info.failureReason) !== null && _a !== void 0 ? _a : ''}`.trim());
    return true;
}
async function flwTransfer(key, w, s, wid) {
    var _a;
    var _b, _c;
    const body = {
        account_bank: w.rail === 'mobile_money' ? s.flwBank : s.bankCode,
        account_number: w.rail === 'mobile_money' ? s.msisdn : s.accountNumber,
        amount: w.localAmount,
        currency: w.currency,
        debit_currency: 'USD',
        narration: 'Oneova creator payout',
        reference: wid,
        beneficiary_name: w.holderName,
    };
    const res = await fetch(`${FLW}/transfers`, {
        method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).then((r) => r.json());
    if ((res === null || res === void 0 ? void 0 : res.status) !== 'success')
        throw new Error((_b = res === null || res === void 0 ? void 0 : res.message) !== null && _b !== void 0 ? _b : 'Flutterwave refused the transfer');
    return String((_c = (_a = res.data) === null || _a === void 0 ? void 0 : _a.id) !== null && _c !== void 0 ? _c : '');
}
async function paystackTransfer(key, w, s, wid, secretRef) {
    var _a;
    var _b, _c, _d, _e;
    const headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
    let recipient = s.paystackRecipient;
    if (!recipient) {
        const bankType = { NG: 'nuban', GH: 'ghipss', KE: 'kepss', ZA: 'basa' };
        const r = await fetch(`${PAYSTACK}/transferrecipient`, {
            method: 'POST', headers,
            body: JSON.stringify(w.rail === 'mobile_money'
                ? { type: 'mobile_money', name: w.holderName, account_number: s.msisdn, bank_code: s.paystackBank, currency: w.currency }
                : { type: (_b = bankType[w.country]) !== null && _b !== void 0 ? _b : 'nuban', name: w.holderName, account_number: s.accountNumber, bank_code: s.bankCode, currency: w.currency }),
        }).then((x) => x.json());
        if (!(r === null || r === void 0 ? void 0 : r.status))
            throw new Error((_c = r === null || r === void 0 ? void 0 : r.message) !== null && _c !== void 0 ? _c : 'Paystack could not add this account');
        recipient = String(r.data.recipient_code);
        await secretRef.update({ paystackRecipient: recipient });
    }
    const t = await fetch(`${PAYSTACK}/transfer`, {
        method: 'POST', headers,
        body: JSON.stringify({ source: 'balance', amount: Math.round(Number(w.localAmount) * 100), recipient, reference: wid, reason: 'Oneova creator payout', currency: w.currency }),
    }).then((x) => x.json());
    if (!(t === null || t === void 0 ? void 0 : t.status))
        throw new Error((_d = t === null || t === void 0 ? void 0 : t.message) !== null && _d !== void 0 ? _d : 'Paystack refused the transfer');
    return String((_e = (_a = t.data) === null || _a === void 0 ? void 0 : _a.transfer_code) !== null && _e !== void 0 ? _e : '');
}
/** Sends a pending withdrawal to its provider. */
async function dispatch(wid) {
    var _a, _b;
    const ref = db().doc(`withdrawals/${wid}`);
    const w = await db().runTransaction(async (tx) => {
        const d = (await tx.get(ref)).data();
        if (!d || d.status !== 'pending' || d.review === true)
            return null;
        tx.update(ref, { status: 'processing', updatedAt: firestore_1.FieldValue.serverTimestamp(), timeline: firestore_1.FieldValue.arrayUnion({ status: 'processing', at: now() }) });
        return d;
    });
    if (!w)
        return;
    const secretRef = db().doc(`payout_method_secrets/${w.uid}_${w.methodId}`);
    const s = (await secretRef.get()).data();
    if (!s) {
        await settle(wid, 'failed', { failureReason: 'The payout method was removed.' });
        return;
    }
    const cfg = await configured();
    try {
        let providerRef = '';
        if (w.provider === 'stripe') {
            const stripe = new stripe_1.default(cfg.keys.st, { apiVersion: '2025-02-24.acacia' });
            const t = await stripe.transfers.create({
                amount: Math.round(Number(w.netUsd) * 100), currency: 'usd', destination: s.stripeAccountId,
                description: 'Oneova creator payout', metadata: { withdrawalId: wid, uid: w.uid },
            }, { idempotencyKey: `wd_${wid}` });
            await ref.update({ providerRef: t.id });
            await settle(wid, 'paid', { paidAt: firestore_1.FieldValue.serverTimestamp() });
            return;
        }
        if (w.provider === 'flutterwave' && cfg.keys.flw)
            providerRef = await flwTransfer(cfg.keys.flw, w, s, wid);
        else if (w.provider === 'paystack' && cfg.keys.ps)
            providerRef = await paystackTransfer(cfg.keys.ps, w, s, wid, secretRef);
        else
            throw new Error('Payouts are paused for this method.');
        await ref.update({ providerRef, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    }
    catch (e) {
        logger.error('payout dispatch failed', wid, (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e);
        await settle(wid, 'failed', { failureReason: String((_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : 'The provider refused the transfer.').slice(0, 200) });
    }
}
exports.requestWithdrawal = (0, https_1.onCall)({ timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c, _d;
    var _e, _f;
    const uid = me(req);
    const key = String((_e = (_a = req.data) === null || _a === void 0 ? void 0 : _a.idempotencyKey) !== null && _e !== void 0 ? _e : '');
    if (key.length < 8 || key.length > 80)
        throw new https_1.HttpsError('invalid-argument', 'Missing request id.');
    const wid = crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 32);
    const ref = db().doc(`withdrawals/${wid}`);
    const existing = await ref.get();
    if (existing.exists)
        return { id: wid, status: existing.get('status'), duplicate: true };
    const kyc = await verifiedKyc(uid);
    await releaseMatured(uid);
    const methodId = String((_f = (_b = req.data) === null || _b === void 0 ? void 0 : _b.methodId) !== null && _f !== void 0 ? _f : '');
    const method = methodId && !methodId.includes('/') ? (await db().doc(`payout_methods/${uid}/methods/${methodId}`).get()).data() : null;
    if (!method)
        throw new https_1.HttpsError('invalid-argument', 'Choose where to send the money.');
    const cfg = await configured();
    if (!(0, payoutLogic_1.railsFor)(method.country, cfg).some((o) => o.rail === method.rail && o.provider === method.provider)) {
        throw new https_1.HttpsError('failed-precondition', 'This payout method is paused right now. Try another one.');
    }
    const diamonds = Math.floor(Number((_c = req.data) === null || _c === void 0 ? void 0 : _c.diamonds));
    const amountUsd = Math.round((0, payoutLogic_1.diamondsToUsd)(diamonds) * 100) / 100;
    if (!Number.isFinite(diamonds) || amountUsd < payoutLogic_1.MIN_WITHDRAW_USD)
        throw new https_1.HttpsError('invalid-argument', `The minimum withdrawal is $${payoutLogic_1.MIN_WITHDRAW_USD}.`);
    if (amountUsd > payoutLogic_1.MAX_WITHDRAW_USD)
        throw new https_1.HttpsError('invalid-argument', `You can withdraw up to $${payoutLogic_1.MAX_WITHDRAW_USD} at a time.`);
    // Velocity: one open withdrawal at a time and a few per day.
    const recent = await db().collection('withdrawals').where('uid', '==', uid).orderBy('createdAt', 'desc').limit(20).get();
    const open = recent.docs.find((d) => ['pending', 'processing'].includes(d.get('status')));
    if (open)
        throw new https_1.HttpsError('failed-precondition', 'You already have a withdrawal on the way. Wait for it to finish.');
    const today = recent.docs.filter((d) => { var _a; var _b; return ((_b = (_a = d.get('createdAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : Date.now()) > Date.now() - 86400000; });
    if (today.length >= payoutLogic_1.MAX_REQUESTS_PER_DAY)
        throw new https_1.HttpsError('resource-exhausted', 'You reached today’s withdrawal limit. Try again tomorrow.');
    const paidBefore = recent.docs.filter((d) => d.get('status') === 'paid').length;
    const [user, profile, deviceAge] = await Promise.all([
        (0, auth_1.getAuth)().getUser(uid),
        db().doc(`payout_profiles/${uid}`).get(),
        touchDevice(uid, (_d = req.data) === null || _d === void 0 ? void 0 : _d.deviceId),
    ]);
    const locAt = profile.get('locationAt');
    const locationCountry = locAt && Date.now() - locAt.toMillis() < 3 * 86400000 ? profile.get('locationCountry') : null;
    const reasons = (0, payoutLogic_1.fraudReasons)({
        amountUsd,
        accountAgeDays: (Date.now() - new Date(user.metadata.creationTime).getTime()) / 86400000,
        deviceAgeHours: deviceAge,
        paidBefore,
        kycCountry: cc(kyc.country),
        locationCountry,
        payoutCountry: method.country,
    });
    const feeUsd = (0, payoutLogic_1.payoutFeeUsd)(method.rail, amountUsd);
    const netUsd = Math.round((amountUsd - feeUsd) * 100) / 100;
    const rate = method.provider === 'stripe' ? 1 : await usdRate(method.currency);
    const currency = method.provider === 'stripe' ? 'USD' : method.currency;
    const localAmount = (0, payoutLogic_1.roundLocal)(netUsd * rate, currency);
    const wallet = db().doc(`wallets/${uid}`);
    await db().runTransaction(async (tx) => {
        var _a;
        const [w, again] = await Promise.all([tx.get(wallet), tx.get(ref)]);
        if (again.exists)
            return;
        const available = Number((_a = w.get('availableCoins')) !== null && _a !== void 0 ? _a : 0);
        if (available < diamonds)
            throw new https_1.HttpsError('failed-precondition', 'You don’t have that many withdrawable Diamonds yet.');
        tx.set(wallet, { availableCoins: firestore_1.FieldValue.increment(-diamonds), lockedCoins: firestore_1.FieldValue.increment(diamonds), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(wallet.collection('ledger').doc(`withdraw_${wid}`), {
            amount: -diamonds, type: 'withdrawal', status: 'pending', referenceId: wid, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(ref, {
            uid, status: 'pending', diamonds, amountUsd, feeUsd, netUsd, currency, localAmount, fxRate: rate,
            rail: method.rail, provider: method.provider, methodId, methodLabel: `${method.label} ••${method.last4}`,
            holderName: method.holderName, country: method.country,
            review: reasons.length > 0, reviewReasons: reasons,
            createdAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
            timeline: [{ status: 'pending', at: now() }],
        });
    });
    if (!reasons.length)
        await dispatch(wid);
    const final = await ref.get();
    return { id: wid, status: final.get('status'), review: reasons.length > 0, localAmount, currency, netUsd, feeUsd };
});
exports.cancelWithdrawal = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = me(req);
    const id = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : '');
    const w = id && !id.includes('/') ? (await db().doc(`withdrawals/${id}`).get()).data() : null;
    if (!w || w.uid !== uid)
        throw new https_1.HttpsError('not-found', 'Withdrawal not found.');
    if (!(await settle(id, 'cancelled')))
        throw new https_1.HttpsError('failed-precondition', 'It is already being sent and can’t be cancelled.');
    return { ok: true };
});
exports.reviewWithdrawal = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c;
    const uid = me(req);
    if ((await db().doc(`users/${uid}`).get()).get('role') !== 'admin')
        throw new https_1.HttpsError('permission-denied', 'Admins only.');
    const id = String((_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.id) !== null && _c !== void 0 ? _c : '');
    if (!id || id.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Missing withdrawal.');
    if (((_b = req.data) === null || _b === void 0 ? void 0 : _b.approve) === true) {
        await db().doc(`withdrawals/${id}`).update({ review: false, reviewedBy: uid, reviewedAt: firestore_1.FieldValue.serverTimestamp() });
        await dispatch(id);
    }
    else {
        await settle(id, 'failed', { failureReason: 'We couldn’t confirm this request. Contact support if this was you.', reviewedBy: uid });
    }
    return { ok: true };
});
// ───────────────────────────── Provider webhooks ─────────────────────────────
/** Flutterwave transfer.completed → paid / failed (status re-read from the API). */
exports.flutterwaveWebhook = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h;
    const [hash, key] = await Promise.all([(0, optionalSecrets_1.optionalSecret)('FLUTTERWAVE_WEBHOOK_HASH'), (0, optionalSecrets_1.optionalSecret)('FLUTTERWAVE_SECRET_KEY')]);
    const sig = String((_e = req.headers['verif-hash']) !== null && _e !== void 0 ? _e : '');
    if (!hash || !key || sig.length !== hash.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(hash))) {
        res.status(401).send('unauthorized');
        return;
    }
    try {
        const id = (_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.data) === null || _b === void 0 ? void 0 : _b.id;
        if (((_c = req.body) === null || _c === void 0 ? void 0 : _c.event) === 'transfer.completed' && id) {
            const t = await fetch(`${FLW}/transfers/${encodeURIComponent(String(id))}`, { headers: { Authorization: `Bearer ${key}` } }).then((r) => r.json());
            const ref = String((_f = (_d = t === null || t === void 0 ? void 0 : t.data) === null || _d === void 0 ? void 0 : _d.reference) !== null && _f !== void 0 ? _f : '');
            if (/^[0-9a-f]{32}$/.test(ref)) {
                if (t.data.status === 'SUCCESSFUL')
                    await settle(ref, 'paid', { paidAt: firestore_1.FieldValue.serverTimestamp() });
                else if (t.data.status === 'FAILED')
                    await settle(ref, 'failed', { failureReason: String((_g = t.data.complete_message) !== null && _g !== void 0 ? _g : 'The network declined it.').slice(0, 200) });
            }
        }
        res.status(200).send('ok');
    }
    catch (e) {
        logger.error('flutterwave webhook failed', (_h = e === null || e === void 0 ? void 0 : e.message) !== null && _h !== void 0 ? _h : e);
        res.status(500).send('error');
    }
});
/** Paystack transfer.success / failed / reversed (HMAC-SHA512 signed). */
exports.paystackWebhook = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c;
    var _d, _e, _f, _g;
    const key = await (0, optionalSecrets_1.optionalSecret)('PAYSTACK_SECRET_KEY');
    const sig = String((_d = req.headers['x-paystack-signature']) !== null && _d !== void 0 ? _d : '');
    const want = key ? crypto.createHmac('sha512', key).update(req.rawBody).digest('hex') : '';
    if (!key || sig.length !== want.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want))) {
        res.status(401).send('unauthorized');
        return;
    }
    try {
        const ref = String((_e = (_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.data) === null || _b === void 0 ? void 0 : _b.reference) !== null && _e !== void 0 ? _e : '');
        if (/^[0-9a-f]{32}$/.test(ref)) {
            if (req.body.event === 'transfer.success')
                await settle(ref, 'paid', { paidAt: firestore_1.FieldValue.serverTimestamp() });
            if (req.body.event === 'transfer.failed' || req.body.event === 'transfer.reversed') {
                await settle(ref, 'failed', { failureReason: String((_f = (_c = req.body.data) === null || _c === void 0 ? void 0 : _c.reason) !== null && _f !== void 0 ? _f : 'The bank or network declined it.').slice(0, 200) });
            }
        }
        res.status(200).send('ok');
    }
    catch (e) {
        logger.error('paystack webhook failed', (_g = e === null || e === void 0 ? void 0 : e.message) !== null && _g !== void 0 ? _g : e);
        res.status(500).send('error');
    }
});
//# sourceMappingURL=payouts.js.map