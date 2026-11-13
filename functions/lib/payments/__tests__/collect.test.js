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
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert/strict"));
const collectAdapters_1 = require("../collectAdapters");
function fake(replies) {
    const calls = [];
    const f = (async (url) => {
        calls.push(url);
        const key = Object.keys(replies).find((k) => url.includes(k));
        if (!key)
            throw new Error(`unexpected ${url}`);
        const r = typeof replies[key] === 'function' ? replies[key]() : replies[key];
        return { status: r.status, text: async () => (typeof r.body === 'string' ? r.body : JSON.stringify(r.body)) };
    });
    f.calls = calls;
    return f;
}
const uuid = '3f2b8c1e-6a4d-4e2f-9b1a-2c3d4e5f6a7b';
(0, node_test_1.test)('Daraja timestamp is Kenya time', () => {
    assert.equal((0, collectAdapters_1.darajaTimestamp)(new Date(Date.UTC(2026, 10, 12, 22, 5, 9))), '20261113010509');
});
(0, node_test_1.test)('M-Pesa: STK accepted, then pending, then paid', async () => {
    let state = 'pending';
    const f = fake({
        '/oauth/v1/generate': { status: 200, body: { access_token: 't' } },
        '/stkpush/v1/processrequest': { status: 200, body: { ResponseCode: '0', CheckoutRequestID: 'ws_CO_1' } },
        '/stkpushquery': () => (state === 'pending'
            ? { status: 500, body: { errorCode: '500.001.1001', errorMessage: 'The transaction is being processed' } }
            : { status: 200, body: { ResultCode: '0', ResultDesc: 'ok' } }),
    });
    const c = new collectAdapters_1.MpesaCollector({ consumerKey: 'k', consumerSecret: 's', shortcode: '174379', passkey: 'p', env: 'sandbox', callbackUrl: 'https://x' }, f);
    const out = await c.collect({ reference: uuid, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor: 150000, msisdn: '254712345678' });
    assert.deepEqual(out, { kind: 'accepted', providerRef: 'ws_CO_1' });
    assert.equal((await c.check(uuid, 'ws_CO_1')).status, 'pending');
    state = 'paid';
    assert.equal((await c.check(uuid, 'ws_CO_1')).status, 'paid');
});
(0, node_test_1.test)('M-Pesa: cancelled on the phone is failed; cents refused', async () => {
    const f = fake({
        '/oauth/v1/generate': { status: 200, body: { access_token: 't' } },
        '/stkpushquery': { status: 200, body: { ResultCode: '1032', ResultDesc: 'Request cancelled by user' } },
    });
    const c = new collectAdapters_1.MpesaCollector({ consumerKey: 'k', consumerSecret: 's', shortcode: '1', passkey: 'p', env: 'sandbox', callbackUrl: 'x' }, f);
    assert.equal((await c.check(uuid, 'ws')).status, 'failed');
    const r = await c.collect({ reference: uuid, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor: 150050, msisdn: '254712345678' });
    assert.equal(r.kind, 'rejected');
});
(0, node_test_1.test)('M-Pesa: a timeout on the push is unknown, never rejected', async () => {
    const f = fake({
        '/oauth/v1/generate': { status: 200, body: { access_token: 't' } },
        '/stkpush/v1/processrequest': { status: 504, body: 'gateway timeout' },
    });
    const c = new collectAdapters_1.MpesaCollector({ consumerKey: 'k', consumerSecret: 's', shortcode: '1', passkey: 'p', env: 'sandbox', callbackUrl: 'x' }, f);
    const r = await c.collect({ reference: uuid, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor: 100, msisdn: '254712345678' });
    assert.equal(r.kind, 'unknown');
});
(0, node_test_1.test)('MoMo: 202 accepted, 409 duplicate is the same request, status maps', async () => {
    let code = 202;
    const f = fake({
        '/collection/token/': { status: 200, body: { access_token: 't' } },
        '/requesttopay/': { status: 200, body: { status: 'SUCCESSFUL', amount: '5000', currency: 'UGX', financialTransactionId: '99' } },
        '/requesttopay': () => ({ status: code, body: '' }),
    });
    const c = new collectAdapters_1.MomoCollector({ subscriptionKey: 's', apiUser: 'u', apiKey: 'k', env: 'mtnuganda' }, f);
    const req = { reference: uuid, country: 'UG', rail: 'mobile_money', currency: 'UGX', amountMinor: 5000, msisdn: '256772000000' };
    assert.equal((await c.collect(req)).kind, 'accepted');
    code = 409;
    assert.equal((await c.collect(req)).kind, 'accepted');
    const chk = await c.check(uuid);
    assert.equal(chk.status, 'paid');
    assert.equal(chk.amountMinor, 5000);
    assert.equal((await c.collect(Object.assign(Object.assign({}, req), { reference: 'not-a-uuid' }))).kind, 'rejected');
});
(0, node_test_1.test)('Paystack: hosted page link, verify amount in subunits, not found', async () => {
    const f = fake({
        '/transaction/initialize': { status: 200, body: { status: true, data: { authorization_url: 'https://checkout/x', access_code: 'ac' } } },
        [`/transaction/verify/${uuid}`]: { status: 200, body: { status: true, data: { status: 'success', amount: 250000, currency: 'NGN', id: 7 } } },
        '/transaction/verify/missing': { status: 400, body: { status: false, message: 'Transaction reference not found' } },
    });
    const c = new collectAdapters_1.PaystackCollector('sk', f);
    const out = await c.collect({ reference: uuid, country: 'NG', rail: 'card', currency: 'NGN', amountMinor: 250000, email: 'a@b.c' });
    assert.equal(out.kind === 'accepted' && out.redirectUrl, 'https://checkout/x');
    assert.deepEqual(await c.check(uuid), { status: 'paid', providerRef: '7', amountMinor: 250000, currency: 'NGN', reason: undefined });
    assert.equal((await c.check('missing')).status, 'not_found');
});
(0, node_test_1.test)('sandbox approves after a delay and declines amounts ending in 90', async () => {
    let now = 1000000;
    const c = new collectAdapters_1.SandboxCollector(() => now, 4000);
    const ok = await c.collect({ reference: uuid, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor: 1000 });
    assert.equal(ok.kind, 'accepted');
    const ref = ok.kind === 'accepted' ? ok.providerRef : '';
    assert.equal((await c.check(uuid, ref)).status, 'pending');
    now += 5000;
    assert.equal((await c.check(uuid, ref)).status, 'paid');
    const bad = await c.collect({ reference: uuid, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor: 1090 });
    now += 5000;
    assert.equal((await c.check(uuid, bad.kind === 'accepted' ? bad.providerRef : '')).status, 'failed');
});
//# sourceMappingURL=collect.test.js.map