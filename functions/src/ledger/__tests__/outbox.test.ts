import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { isPermanent, nextDelayMs, outboxId, send } from '../outbox';

test('backoff doubles from 1 minute and caps at 6 hours', () => {
  assert.equal(nextDelayMs(1), 60_000);
  assert.equal(nextDelayMs(3), 240_000);
  assert.equal(nextDelayMs(30), 6 * 3600_000);
});

test('only "won\'t ever work" errors stop retries', () => {
  assert.ok(isPermanent(400));
  assert.ok(isPermanent(409)); // same key, different journal: a person must look
  assert.ok(!isPermanent(422)); // insufficient funds: an earlier movement may still be on its way
  assert.ok(!isPermanent(429));
  assert.ok(!isPermanent(503));
});

test('outbox id is stable per key', () => {
  assert.equal(outboxId('play_abc'), outboxId('play_abc'));
  assert.notEqual(outboxId('play_abc'), outboxId('play_abd'));
});

// Contract test against a running ledger: LEDGER_URL=http://localhost:8099 npm run test:pay
test('functions and the Python ledger agree on every template', { skip: !process.env.LEDGER_URL }, async () => {
  const run = Date.now().toString(36);
  const steps: [string, Record<string, unknown>][] = [
    ['coin_purchase', { uid: `a${run}`, coins: 700, debt_paid: 0, order_id: null }],
    ['gift', { sender: `a${run}`, coins: 100, receiver: `b${run}`, receiver_diamonds: 80 }],
    ['release', { uid: `b${run}`, diamonds: 80 }],
    ['withdrawal_lock', { uid: `b${run}`, diamonds: 50, withdrawal_id: 'w1' }],
    ['withdrawal_returned', { uid: `b${run}`, diamonds: 20, withdrawal_id: 'w1' }],
    ['withdrawal_paid', { uid: `b${run}`, diamonds: 30, withdrawal_id: 'w1' }],
    ['coin_void', { uid: `a${run}`, take_from_balance: 600, add_debt: 100, order_id: null }],
    ['payout_cash', { uid: `b${run}`, withdrawal_id: 'w1', currency: 'USD', gross_minor: 1500, rail: 'mobile_money', country: 'KE', partner: 'flutterwave' }],
    ['biz_order_paid', { order_id: `o${run}`, currency: 'KES', total_minor: 170000 }],
    ['biz_order_release', { order_id: `o${run}`, currency: 'KES', items_minor: 150000, seller: `s${run}`, delivery_minor: 20000, rider: `r${run}` }],
  ];
  for (const [i, [template, args]] of steps.entries()) {
    const r = await send(template, `contract_${run}_${i}`, args);
    assert.equal(r.status, 200, `${template}: ${JSON.stringify(r.body)}`);
  }
  const again = await send('coin_purchase', `contract_${run}_0`, steps[0][1]);
  assert.equal(again.body.replayed, true);
});
