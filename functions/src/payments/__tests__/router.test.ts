import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { MockProvider } from '../mockProvider';
import { candidates, reconcileAction, routePayout } from '../router';
import { FetchFn, PayoutRequest, callJson, toMajor, toMinor } from '../provider';
import { PaystackProvider } from '../adapters';

const req = (amountMinor: number, reference = 'ref_1'): PayoutRequest => ({
  reference, country: 'KE', rail: 'mobile_money', currency: 'KES', amountMinor, holderName: 'A B', account: '254700000000', bankCode: 'MPS',
});

test('accepted on the first provider', async () => {
  const a = new MockProvider({ id: 'mock' });
  const r = await routePayout([a], req(10_000));
  assert.equal(r.outcome.kind, 'accepted');
  assert.equal(r.provider, 'mock');
  assert.equal(a.paidCount('ref_1'), 1);
});

test('fails over only when the first provider definitely took nothing', async () => {
  const a = new MockProvider({ id: 'mock', down: true });
  const b = new MockProvider({ id: 'mock_b' });
  const r = await routePayout([a, b], req(10_000));
  assert.equal(r.outcome.kind, 'accepted');
  assert.equal(r.provider, 'mock_b');
  assert.deepEqual(r.attempts.map((x) => x.provider), ['mock', 'mock_b']);
});

test('never fails over on an unknown outcome (no double payout)', async () => {
  const a = new MockProvider({ id: 'mock' });
  const b = new MockProvider({ id: 'mock_b' });
  const r = await routePayout([a, b], req(10_092)); // A times out but actually paid
  assert.equal(r.outcome.kind, 'unknown');
  assert.equal(b.calls, 0);
  assert.equal(a.paidCount('ref_1') + b.paidCount('ref_1'), 1);
});

test('a final refusal stops without trying others', async () => {
  const a = new MockProvider({ id: 'mock' });
  const b = new MockProvider({ id: 'mock_b' });
  const r = await routePayout([a, b], req(10_090));
  assert.equal(r.outcome.kind, 'rejected');
  assert.equal(b.calls, 0);
});

test('retrying the same reference never pays twice', async () => {
  const a = new MockProvider();
  await routePayout([a], req(5_000, 'same'));
  await routePayout([a], req(5_000, 'same'));
  assert.equal(a.paidCount('same'), 1);
});

test('invalid amounts are refused before any provider call', async () => {
  const a = new MockProvider();
  for (const amt of [0, -5, 10.5, Number.NaN]) {
    const r = await routePayout([a], req(amt));
    assert.equal(r.outcome.kind, 'rejected');
  }
  assert.equal(a.calls, 0);
});

test('circuit breaker skips a provider after repeated failures, then lets it back', async () => {
  const a = new MockProvider({ id: 'mock', down: true });
  const b = new MockProvider({ id: 'mock_b' });
  let health = {};
  for (let i = 0; i < 3; i++) health = (await routePayout([a, b], req(10_000, `r${i}`), { health, now: 1000, failThreshold: 3 })).health;
  assert.deepEqual(candidates([a, b], req(1), { health, now: 1001 }).map((p) => p.id), ['mock_b']);
  assert.deepEqual(candidates([a, b], req(1), { health, now: 1000 + 5 * 60_000 }).map((p) => p.id), ['mock', 'mock_b']);
});

test('preference order picks the cheaper provider first', () => {
  const a = new MockProvider({ id: 'mock' });
  const b = new MockProvider({ id: 'mock_b' });
  assert.deepEqual(candidates([a, b], req(1), { preference: ['mock_b', 'mock'] }).map((p) => p.id), ['mock_b', 'mock']);
});

test('reconcile: unknown payouts settle from the provider status', async () => {
  const a = new MockProvider();
  await routePayout([a], req(10_092, 'late'));
  assert.equal((await a.status('late')).status, 'paid');
  assert.equal(reconcileAction('paid', 0), 'settle_paid');
  assert.equal(reconcileAction('failed', 0), 'settle_failed');
  assert.equal(reconcileAction('pending', 3600_000), 'wait');
  assert.equal(reconcileAction('unknown', 25 * 3600_000), 'review');
});

test('reconcile: not_found refunds only where the provider lookup is reliable', () => {
  assert.equal(reconcileAction('not_found', 10 * 60_000, { notFoundIsFinalAfterMs: 3600_000 }), 'wait');
  assert.equal(reconcileAction('not_found', 2 * 3600_000, { notFoundIsFinalAfterMs: 3600_000 }), 'settle_failed');
  assert.equal(reconcileAction('not_found', 2 * 3600_000, { notFoundIsFinalAfterMs: null }), 'wait');
  assert.equal(reconcileAction('not_found', 30 * 3600_000, { notFoundIsFinalAfterMs: null }), 'review');
});

const fakeFetch = (status: number, body: string | Error): FetchFn => async () => {
  if (body instanceof Error) throw body;
  return { status, text: async () => body };
};

test('callJson sorts replies into ok / client_error / unknown', async () => {
  assert.equal((await callJson(fakeFetch(200, '{"status":true}'), 'u')).kind, 'ok');
  assert.equal((await callJson(fakeFetch(400, '{"message":"bad account"}'), 'u')).kind, 'client_error');
  assert.equal((await callJson(fakeFetch(502, '{"message":"gateway"}'), 'u')).kind, 'unknown');
  assert.equal((await callJson(fakeFetch(200, '<html>'), 'u')).kind, 'unknown');
  assert.equal((await callJson(fakeFetch(0, new Error('ETIMEDOUT')), 'u')).kind, 'unknown');
});

test('Paystack: a timeout on the transfer is unknown, a 400 is rejected', async () => {
  const withRecipient = async () => 'RCP_1';
  const timeout = new PaystackProvider('sk_test', fakeFetch(0, new Error('timeout')), withRecipient);
  assert.equal((await timeout.payout(req(10_000))).kind, 'unknown');
  const refused = new PaystackProvider('sk_test', fakeFetch(400, '{"status":false,"message":"Insufficient balance"}'), withRecipient);
  assert.deepEqual(await refused.payout(req(10_000)), { kind: 'rejected', reason: 'Insufficient balance', retryable: false });
  const notFound = new PaystackProvider('sk_test', fakeFetch(404, '{"status":false,"message":"Transfer not found"}'));
  assert.equal((await notFound.status('x')).status, 'not_found');
});

test('minor units: integers in, provider decimals out', () => {
  assert.equal(toMinor(12.34, 'USD'), 1234);
  assert.equal(toMinor(0.1 + 0.2, 'USD'), 30);
  assert.equal(toMinor(5000, 'UGX'), 5000);
  assert.equal(toMajor(1234, 'USD'), 12.34);
  assert.equal(toMajor(5000, 'XOF'), 5000);
  assert.throws(() => toMajor(12.5, 'USD'));
});
