import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { analyzeText, analyzeUrl, extractUrls, looksLikeName, registrableDomain, verdictFor } from '../linkSafety';

test('extracts links with and without a scheme', () => {
  assert.deepEqual(extractUrls('see https://a.com/x, and www.b.org.'), ['https://a.com/x', 'http://www.b.org']);
  assert.deepEqual(extractUrls('go to paypa1-login.xyz now'), ['http://paypa1-login.xyz']);
});

test('official domains are clean', () => {
  assert.equal(analyzeUrl('https://www.paypal.com/signin')!.points, 0);
  assert.equal(analyzeUrl('https://m.facebook.com/x')!.points, 0);
});

test('look-alike and brand-in-host domains are flagged', () => {
  assert.ok(analyzeUrl('https://paypa1.com/login')!.points >= 55);
  assert.ok(analyzeUrl('https://g00gle.com')!.points >= 55);
  assert.ok(analyzeUrl('https://paypal.com.secure-check.xyz')!.points >= 40);
  assert.ok(analyzeUrl('https://xn--pypal-4ve.com')!.points >= 35);
  assert.ok(analyzeUrl('http://192.168.4.1/claim')!.points >= 30);
});

test('ordinary names are not look-alikes', () => {
  assert.ok(analyzeUrl('https://applebees.com')!.points < 40);
  assert.ok(analyzeUrl('https://apply.example.org')!.points < 40);
  assert.equal(registrableDomain('shop.safaricom.co.ke'), 'safaricom.co.ke');
});

test('scam wording plus link is suspicious, normal chat is safe', () => {
  const scam = analyzeText('Congratulations you won! Claim your prize at bit.ly/xyz, just pay a small fee');
  assert.ok(scam.points >= 40, String(scam.points));
  assert.ok(scam.categories.includes('giveaway') && scam.categories.includes('payment'));
  assert.equal(verdictFor(scam.points, false), 'suspicious');
  const ok = analyzeText('See you at 5, the menu is on https://example.com/menu');
  assert.equal(verdictFor(ok.points, false), 'safe');
});

test('known-bad or confident AI verdicts block', () => {
  assert.equal(verdictFor(0, true), 'dangerous');
  assert.equal(verdictFor(30, false, 'phishing', 0.9), 'dangerous');
  assert.equal(verdictFor(30, false, 'phishing', 0.5), 'safe');
});

test('display-name impersonation', () => {
  assert.ok(looksLikeName('0neova Supp0rt', 'Oneova Support'));
  assert.ok(!looksLikeName('Jane Doe', 'Oneova Support'));
});
