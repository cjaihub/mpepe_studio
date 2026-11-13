import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { pickVariant, stockAfterSale, VariantError } from '../commerce/variant_logic';

const shoe = {
  stock: 5,
  variants: [
    { id: 'blue', name: 'Blue', stock: 2 },
    { id: 'white', name: 'White' },
  ],
};

test('a product without variants needs no choice', () => {
  assert.equal(pickVariant({ stock: 3 }, undefined, 1), null);
});

test('a product without variants rejects a variant id', () => {
  assert.throws(() => pickVariant({ stock: 3 }, 'blue', 1), VariantError);
});

test('a product with variants requires a valid choice', () => {
  assert.throws(() => pickVariant(shoe, '', 1), /Choose an option/);
  assert.throws(() => pickVariant(shoe, 'red', 1), /no longer available/);
  assert.equal(pickVariant(shoe, 'blue', 2)?.name, 'Blue');
});

test('variant stock is checked', () => {
  assert.throws(() => pickVariant(shoe, 'blue', 3), /Not enough Blue/);
  assert.equal(pickVariant(shoe, 'white', 20)?.stock, null); // untracked variant stock
});

test('a sale lowers product and variant stock', () => {
  const { update, shortfall } = stockAfterSale(shoe, 'blue', 2);
  assert.equal(shortfall, false);
  assert.equal(update.stock, 3);
  const v = (update.variants as Array<Record<string, unknown>>);
  assert.equal(v[0].stock, 0);
  assert.equal(v[1].stock, undefined);
});

test('selling the last unit marks the product out of stock', () => {
  const { update } = stockAfterSale({ stock: 1 }, null, 1);
  assert.equal(update.stock, 0);
  assert.equal(update.inStock, false);
});

test('overselling never goes below zero and is reported', () => {
  const { update, shortfall } = stockAfterSale({ stock: 1 }, null, 3);
  assert.equal(update.stock, 0);
  assert.equal(shortfall, true);
});

test('untracked stock is left alone', () => {
  const { update, shortfall } = stockAfterSale({ price: 10 }, null, 4);
  assert.deepEqual(update, {});
  assert.equal(shortfall, false);
});
