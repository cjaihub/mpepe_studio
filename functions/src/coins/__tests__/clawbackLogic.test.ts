import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { clawbackPlan, creditWithDebt, giftRecipients } from '../clawbackLogic';
import { giftId } from '../../liveStudio/gift_logic';

test('refund taken from balance first, the rest becomes debt', () => {
  assert.deepEqual(clawbackPlan(1000, 700), { takeFromBalance: 700, addDebt: 0 });
  assert.deepEqual(clawbackPlan(200, 700), { takeFromBalance: 200, addDebt: 500 });
  assert.deepEqual(clawbackPlan(-5, 70), { takeFromBalance: 0, addDebt: 70 });
});

test('a new pack pays the debt first', () => {
  assert.deepEqual(creditWithDebt(350, 500), { credit: 0, debtPaid: 350 });
  assert.deepEqual(creditWithDebt(700, 500), { credit: 200, debtPaid: 500 });
  assert.deepEqual(creditWithDebt(70, 0), { credit: 70, debtPaid: 0 });
});

test('gift recipients since the purchase, summed', () => {
  const r = giftRecipients([
    { type: 'user_gift_sent', toUid: 'a', amount: -100, createdAtMs: 2000 },
    { type: 'live_gift_sent', toUid: 'a', amount: -50, createdAtMs: 3000 },
    { type: 'live_gift_sent', toUid: 'b', amount: -10, createdAtMs: 500 }, // before the purchase
    { type: 'coin_purchase', amount: 700, createdAtMs: 2500 },
  ], 1000);
  assert.deepEqual([...r.entries()], [['a', 150]]);
});

test('gift id: same requestId gives the same id; bad ones fall back', () => {
  assert.equal(giftId('u1', 'abcd1234-ef', 1), giftId('u1', 'abcd1234-ef', 999));
  assert.notEqual(giftId('u1', 'short', 1), giftId('u1', 'short', 2));
  assert.notEqual(giftId('u1', 'bad/../id-xxxxxx', 1), 'u1_rbad/../id-xxxxxx');
});
