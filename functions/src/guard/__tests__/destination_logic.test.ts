import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { defaultLabel, firstPartyRoute, parseDestination } from '../../feed/destination_logic';

test('product id wins and maps to checkout', () => {
  const r = parseDestination({ productId: 'abc_123', url: 'https://x.com' });
  assert.ok(r.ok);
  if (r.ok) {
    assert.equal(r.value.kind, 'product');
    assert.equal(r.value.route, '/biz/checkout/abc_123');
  }
  assert.equal(parseDestination({ productId: '../x' }).ok, false);
});

test('web links are normalised to https', () => {
  const r = parseDestination({ url: 'shop.example.com/item?id=4' });
  assert.ok(r.ok);
  if (r.ok) {
    assert.equal(r.value.kind, 'web');
    assert.equal(r.value.url, 'https://shop.example.com/item?id=4');
    assert.equal(r.value.host, 'shop.example.com');
  }
  const h = parseDestination({ url: 'http://example.org' });
  assert.ok(h.ok && h.value.url === 'https://example.org/');
});

test('dangerous shapes are rejected', () => {
  for (const url of ['javascript:alert(1)', 'data:text/html,hi', 'intent://x', 'https://user:pw@bank.com', 'http://localhost:3000',
    'https://192.168.1.4/', 'https://10.0.0.1', 'ftp://example.com', 'https://nodot', 'has space.com', '']) {
    assert.equal(parseDestination({ url }).ok, false, url);
  }
  assert.equal(parseDestination({ url: `https://a.com/${'x'.repeat(600)}` }).ok, false);
});

test('first-party links open in the app', () => {
  const r = parseDestination({ url: 'https://oneova.web.app/product/p1' });
  assert.ok(r.ok && r.value.kind === 'product' && r.value.route === '/biz/checkout/p1');
  assert.equal(firstPartyRoute('/shop')?.route, '/biz_feed');
  assert.equal(firstPartyRoute('/live/s1')?.route, '/live/viewer/s1');
  assert.equal(firstPartyRoute('/profile/u1')?.route, '/profile/u1');
  const other = parseDestination({ url: 'https://oneova.web.app/deletion' });
  assert.ok(other.ok && other.value.kind === 'web');
});

test('labels', () => {
  assert.equal(defaultLabel('web', 'www.nike.com'), 'nike.com');
  assert.equal(defaultLabel('product', null, 'Red sneakers'), 'Red sneakers');
  assert.equal(parseDestination({ url: 'a.com', label: '  Buy\u0000 now  ' }).ok, true);
});
