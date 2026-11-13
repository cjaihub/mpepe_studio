"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SandboxCollector = exports.PaystackCollector = exports.FlutterwaveCollector = exports.MomoCollector = exports.MpesaCollector = void 0;
exports.darajaTimestamp = darajaTimestamp;
/**
 * Pay-in partners behind `Collector` (Oneova Pay). Keys come from Secret
 * Manager (see pay/payConfig.ts); a missing key simply turns its rail off.
 * Nothing here reads Firestore, so every adapter is unit tested with a fake
 * fetch.
 *
 *   M-Pesa (Daraja)   STK push on the payer's phone, then STK query
 *   MTN MoMo          request-to-pay on the payer's phone, then status
 *   Flutterwave       the partner's secure page (card, mobile money, bank)
 *   Paystack          the partner's secure page (card, mobile money, bank)
 *   Sandbox           no money; approves a few seconds later (testing)
 *
 * Card numbers never touch Oneova: cards are only taken on a licensed
 * partner's hosted page.
 */
const provider_1 = require("./provider");
const FLW = 'https://api.flutterwave.com/v3';
const PAYSTACK = 'https://api.paystack.co';
const notFound = () => ({ status: 'not_found' });
const unknown = (reason) => ({ status: 'unknown', reason });
/** Daraja wants the timestamp in Kenya time (UTC+3) as YYYYMMDDHHmmss. */
function darajaTimestamp(now) {
    const t = new Date(now.getTime() + 3 * 3600000);
    const p = (n) => String(n).padStart(2, '0');
    return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}
class MpesaCollector {
    constructor(cfg, fetchFn, now = () => new Date()) {
        this.cfg = cfg;
        this.fetchFn = fetchFn;
        this.now = now;
        this.id = 'mpesa';
        this.kind = 'prompt';
    }
    get base() {
        return this.cfg.env === 'production' ? 'https://api.safaricom.co.ke' : 'https://sandbox.safaricom.co.ke';
    }
    supports(country, rail, currency, network) {
        return country === 'KE' && rail === 'mobile_money' && currency === 'KES' && (!network || network === 'MPESA');
    }
    async token() {
        var _a;
        const basic = Buffer.from(`${this.cfg.consumerKey}:${this.cfg.consumerSecret}`).toString('base64');
        const r = await (0, provider_1.callJson)(this.fetchFn, `${this.base}/oauth/v1/generate?grant_type=client_credentials`, { headers: { Authorization: `Basic ${basic}` } });
        return r.kind === 'ok' && ((_a = r.body) === null || _a === void 0 ? void 0 : _a.access_token) ? String(r.body.access_token) : null;
    }
    password(ts) {
        return Buffer.from(`${this.cfg.shortcode}${this.cfg.passkey}${ts}`).toString('base64');
    }
    async collect(req) {
        var _a, _b, _c, _d;
        var _e, _f, _g;
        const amount = (0, provider_1.toMajor)(req.amountMinor, req.currency);
        if (!Number.isInteger(amount) || amount < 1)
            return { kind: 'rejected', reason: 'M-Pesa takes whole shillings only.', retryable: false };
        if (!req.msisdn)
            return { kind: 'rejected', reason: 'Enter your M-Pesa number.', retryable: false };
        // No token means nothing was sent: safe to retry.
        const token = await this.token();
        if (!token)
            return { kind: 'rejected', reason: 'M-Pesa is not answering right now.', retryable: true };
        const ts = darajaTimestamp(this.now());
        const r = await (0, provider_1.callJson)(this.fetchFn, `${this.base}/mpesa/stkpush/v1/processrequest`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                BusinessShortCode: this.cfg.shortcode,
                Password: this.password(ts),
                Timestamp: ts,
                TransactionType: 'CustomerPayBillOnline',
                Amount: amount,
                PartyA: req.msisdn,
                PartyB: this.cfg.shortcode,
                PhoneNumber: req.msisdn,
                CallBackURL: this.cfg.callbackUrl,
                AccountReference: 'Oneova',
                TransactionDesc: ((_e = req.narration) !== null && _e !== void 0 ? _e : 'Oneova payment').slice(0, 13),
            }),
        });
        if (r.kind === 'unknown')
            return { kind: 'unknown', reason: r.reason };
        if (r.kind === 'client_error')
            return { kind: 'rejected', reason: String((_f = (_a = r.body) === null || _a === void 0 ? void 0 : _a.errorMessage) !== null && _f !== void 0 ? _f : r.reason).slice(0, 200), retryable: (0, provider_1.retryableStatus)(r.status) };
        if (String((_b = r.body) === null || _b === void 0 ? void 0 : _b.ResponseCode) !== '0' || !((_c = r.body) === null || _c === void 0 ? void 0 : _c.CheckoutRequestID)) {
            return { kind: 'rejected', reason: String((_g = (_d = r.body) === null || _d === void 0 ? void 0 : _d.ResponseDescription) !== null && _g !== void 0 ? _g : 'M-Pesa refused the request').slice(0, 200), retryable: false };
        }
        return { kind: 'accepted', providerRef: String(r.body.CheckoutRequestID) };
    }
    async check(_reference, providerRef) {
        var _a, _b, _c;
        var _d, _e, _f;
        if (!providerRef)
            return notFound();
        const token = await this.token();
        if (!token)
            return unknown('no token');
        const ts = darajaTimestamp(this.now());
        const r = await (0, provider_1.callJson)(this.fetchFn, `${this.base}/mpesa/stkpushquery/v1/query`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ BusinessShortCode: this.cfg.shortcode, Password: this.password(ts), Timestamp: ts, CheckoutRequestID: providerRef }),
        });
        // While the payer hasn't answered, Daraja replies with an error code.
        const code = String((_d = (_a = r.body) === null || _a === void 0 ? void 0 : _a.errorCode) !== null && _d !== void 0 ? _d : '');
        if (code === '500.001.1001')
            return { status: 'pending', providerRef };
        if (r.kind !== 'ok')
            return unknown(r.reason);
        const result = String((_e = (_b = r.body) === null || _b === void 0 ? void 0 : _b.ResultCode) !== null && _e !== void 0 ? _e : '');
        if (result === '0')
            return { status: 'paid', providerRef };
        if (result === '')
            return { status: 'pending', providerRef };
        return { status: 'failed', providerRef, reason: String((_f = (_c = r.body) === null || _c === void 0 ? void 0 : _c.ResultDesc) !== null && _f !== void 0 ? _f : 'The payment was not completed.').slice(0, 200) };
    }
}
exports.MpesaCollector = MpesaCollector;
const MOMO_COUNTRIES = ['UG', 'GH', 'RW', 'ZM', 'CM', 'CI', 'BJ'];
class MomoCollector {
    constructor(cfg, fetchFn) {
        this.cfg = cfg;
        this.fetchFn = fetchFn;
        this.id = 'mtn_momo';
        this.kind = 'prompt';
    }
    get sandbox() {
        return this.cfg.env === 'sandbox';
    }
    get base() {
        return this.sandbox ? 'https://sandbox.momodeveloper.mtn.com' : 'https://proxy.momoapi.mtn.com';
    }
    supports(country, rail, _currency, network) {
        return rail === 'mobile_money' && MOMO_COUNTRIES.includes(country) && (!network || network === 'MTN');
    }
    async token() {
        var _a;
        const basic = Buffer.from(`${this.cfg.apiUser}:${this.cfg.apiKey}`).toString('base64');
        const r = await (0, provider_1.callJson)(this.fetchFn, `${this.base}/collection/token/`, {
            method: 'POST',
            headers: { Authorization: `Basic ${basic}`, 'Ocp-Apim-Subscription-Key': this.cfg.subscriptionKey },
        });
        return r.kind === 'ok' && ((_a = r.body) === null || _a === void 0 ? void 0 : _a.access_token) ? String(r.body.access_token) : null;
    }
    headers(token, reference) {
        return Object.assign(Object.assign({ Authorization: `Bearer ${token}`, 'X-Target-Environment': this.cfg.env, 'Ocp-Apim-Subscription-Key': this.cfg.subscriptionKey, 'Content-Type': 'application/json' }, (reference ? { 'X-Reference-Id': reference } : {})), (reference && this.cfg.callbackUrl ? { 'X-Callback-Url': this.cfg.callbackUrl } : {}));
    }
    async collect(req) {
        var _a;
        var _b, _c, _d;
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(req.reference)) {
            return { kind: 'rejected', reason: 'MoMo needs a UUID reference.', retryable: false };
        }
        if (!req.msisdn)
            return { kind: 'rejected', reason: 'Enter your MoMo number.', retryable: false };
        const token = await this.token();
        if (!token)
            return { kind: 'rejected', reason: 'MoMo is not answering right now.', retryable: true };
        let res;
        try {
            res = await this.fetchFn(`${this.base}/collection/v1_0/requesttopay`, {
                method: 'POST',
                headers: this.headers(token, req.reference),
                body: JSON.stringify({
                    // The sandbox only takes EUR.
                    amount: String((0, provider_1.toMajor)(req.amountMinor, req.currency)),
                    currency: this.sandbox ? 'EUR' : req.currency,
                    externalId: req.reference,
                    payer: { partyIdType: 'MSISDN', partyId: req.msisdn },
                    payerMessage: ((_b = req.narration) !== null && _b !== void 0 ? _b : 'Oneova payment').slice(0, 160),
                    payeeNote: 'Oneova',
                }),
            });
        }
        catch (e) {
            return { kind: 'unknown', reason: `network: ${String((_c = e === null || e === void 0 ? void 0 : e.message) !== null && _c !== void 0 ? _c : e).slice(0, 120)}` };
        }
        // 202: accepted. 409: this reference already exists (a retry) — same request.
        if (res.status === 202 || res.status === 409)
            return { kind: 'accepted', providerRef: req.reference };
        if (res.status >= 500 || res.status === 0)
            return { kind: 'unknown', reason: `provider error ${res.status}` };
        let msg = `refused (${res.status})`;
        try {
            msg = String((_d = (_a = JSON.parse(await res.text())) === null || _a === void 0 ? void 0 : _a.message) !== null && _d !== void 0 ? _d : msg);
        }
        catch (_e) { /* keep msg */ }
        return { kind: 'rejected', reason: msg.slice(0, 200), retryable: (0, provider_1.retryableStatus)(res.status) };
    }
    async check(reference) {
        var _a, _b, _c, _d, _e, _f;
        var _g, _h, _j, _k;
        const token = await this.token();
        if (!token)
            return unknown('no token');
        const r = await (0, provider_1.callJson)(this.fetchFn, `${this.base}/collection/v1_0/requesttopay/${encodeURIComponent(reference)}`, { headers: this.headers(token) });
        if (r.kind === 'client_error' && r.status === 404)
            return notFound();
        if (r.kind !== 'ok')
            return unknown(r.reason);
        const s = String((_g = (_a = r.body) === null || _a === void 0 ? void 0 : _a.status) !== null && _g !== void 0 ? _g : '').toUpperCase();
        const status = s === 'SUCCESSFUL' ? 'paid' : s === 'FAILED' || s === 'REJECTED' || s === 'TIMEOUT' ? 'failed' : 'pending';
        const currency = String((_h = (_b = r.body) === null || _b === void 0 ? void 0 : _b.currency) !== null && _h !== void 0 ? _h : '');
        return Object.assign(Object.assign({ status, providerRef: String((_j = (_c = r.body) === null || _c === void 0 ? void 0 : _c.financialTransactionId) !== null && _j !== void 0 ? _j : reference) }, (status === 'paid' && currency && !this.sandbox ? { amountMinor: (0, provider_1.toMinor)(Number((_d = r.body) === null || _d === void 0 ? void 0 : _d.amount), currency), currency } : {})), { reason: ((_e = r.body) === null || _e === void 0 ? void 0 : _e.reason) ? String((_k = (_f = r.body.reason) === null || _f === void 0 ? void 0 : _f.message) !== null && _k !== void 0 ? _k : r.body.reason).slice(0, 200) : undefined });
    }
}
exports.MomoCollector = MomoCollector;
// ───────────────────────────── Flutterwave (hosted page) ─────────────────────────────
class FlutterwaveCollector {
    constructor(key, fetchFn, countries) {
        this.key = key;
        this.fetchFn = fetchFn;
        this.countries = countries;
        this.id = 'flutterwave';
        this.kind = 'hosted';
    }
    headers() {
        return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
    }
    supports(country, rail) {
        return rail === 'card' || ((rail === 'mobile_money' || rail === 'bank') && this.countries.includes(country));
    }
    async collect(req) {
        var _a, _b, _c, _d;
        var _e, _f, _g;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${FLW}/payments`, {
            method: 'POST',
            headers: this.headers(),
            body: JSON.stringify({
                tx_ref: req.reference,
                amount: (0, provider_1.toMajor)(req.amountMinor, req.currency),
                currency: req.currency,
                redirect_url: req.returnUrl,
                payment_options: req.rail === 'card' ? 'card' : req.rail === 'bank' ? 'banktransfer,account' : 'mobilemoneyghana,mobilemoneyuganda,mobilemoneyrwanda,mobilemoneyzambia,mobilemoneytanzania,mobilemoneyfranco,mpesa',
                customer: { email: req.email, phonenumber: req.msisdn, name: req.payerName },
                customizations: { title: 'Oneova', description: ((_e = req.narration) !== null && _e !== void 0 ? _e : 'Oneova payment').slice(0, 100) },
                meta: { reference: req.reference },
            }),
        });
        if (r.kind === 'unknown')
            return { kind: 'unknown', reason: r.reason };
        if (r.kind === 'client_error' || ((_a = r.body) === null || _a === void 0 ? void 0 : _a.status) !== 'success' || !((_c = (_b = r.body) === null || _b === void 0 ? void 0 : _b.data) === null || _c === void 0 ? void 0 : _c.link)) {
            return { kind: 'rejected', reason: String((_g = (_f = (_d = r.body) === null || _d === void 0 ? void 0 : _d.message) !== null && _f !== void 0 ? _f : r.reason) !== null && _g !== void 0 ? _g : 'Could not open the payment page').slice(0, 200), retryable: (0, provider_1.retryableStatus)(r.status) };
        }
        // Opening a page moves no money; the payer pays there.
        return { kind: 'accepted', providerRef: '', redirectUrl: String(r.body.data.link) };
    }
    async check(reference) {
        var _a, _b;
        var _c, _d, _e, _f, _g, _h;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${FLW}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(reference)}`, { headers: this.headers() });
        if (r.kind === 'client_error' && (r.status === 404 || /no transaction/i.test(String((_c = (_a = r.body) === null || _a === void 0 ? void 0 : _a.message) !== null && _c !== void 0 ? _c : ''))))
            return notFound();
        if (r.kind !== 'ok')
            return unknown(r.reason);
        const d = (_d = (_b = r.body) === null || _b === void 0 ? void 0 : _b.data) !== null && _d !== void 0 ? _d : {};
        if (String((_e = d.tx_ref) !== null && _e !== void 0 ? _e : '') !== reference)
            return notFound();
        const s = String((_f = d.status) !== null && _f !== void 0 ? _f : '').toLowerCase();
        const status = s === 'successful' ? 'paid' : s === 'failed' || s === 'cancelled' ? 'failed' : 'pending';
        const currency = String((_g = d.currency) !== null && _g !== void 0 ? _g : '');
        return Object.assign(Object.assign({ status, providerRef: String((_h = d.id) !== null && _h !== void 0 ? _h : '') }, (status === 'paid' && currency ? { amountMinor: (0, provider_1.toMinor)(Number(d.amount), currency), currency } : {})), { reason: d.processor_response ? String(d.processor_response).slice(0, 200) : undefined });
    }
    async refund(_reference, providerRef, amountMinor, currency) {
        var _a, _b, _c, _d;
        var _e, _f;
        if (!providerRef)
            return { kind: 'rejected', reason: 'missing transaction id', retryable: false };
        const r = await (0, provider_1.callJson)(this.fetchFn, `${FLW}/transactions/${encodeURIComponent(providerRef)}/refund`, {
            method: 'POST',
            headers: this.headers(),
            body: JSON.stringify({ amount: (0, provider_1.toMajor)(amountMinor, currency) }),
        });
        if (r.kind === 'unknown')
            return { kind: 'unknown', reason: r.reason };
        if (r.kind !== 'ok' || ((_a = r.body) === null || _a === void 0 ? void 0 : _a.status) !== 'success')
            return { kind: 'rejected', reason: String((_e = (_b = r.body) === null || _b === void 0 ? void 0 : _b.message) !== null && _e !== void 0 ? _e : r.reason).slice(0, 200), retryable: (0, provider_1.retryableStatus)(r.status) };
        return { kind: 'accepted', providerRef: String((_f = (_d = (_c = r.body) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.id) !== null && _f !== void 0 ? _f : '') };
    }
}
exports.FlutterwaveCollector = FlutterwaveCollector;
// ───────────────────────────── Paystack (hosted page) ─────────────────────────────
const PAYSTACK_COUNTRIES = ['NG', 'GH', 'KE', 'ZA', 'CI'];
class PaystackCollector {
    constructor(key, fetchFn) {
        this.key = key;
        this.fetchFn = fetchFn;
        this.id = 'paystack';
        this.kind = 'hosted';
    }
    headers() {
        return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
    }
    supports(country, rail) {
        return PAYSTACK_COUNTRIES.includes(country) && (rail === 'card' || rail === 'mobile_money' || rail === 'bank');
    }
    async collect(req) {
        var _a, _b, _c, _d;
        var _e, _f, _g;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${PAYSTACK}/transaction/initialize`, {
            method: 'POST',
            headers: this.headers(),
            body: JSON.stringify({
                email: req.email,
                // Paystack takes the amount in subunits, which is our minor units.
                amount: req.amountMinor,
                currency: req.currency,
                reference: req.reference,
                callback_url: req.returnUrl,
                channels: req.rail === 'card' ? ['card'] : req.rail === 'bank' ? ['bank', 'bank_transfer', 'ussd'] : ['mobile_money'],
                metadata: { reference: req.reference },
            }),
        });
        if (r.kind === 'unknown')
            return { kind: 'unknown', reason: r.reason };
        if (r.kind === 'client_error' || !((_a = r.body) === null || _a === void 0 ? void 0 : _a.status) || !((_c = (_b = r.body) === null || _b === void 0 ? void 0 : _b.data) === null || _c === void 0 ? void 0 : _c.authorization_url)) {
            return { kind: 'rejected', reason: String((_f = (_e = (_d = r.body) === null || _d === void 0 ? void 0 : _d.message) !== null && _e !== void 0 ? _e : r.reason) !== null && _f !== void 0 ? _f : 'Could not open the payment page').slice(0, 200), retryable: (0, provider_1.retryableStatus)(r.status) };
        }
        return { kind: 'accepted', providerRef: String((_g = r.body.data.access_code) !== null && _g !== void 0 ? _g : ''), redirectUrl: String(r.body.data.authorization_url) };
    }
    async check(reference) {
        var _a;
        var _b, _c, _d, _e;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${PAYSTACK}/transaction/verify/${encodeURIComponent(reference)}`, { headers: this.headers() });
        if (r.kind === 'client_error' && (r.status === 404 || r.status === 400))
            return notFound();
        if (r.kind !== 'ok')
            return unknown(r.reason);
        const d = (_b = (_a = r.body) === null || _a === void 0 ? void 0 : _a.data) !== null && _b !== void 0 ? _b : {};
        const s = String((_c = d.status) !== null && _c !== void 0 ? _c : '').toLowerCase();
        // "abandoned" / "ongoing": the payer hasn't finished on the page yet.
        const status = s === 'success' ? 'paid' : s === 'failed' || s === 'reversed' ? 'failed' : 'pending';
        return Object.assign(Object.assign({ status, providerRef: String((_d = d.id) !== null && _d !== void 0 ? _d : '') }, (status === 'paid' ? { amountMinor: Number(d.amount), currency: String((_e = d.currency) !== null && _e !== void 0 ? _e : '') } : {})), { reason: d.gateway_response ? String(d.gateway_response).slice(0, 200) : undefined });
    }
    async refund(reference, _providerRef, amountMinor) {
        var _a, _b, _c, _d;
        var _e, _f;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${PAYSTACK}/refund`, {
            method: 'POST',
            headers: this.headers(),
            body: JSON.stringify({ transaction: reference, amount: amountMinor }),
        });
        if (r.kind === 'unknown')
            return { kind: 'unknown', reason: r.reason };
        if (r.kind !== 'ok' || !((_a = r.body) === null || _a === void 0 ? void 0 : _a.status))
            return { kind: 'rejected', reason: String((_e = (_b = r.body) === null || _b === void 0 ? void 0 : _b.message) !== null && _e !== void 0 ? _e : r.reason).slice(0, 200), retryable: (0, provider_1.retryableStatus)(r.status) };
        return { kind: 'accepted', providerRef: String((_f = (_d = (_c = r.body) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.id) !== null && _f !== void 0 ? _f : '') };
    }
}
exports.PaystackCollector = PaystackCollector;
// ───────────────────────────── Sandbox ─────────────────────────────
/**
 * Moves no money. The payer "approves" [approveAfterMs] after the prompt;
 * an amount ending in 90 (minor units) is declined, so failures can be tested.
 * Only switched on with PAY_SANDBOX=true, and every intent it touches is
 * marked `sandbox: true`.
 */
class SandboxCollector {
    constructor(now = () => Date.now(), approveAfterMs = 4000) {
        this.now = now;
        this.approveAfterMs = approveAfterMs;
        this.id = 'sandbox';
        this.kind = 'prompt';
    }
    supports() {
        return true;
    }
    async collect(req) {
        if (!Number.isSafeInteger(req.amountMinor) || req.amountMinor <= 0)
            return { kind: 'rejected', reason: 'invalid amount', retryable: false };
        return { kind: 'accepted', providerRef: `sbx_${this.now()}_${req.amountMinor}` };
    }
    async check(_reference, providerRef) {
        const m = /^sbx_(\d+)_(\d+)$/.exec(providerRef !== null && providerRef !== void 0 ? providerRef : '');
        if (!m)
            return notFound();
        const at = Number(m[1]);
        const amountMinor = Number(m[2]);
        if (this.now() - at < this.approveAfterMs)
            return { status: 'pending', providerRef };
        if (amountMinor % 100 === 90)
            return { status: 'failed', providerRef, reason: 'Declined on the phone (sandbox).' };
        return { status: 'paid', providerRef, amountMinor };
    }
    async refund() {
        return { kind: 'accepted', providerRef: `sbx_refund_${this.now()}` };
    }
}
exports.SandboxCollector = SandboxCollector;
//# sourceMappingURL=collectAdapters.js.map