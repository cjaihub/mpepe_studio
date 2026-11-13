"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.maskMsisdn = exports.userOf = exports.TOPUP_MAX_USD = exports.TOPUP_MIN_USD = exports.currencyFor = exports.intentTtlMs = exports.isOpenIntent = void 0;
exports.canMoveIntent = canMoveIntent;
exports.methodsFor = methodsFor;
exports.ledgerBalanced = ledgerBalanced;
exports.orderSplit = orderSplit;
exports.balancePayoutFee = balancePayoutFee;
/**
 * Oneova Pay rules with no I/O, so they are unit tested.
 *
 * A pay-in is a `pay_intents/{id}` document:
 *   created → pending_payer → succeeded
 *                           → failed | expired | cancelled
 *   expired / cancelled → succeeded   only when the partner later confirms the
 *                                     money really arrived (a late approval);
 *                                     money that came in is never ignored.
 *   succeeded → refunded
 * Any state → review when the amount paid doesn't match the intent.
 */
const payoutLogic_1 = require("../creator/payoutLogic");
const NEXT = {
    created: ['pending_payer', 'succeeded', 'failed', 'cancelled', 'review'],
    pending_payer: ['succeeded', 'failed', 'expired', 'cancelled', 'review'],
    expired: ['succeeded', 'review'],
    cancelled: ['succeeded', 'review'],
    failed: ['review'],
    succeeded: ['refunded', 'review'],
    refunded: [],
    review: ['succeeded', 'failed', 'refunded'],
};
function canMoveIntent(from, to) {
    var _a;
    var _b;
    return (_b = (_a = NEXT[from]) === null || _a === void 0 ? void 0 : _a.includes(to)) !== null && _b !== void 0 ? _b : false;
}
const isOpenIntent = (s) => s === 'created' || s === 'pending_payer';
exports.isOpenIntent = isOpenIntent;
/** How long a payer has to approve: a phone prompt is short, a hosted page longer. */
const intentTtlMs = (kind) => (kind === 'hosted' ? 45 * 60000 : 10 * 60000);
exports.intentTtlMs = intentTtlMs;
const MOMO_COUNTRIES = ['UG', 'GH', 'RW', 'ZM', 'CM', 'CI', 'BJ'];
const PAYSTACK_COUNTRIES = ['NG', 'GH', 'KE', 'ZA', 'CI'];
const currencyFor = (country) => { var _a; var _b; return (_b = (_a = payoutLogic_1.AFRICA[country]) === null || _a === void 0 ? void 0 : _a.currency) !== null && _b !== void 0 ? _b : 'USD'; };
exports.currencyFor = currencyFor;
/**
 * Ways to pay in [country], best first. A rail appears only when a partner
 * with keys can take it; with the sandbox on, every rail appears and is
 * served by the sandbox instead.
 */
function methodsFor(country, cfg) {
    var _a;
    const a = payoutLogic_1.AFRICA[country];
    const out = [];
    const sbx = (m) => (Object.assign(Object.assign({}, m), { kind: 'prompt', provider: 'sandbox', sandbox: true }));
    for (const n of (_a = a === null || a === void 0 ? void 0 : a.networks) !== null && _a !== void 0 ? _a : []) {
        const id = `momo:${n.id}`;
        const base = { id, rail: 'mobile_money', label: n.label, network: n.id };
        if (n.id === 'MPESA' && country === 'KE' && cfg.mpesa)
            out.push(Object.assign(Object.assign({}, base), { provider: 'mpesa', kind: 'prompt', needsPhone: true }));
        else if (n.id === 'MTN' && MOMO_COUNTRIES.includes(country) && cfg.momo)
            out.push(Object.assign(Object.assign({}, base), { provider: 'mtn_momo', kind: 'prompt', needsPhone: true }));
        else if (cfg.flutterwave)
            out.push(Object.assign(Object.assign({}, base), { provider: 'flutterwave', kind: 'hosted', needsPhone: true }));
        else if (cfg.paystack && PAYSTACK_COUNTRIES.includes(country) && n.paystack)
            out.push(Object.assign(Object.assign({}, base), { provider: 'paystack', kind: 'hosted', needsPhone: true }));
        else if (cfg.sandbox)
            out.push(sbx(Object.assign(Object.assign({}, base), { needsPhone: true })));
    }
    if (cfg.flutterwave)
        out.push({ id: 'card', rail: 'card', provider: 'flutterwave', kind: 'hosted', label: 'Debit or credit card', needsPhone: false });
    else if (cfg.paystack && PAYSTACK_COUNTRIES.includes(country))
        out.push({ id: 'card', rail: 'card', provider: 'paystack', kind: 'hosted', label: 'Debit or credit card', needsPhone: false });
    else if (cfg.sandbox)
        out.push(sbx({ id: 'card', rail: 'card', label: 'Debit or credit card', needsPhone: false }));
    if (a === null || a === void 0 ? void 0 : a.bank) {
        if (cfg.flutterwave)
            out.push({ id: 'bank', rail: 'bank', provider: 'flutterwave', kind: 'hosted', label: 'Bank transfer', needsPhone: false });
        else if (cfg.paystack && PAYSTACK_COUNTRIES.includes(country))
            out.push({ id: 'bank', rail: 'bank', provider: 'paystack', kind: 'hosted', label: 'Bank transfer', needsPhone: false });
    }
    if (cfg.wallet)
        out.unshift({ id: 'balance', rail: 'balance', provider: 'oneova', kind: 'instant', label: 'Oneova balance', needsPhone: false });
    return out;
}
/** Top-up limits, in USD-equivalent major units (checked against the local amount × rate). */
exports.TOPUP_MIN_USD = 1;
exports.TOPUP_MAX_USD = 1000;
/** Every posting must sum to zero per currency, with integer minor units. */
function ledgerBalanced(lines) {
    var _a;
    if (!lines.length)
        return false;
    const sums = new Map();
    for (const l of lines) {
        if (!Number.isSafeInteger(l.amountMinor) || !l.account || !l.currency)
            return false;
        sums.set(l.currency, ((_a = sums.get(l.currency)) !== null && _a !== void 0 ? _a : 0) + l.amountMinor);
    }
    return [...sums.values()].every((v) => v === 0);
}
/** `user:{uid}` → uid, anything else → null. */
const userOf = (account) => (account.startsWith('user:') ? account.slice(5) : null);
exports.userOf = userOf;
// ───────────────────────────── Orders ─────────────────────────────
/**
 * How a paid order's escrow is released, in integer minor units:
 * the seller gets the items minus commission (rounded down to the seller's
 * favour of the platform never taking more than the percent), the rider the
 * delivery fee, the platform the rest. Sums exactly to the total.
 */
function orderSplit(itemsMinor, deliveryMinor, commissionPercent) {
    if (!Number.isSafeInteger(itemsMinor) || !Number.isSafeInteger(deliveryMinor) || itemsMinor < 0 || deliveryMinor < 0) {
        throw new Error('amounts must be non-negative integers');
    }
    const pct = Math.min(Math.max(commissionPercent, 0), 50);
    const platform = Math.floor((itemsMinor * pct) / 100);
    return { seller: itemsMinor - platform, rider: deliveryMinor, platform, total: itemsMinor + deliveryMinor };
}
/** Payout fee on a balance withdrawal, in minor units (mobile money 1.5%, bank 1%). */
function balancePayoutFee(rail, amountMinor) {
    const pct = rail === 'mobile_money' ? 1.5 : 1;
    return Math.ceil((amountMinor * pct) / 100);
}
/** Masks a phone number for display: 2547…1234. */
const maskMsisdn = (m) => (m.length > 8 ? `${m.slice(0, 4)}…${m.slice(-4)}` : '…');
exports.maskMsisdn = maskMsisdn;
//# sourceMappingURL=payLogic.js.map