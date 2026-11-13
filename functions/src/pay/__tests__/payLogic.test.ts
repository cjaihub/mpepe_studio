import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { PayConfig, balancePayoutFee, canMoveIntent, ledgerBalanced, methodsFor, orderSplit } from '../payLogic';

const off: PayConfig = { sandbox: false, wallet: false, mpesa: false, momo: false, flutterwave: false, paystack: false };

test('no partner keys: no ways to pay', () => {
  assert.deepEqual(methodsFor('KE', off), []);
});

test('sandbox: every rail, served by the sandbox', () => {
  const m = methodsFor('KE', { ...off, sandbox: true, wallet: true });
  assert.equal(m[0].id, 'balance');
  assert.ok(m.some((x) => x.id === 'momo:MPESA' && x.provider === 'sandbox' && x.sandbox));
  assert.ok(m.some((x) => x.id === 'card' && x.provider === 'sandbox'));
});

test('real partners win over the sandbox, by country', () => {
  const ke = methodsFor('KE', { ...off, sandbox: true, mpesa: true, flutterwave: true });
  assert.equal(ke.find((x) => x.id === 'momo:MPESA')!.provider, 'mpesa');
  assert.equal(ke.find((x) => x.id === 'momo:AIRTEL')!.provider, 'flutterwave');
  assert.equal(ke.find((x) => x.id === 'card')!.kind, 'hosted');
  const ug = methodsFor('UG', { ...off, momo: true });
  assert.equal(ug.find((x) => x.id === 'momo:MTN')!.provider, 'mtn_momo');
  assert.equal(ug.find((x) => x.id === 'momo:AIRTEL'), undefined);
  // M-Pesa keys only open M-Pesa in Kenya.
  assert.equal(methodsFor('TZ', { ...off, mpesa: true }).length, 0);
});

test('intent states: late approvals still count, finals stay final', () => {
  assert.ok(canMoveIntent('pending_payer', 'succeeded'));
  assert.ok(canMoveIntent('expired', 'succeeded'));
  assert.ok(canMoveIntent('cancelled', 'succeeded'));
  assert.ok(!canMoveIntent('failed', 'succeeded'));
  assert.ok(!canMoveIntent('refunded', 'succeeded'));
  assert.ok(canMoveIntent('succeeded', 'refunded'));
});

test('ledger postings must balance per currency', () => {
  assert.ok(ledgerBalanced([{ account: 'a', currency: 'KES', amountMinor: -500 }, { account: 'b', currency: 'KES', amountMinor: 500 }]));
  assert.ok(!ledgerBalanced([{ account: 'a', currency: 'KES', amountMinor: -500 }, { account: 'b', currency: 'UGX', amountMinor: 500 }]));
  assert.ok(!ledgerBalanced([{ account: 'a', currency: 'KES', amountMinor: 1.5 }, { account: 'b', currency: 'KES', amountMinor: -1.5 }]));
  assert.ok(!ledgerBalanced([]));
});

test('order split sums exactly to the total', () => {
  const s = orderSplit(999_999, 15_000, 10);
  assert.equal(s.platform, 99_999);
  assert.equal(s.seller + s.rider + s.platform, s.total);
  assert.equal(orderSplit(100, 0, 99).platform, 50); // commission capped at 50%
  assert.throws(() => orderSplit(1.5, 0, 10));
});

test('balance payout fees round up to the platform', () => {
  assert.equal(balancePayoutFee('mobile_money', 10_000), 150);
  assert.equal(balancePayoutFee('bank', 101), 2);
});

test('live deals: active, scoped, rounded per currency', async () => {
  const { liveDealFor, dealPrice } = await import('../../commerce/orderEscrow');
  const ts = (ms: number) => ({ toMillis: () => ms });
  const now = 1_000_000;
  assert.deepEqual(liveDealFor({ title: 'Flash', percentOff: 20, endsAt: ts(now + 1), productIds: [] }, 'p1', now), { title: 'Flash', percentOff: 20 });
  assert.equal(liveDealFor({ percentOff: 20, endsAt: ts(now), productIds: [] }, 'p1', now), null); // ended
  assert.equal(liveDealFor({ percentOff: 20, endsAt: ts(now + 1), productIds: ['p2'] }, 'p1', now), null); // other product
  assert.equal(liveDealFor({ percentOff: 90, endsAt: ts(now + 1) }, 'p1', now), null); // out of range
  assert.equal(dealPrice(9999, 20, 'KES'), 7999.2);
  assert.equal(dealPrice(12.99, 15, 'USD'), 11.04);
  assert.equal(dealPrice(999, 20, 'UGX'), 799);
});
