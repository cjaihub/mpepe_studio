"use strict";
/**
 * One interface for every payment partner (Flutterwave, Paystack, M-Pesa,
 * MTN MoMo, banks, the sandbox and the test mock). No Firestore here, so it is unit tested.
 *
 * The one rule that keeps money safe: a provider call ends in exactly one of
 *   accepted  the provider took it (it may still finish later by webhook)
 *   rejected  the provider definitely did NOT take it, so it is safe to retry
 *             elsewhere or give the money back
 *   unknown   we can't tell (timeout, 5xx, unreadable reply). The money may have
 *             moved. Never refund or fail over on this; ask the provider's
 *             status endpoint later (reconcile).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.exponent = exports.retryableStatus = void 0;
exports.callJson = callJson;
exports.toMajor = toMajor;
exports.toMinor = toMinor;
/**
 * Calls a provider and sorts the result into ok / client_error / unknown.
 * A network error, timeout, 5xx or unreadable body is `unknown`: the request
 * may have reached the provider. 4xx with a JSON body is `client_error`: the
 * provider read it and said no.
 */
async function callJson(fetchFn, url, init = {}) {
    var _a, _b;
    let res;
    try {
        res = await fetchFn(url, init);
    }
    catch (e) {
        return { kind: 'unknown', status: 0, body: null, reason: `network: ${String((_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e).slice(0, 120)}` };
    }
    let body = null;
    try {
        body = JSON.parse(await res.text());
    }
    catch (_c) {
        return { kind: res.status >= 400 && res.status < 500 ? 'client_error' : 'unknown', status: res.status, body: null, reason: `unreadable reply (${res.status})` };
    }
    if (res.status >= 500 || res.status === 0)
        return { kind: 'unknown', status: res.status, body, reason: `provider error ${res.status}` };
    if (res.status >= 400)
        return { kind: 'client_error', status: res.status, body, reason: String((_b = body === null || body === void 0 ? void 0 : body.message) !== null && _b !== void 0 ? _b : `refused (${res.status})`).slice(0, 200) };
    return { kind: 'ok', status: res.status, body, reason: '' };
}
/** 408 / 409 / 429 mean "not processed now", so trying again (or elsewhere) is safe. */
const retryableStatus = (status) => status === 408 || status === 429 || status === 409;
exports.retryableStatus = retryableStatus;
/** ISO-4217 minor-unit exponents for the currencies we pay out in (default 2). */
const EXPONENT = {
    UGX: 0, RWF: 0, XAF: 0, XOF: 0, BIF: 0, GNF: 0, KMF: 0, DJF: 0, JPY: 0, KRW: 0, VND: 0, CLP: 0, PYG: 0,
    // Shillings and naira have cents on paper but providers pay whole units.
    KES: 2, TZS: 2, NGN: 2, GHS: 2, ZAR: 2, ZMW: 2, MWK: 2, EGP: 2, ETB: 2, USD: 2, EUR: 2, GBP: 2,
};
const exponent = (currency) => { var _a; return (_a = EXPONENT[currency.toUpperCase()]) !== null && _a !== void 0 ? _a : 2; };
exports.exponent = exponent;
/** Integer minor units → the decimal number a provider's JSON field expects. */
function toMajor(amountMinor, currency) {
    if (!Number.isSafeInteger(amountMinor))
        throw new Error('amount must be an integer number of minor units');
    const e = (0, exports.exponent)(currency);
    return e === 0 ? amountMinor : Number((amountMinor / 10 ** e).toFixed(e));
}
/** A decimal amount → integer minor units, rounded half-up once at the edge. */
function toMinor(amount, currency) {
    const e = (0, exports.exponent)(currency);
    return Math.round(Number((amount * 10 ** e).toFixed(6)));
}
//# sourceMappingURL=provider.js.map