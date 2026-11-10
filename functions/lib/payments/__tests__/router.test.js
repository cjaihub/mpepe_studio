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
const mockProvider_1 = require("../mockProvider");
const router_1 = require("../router");
const provider_1 = require("../provider");
const adapters_1 = require("../adapters");
const req = (amountMinor, reference = 'ref_1') => ({
    reference, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor, holderName: 'A B', account: '254700000000', bankCode: 'MPS',
});
(0, node_test_1.test)('accepted on the first provider', async () => {
    const a = new mockProvider_1.MockProvider({ id: 'mock' });
    const r = await (0, router_1.routePayout)([a], req(10000));
    assert.equal(r.outcome.kind, 'accepted');
    assert.equal(r.provider, 'mock');
    assert.equal(a.paidCount('ref_1'), 1);
});
(0, node_test_1.test)('fails over only when the first provider definitely took nothing', async () => {
    const a = new mockProvider_1.MockProvider({ id: 'mock', down: true });
    const b = new mockProvider_1.MockProvider({ id: 'mock_b' });
    const r = await (0, router_1.routePayout)([a, b], req(10000));
    assert.equal(r.outcome.kind, 'accepted');
    assert.equal(r.provider, 'mock_b');
    assert.deepEqual(r.attempts.map((x) => x.provider), ['mock', 'mock_b']);
});
(0, node_test_1.test)('never fails over on an unknown outcome (no double payout)', async () => {
    const a = new mockProvider_1.MockProvider({ id: 'mock' });
    const b = new mockProvider_1.MockProvider({ id: 'mock_b' });
    const r = await (0, router_1.routePayout)([a, b], req(10092)); // A times out but actually paid
    assert.equal(r.outcome.kind, 'unknown');
    assert.equal(b.calls, 0);
    assert.equal(a.paidCount('ref_1') + b.paidCount('ref_1'), 1);
});
(0, node_test_1.test)('a final refusal stops without trying others', async () => {
    const a = new mockProvider_1.MockProvider({ id: 'mock' });
    const b = new mockProvider_1.MockProvider({ id: 'mock_b' });
    const r = await (0, router_1.routePayout)([a, b], req(10090));
    assert.equal(r.outcome.kind, 'rejected');
    assert.equal(b.calls, 0);
});
(0, node_test_1.test)('retrying the same reference never pays twice', async () => {
    const a = new mockProvider_1.MockProvider();
    await (0, router_1.routePayout)([a], req(5000, 'same'));
    await (0, router_1.routePayout)([a], req(5000, 'same'));
    assert.equal(a.paidCount('same'), 1);
});
(0, node_test_1.test)('invalid amounts are refused before any provider call', async () => {
    const a = new mockProvider_1.MockProvider();
    for (const amt of [0, -5, 10.5, Number.NaN]) {
        const r = await (0, router_1.routePayout)([a], req(amt));
        assert.equal(r.outcome.kind, 'rejected');
    }
    assert.equal(a.calls, 0);
});
(0, node_test_1.test)('circuit breaker skips a provider after repeated failures, then lets it back', async () => {
    const a = new mockProvider_1.MockProvider({ id: 'mock', down: true });
    const b = new mockProvider_1.MockProvider({ id: 'mock_b' });
    let health = {};
    for (let i = 0; i < 3; i++)
        health = (await (0, router_1.routePayout)([a, b], req(10000, `r${i}`), { health, now: 1000, failThreshold: 3 })).health;
    assert.deepEqual((0, router_1.candidates)([a, b], req(1), { health, now: 1001 }).map((p) => p.id), ['mock_b']);
    assert.deepEqual((0, router_1.candidates)([a, b], req(1), { health, now: 1000 + 5 * 60000 }).map((p) => p.id), ['mock', 'mock_b']);
});
(0, node_test_1.test)('preference order picks the cheaper provider first', () => {
    const a = new mockProvider_1.MockProvider({ id: 'mock' });
    const b = new mockProvider_1.MockProvider({ id: 'mock_b' });
    assert.deepEqual((0, router_1.candidates)([a, b], req(1), { preference: ['mock_b', 'mock'] }).map((p) => p.id), ['mock_b', 'mock']);
});
(0, node_test_1.test)('reconcile: unknown payouts settle from the provider status', async () => {
    const a = new mockProvider_1.MockProvider();
    await (0, router_1.routePayout)([a], req(10092, 'late'));
    assert.equal((await a.status('late')).status, 'paid');
    assert.equal((0, router_1.reconcileAction)('paid', 0), 'settle_paid');
    assert.equal((0, router_1.reconcileAction)('failed', 0), 'settle_failed');
    assert.equal((0, router_1.reconcileAction)('pending', 3600000), 'wait');
    assert.equal((0, router_1.reconcileAction)('unknown', 25 * 3600000), 'review');
});
(0, node_test_1.test)('reconcile: not_found refunds only where the provider lookup is reliable', () => {
    assert.equal((0, router_1.reconcileAction)('not_found', 10 * 60000, { notFoundIsFinalAfterMs: 3600000 }), 'wait');
    assert.equal((0, router_1.reconcileAction)('not_found', 2 * 3600000, { notFoundIsFinalAfterMs: 3600000 }), 'settle_failed');
    assert.equal((0, router_1.reconcileAction)('not_found', 2 * 3600000, { notFoundIsFinalAfterMs: null }), 'wait');
    assert.equal((0, router_1.reconcileAction)('not_found', 30 * 3600000, { notFoundIsFinalAfterMs: null }), 'review');
});
const fakeFetch = (status, body) => async () => {
    if (body instanceof Error)
        throw body;
    return { status, text: async () => body };
};
(0, node_test_1.test)('callJson sorts replies into ok / client_error / unknown', async () => {
    assert.equal((await (0, provider_1.callJson)(fakeFetch(200, '{"status":true}'), 'u')).kind, 'ok');
    assert.equal((await (0, provider_1.callJson)(fakeFetch(400, '{"message":"bad account"}'), 'u')).kind, 'client_error');
    assert.equal((await (0, provider_1.callJson)(fakeFetch(502, '{"message":"gateway"}'), 'u')).kind, 'unknown');
    assert.equal((await (0, provider_1.callJson)(fakeFetch(200, '<html>'), 'u')).kind, 'unknown');
    assert.equal((await (0, provider_1.callJson)(fakeFetch(0, new Error('ETIMEDOUT')), 'u')).kind, 'unknown');
});
(0, node_test_1.test)('Paystack: a timeout on the transfer is unknown, a 400 is rejected', async () => {
    const withRecipient = async () => 'RCP_1';
    const timeout = new adapters_1.PaystackProvider('sk_test', fakeFetch(0, new Error('timeout')), withRecipient);
    assert.equal((await timeout.payout(req(10000))).kind, 'unknown');
    const refused = new adapters_1.PaystackProvider('sk_test', fakeFetch(400, '{"status":false,"message":"Insufficient balance"}'), withRecipient);
    assert.deepEqual(await refused.payout(req(10000)), { kind: 'rejected', reason: 'Insufficient balance', retryable: false });
    const notFound = new adapters_1.PaystackProvider('sk_test', fakeFetch(404, '{"status":false,"message":"Transfer not found"}'));
    assert.equal((await notFound.status('x')).status, 'not_found');
});
(0, node_test_1.test)('minor units: integers in, provider decimals out', () => {
    assert.equal((0, provider_1.toMinor)(12.34, 'USD'), 1234);
    assert.equal((0, provider_1.toMinor)(0.1 + 0.2, 'USD'), 30);
    assert.equal((0, provider_1.toMinor)(5000, 'UGX'), 5000);
    assert.equal((0, provider_1.toMajor)(1234, 'USD'), 12.34);
    assert.equal((0, provider_1.toMajor)(5000, 'XOF'), 5000);
    assert.throws(() => (0, provider_1.toMajor)(12.5, 'USD'));
});
//# sourceMappingURL=router.test.js.map