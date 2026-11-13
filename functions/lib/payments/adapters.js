"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PaystackProvider = exports.FlutterwaveProvider = exports.POLICY = void 0;
/**
 * Real partner adapters behind PaymentProvider. Keys come from Secret Manager
 * (see creator/payouts.ts `configured()`); nothing here reads Firestore.
 *
 * Status lookups by our reference:
 *   Paystack     GET /transfer/verify/:reference (documented) → a not_found an
 *                hour later is final.
 *   Flutterwave  GET /v3/transfers?reference= — only an item whose reference
 *                matches ours counts; not_found never refunds by itself, it
 *                goes to a person. Check this filter in the sandbox.
 */
const provider_1 = require("./provider");
const FLW = 'https://api.flutterwave.com/v3';
const PAYSTACK = 'https://api.paystack.co';
exports.POLICY = {
    paystack: { notFoundIsFinalAfterMs: 3600000, idempotentRetry: false },
    flutterwave: { notFoundIsFinalAfterMs: null, idempotentRetry: false },
    mock: { notFoundIsFinalAfterMs: 3600000, idempotentRetry: true },
};
const fromHttp = (r) => r.kind === 'unknown'
    ? { kind: 'unknown', reason: r.reason }
    : { kind: 'rejected', reason: r.reason, retryable: (0, provider_1.retryableStatus)(r.status) };
class FlutterwaveProvider {
    constructor(key, fetchFn) {
        this.key = key;
        this.fetchFn = fetchFn;
        this.id = 'flutterwave';
    }
    supports(_country, rail) {
        return rail === 'mobile_money' || rail === 'bank';
    }
    headers() {
        return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
    }
    async payout(req) {
        var _a, _b, _c, _d;
        var _e, _f, _g;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${FLW}/transfers`, {
            method: 'POST',
            headers: this.headers(),
            body: JSON.stringify({
                account_bank: req.bankCode,
                account_number: req.account,
                amount: (0, provider_1.toMajor)(req.amountMinor, req.currency),
                currency: req.currency,
                debit_currency: 'USD',
                narration: (_e = req.narration) !== null && _e !== void 0 ? _e : 'Oneova payout',
                reference: req.reference,
                beneficiary_name: req.holderName,
            }),
        });
        if (r.kind !== 'ok')
            return fromHttp(r);
        if (((_a = r.body) === null || _a === void 0 ? void 0 : _a.status) !== 'success')
            return { kind: 'rejected', reason: String((_f = (_b = r.body) === null || _b === void 0 ? void 0 : _b.message) !== null && _f !== void 0 ? _f : 'Flutterwave refused the transfer').slice(0, 200), retryable: false };
        return { kind: 'accepted', providerRef: String((_g = (_d = (_c = r.body) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.id) !== null && _g !== void 0 ? _g : '') };
    }
    async status(reference) {
        var _a, _b;
        var _c, _d;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${FLW}/transfers?reference=${encodeURIComponent(reference)}`, { headers: this.headers() });
        if (r.kind !== 'ok')
            return { status: 'unknown', reason: r.reason };
        const items = Array.isArray((_a = r.body) === null || _a === void 0 ? void 0 : _a.data) ? r.body.data : ((_b = r.body) === null || _b === void 0 ? void 0 : _b.data) ? [r.body.data] : [];
        const t = items.find((x) => { var _a; return String((_a = x === null || x === void 0 ? void 0 : x.reference) !== null && _a !== void 0 ? _a : '') === reference; });
        if (!t)
            return { status: 'not_found' };
        const s = String((_c = t.status) !== null && _c !== void 0 ? _c : '').toUpperCase();
        const status = s === 'SUCCESSFUL' ? 'paid' : s === 'FAILED' ? 'failed' : 'pending';
        return { status, providerRef: String((_d = t.id) !== null && _d !== void 0 ? _d : ''), reason: t.complete_message };
    }
}
exports.FlutterwaveProvider = FlutterwaveProvider;
class PaystackProvider {
    /**
     * [recipient] returns a cached recipient code for this payee, or null;
     * [saveRecipient] stores a new one. Creating a recipient moves no money.
     */
    constructor(key, fetchFn, recipient = async () => null, saveRecipient = async () => undefined) {
        this.key = key;
        this.fetchFn = fetchFn;
        this.recipient = recipient;
        this.saveRecipient = saveRecipient;
        this.id = 'paystack';
    }
    supports(country, rail) {
        return ['NG', 'GH', 'KE', 'ZA', 'CI'].includes(country) && (rail === 'mobile_money' || rail === 'bank');
    }
    headers() {
        return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
    }
    async payout(req) {
        var _a, _b, _c, _d, _e, _f;
        var _g, _h, _j, _k, _l;
        let code = await this.recipient(req);
        if (!code) {
            const bankType = { NG: 'nuban', GH: 'ghipss', KE: 'kepss', ZA: 'basa' };
            const r = await (0, provider_1.callJson)(this.fetchFn, `${PAYSTACK}/transferrecipient`, {
                method: 'POST',
                headers: this.headers(),
                body: JSON.stringify(req.rail === 'mobile_money'
                    ? { type: 'mobile_money', name: req.holderName, account_number: req.account, bank_code: req.bankCode, currency: req.currency }
                    : { type: (_g = bankType[req.country]) !== null && _g !== void 0 ? _g : 'nuban', name: req.holderName, account_number: req.account, bank_code: req.bankCode, currency: req.currency }),
            });
            // No transfer was sent yet, so any failure here is a safe "rejected".
            if (r.kind !== 'ok' || !((_a = r.body) === null || _a === void 0 ? void 0 : _a.status)) {
                return { kind: 'rejected', reason: r.reason || String((_h = (_b = r.body) === null || _b === void 0 ? void 0 : _b.message) !== null && _h !== void 0 ? _h : 'Paystack could not add this account'), retryable: r.kind === 'unknown' || (0, provider_1.retryableStatus)(r.status) };
            }
            code = String(r.body.data.recipient_code);
            await this.saveRecipient(req, code);
        }
        const t = await (0, provider_1.callJson)(this.fetchFn, `${PAYSTACK}/transfer`, {
            method: 'POST',
            headers: this.headers(),
            body: JSON.stringify({
                source: 'balance', amount: req.amountMinor, recipient: code, reference: req.reference,
                reason: (_j = req.narration) !== null && _j !== void 0 ? _j : 'Oneova payout', currency: req.currency,
            }),
        });
        if (t.kind !== 'ok')
            return fromHttp(t);
        if (!((_c = t.body) === null || _c === void 0 ? void 0 : _c.status))
            return { kind: 'rejected', reason: String((_k = (_d = t.body) === null || _d === void 0 ? void 0 : _d.message) !== null && _k !== void 0 ? _k : 'Paystack refused the transfer').slice(0, 200), retryable: false };
        return { kind: 'accepted', providerRef: String((_l = (_f = (_e = t.body) === null || _e === void 0 ? void 0 : _e.data) === null || _f === void 0 ? void 0 : _f.transfer_code) !== null && _l !== void 0 ? _l : '') };
    }
    async status(reference) {
        var _a, _b, _c, _d, _e, _f;
        var _g, _h;
        const r = await (0, provider_1.callJson)(this.fetchFn, `${PAYSTACK}/transfer/verify/${encodeURIComponent(reference)}`, { headers: this.headers() });
        if (r.kind === 'client_error' && r.status === 404)
            return { status: 'not_found' };
        if (r.kind !== 'ok')
            return { status: 'unknown', reason: r.reason };
        const s = String((_g = (_b = (_a = r.body) === null || _a === void 0 ? void 0 : _a.data) === null || _b === void 0 ? void 0 : _b.status) !== null && _g !== void 0 ? _g : '');
        const status = s === 'success' ? 'paid' : s === 'failed' || s === 'reversed' ? 'failed' : 'pending';
        return { status, providerRef: String((_h = (_d = (_c = r.body) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.transfer_code) !== null && _h !== void 0 ? _h : ''), reason: (_f = (_e = r.body) === null || _e === void 0 ? void 0 : _e.data) === null || _f === void 0 ? void 0 : _f.reason };
    }
}
exports.PaystackProvider = PaystackProvider;
//# sourceMappingURL=adapters.js.map