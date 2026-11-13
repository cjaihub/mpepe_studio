import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { canFulfil, codeDiscount, customizationExtra, nextRating, normalizeCode, priceCustomization, StoreRuleError } from '../commerce/storeLogic';

const shoe = {
  customization: [
    { id: 'sole', label: 'Sole', type: 'choice', required: true, choices: [
      { id: 'white', label: 'White' }, { id: 'gold', label: 'Gold', priceDelta: 5, modelVariant: 'GoldSole' },
    ] },
    { id: 'name', label: 'Engraving', type: 'text', maxLength: 10, priceDelta: 3 },
  ],
};

test('customization: prices choices and text', () => {
  const lines = priceCustomization(shoe, { sole: 'gold', name: 'AMANI' });
  assert.equal(customizationExtra(lines), 8);
  assert.equal(lines[0].modelVariant, 'GoldSole');
});

test('customization: required option and unknown choice are refused', () => {
  assert.throws(() => priceCustomization(shoe, {}), StoreRuleError);
  assert.throws(() => priceCustomization(shoe, { sole: 'red' }), StoreRuleError);
  assert.throws(() => priceCustomization(shoe, { sole: 'white', name: 'X'.repeat(11) }), StoreRuleError);
});

test('customization: client price deltas are ignored', () => {
  const lines = priceCustomization(shoe, { sole: 'white', name: '' });
  assert.equal(customizationExtra(lines), 0);
});

test('codes: percent, amount, limits', () => {
  const now = 1000;
  assert.equal(codeDiscount({ percentOff: 10 }, 200, 'KES', now), 20);
  assert.equal(codeDiscount({ amountOff: 50, currency: 'KES' }, 30, 'KES', now), 30);
  assert.throws(() => codeDiscount({ percentOff: 10, endsAtMs: 900 }, 100, 'KES', now));
  assert.throws(() => codeDiscount({ percentOff: 10, maxUses: 2, uses: 2 }, 100, 'KES', now));
  assert.throws(() => codeDiscount({ percentOff: 10, minSpend: 500 }, 100, 'KES', now));
  assert.throws(() => codeDiscount({ amountOff: 5, currency: 'USD' }, 100, 'KES', now));
  assert.equal(normalizeCode(' live-20 '), 'LIVE20');
});

test('fulfilment moves one step at a time', () => {
  assert.ok(canFulfil(undefined, 'packed'));
  assert.ok(canFulfil('packed', 'ready'));
  assert.ok(!canFulfil('new', 'shipped'));
});

test('rating average', () => {
  assert.deepEqual(nextRating(4, 1, 5), { rating: 4.5, reviewCount: 2 });
  assert.deepEqual(nextRating(undefined, undefined, 9), { rating: 5, reviewCount: 1 });
});
