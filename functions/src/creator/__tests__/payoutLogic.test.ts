import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { canMove, fraudReasons, normalizeMsisdn, payoutFeeUsd, railsFor, roundLocal, usdToDiamonds } from '../payoutLogic';

const all = { flutterwave: true, paystack: true };

test('state machine only moves forward', () => {
  assert.ok(canMove('pending', 'processing'));
  assert.ok(canMove('processing', 'paid'));
  assert.ok(canMove('processing', 'failed'));
  assert.ok(!canMove('paid', 'failed'));
  assert.ok(!canMove('processing', 'cancelled'));
  assert.ok(!canMove('pending', 'paid'));
});

test('rails: Africa gets mobile money and banks, elsewhere none yet', () => {
  const ke = railsFor('KE', all);
  assert.equal(ke[0].rail, 'mobile_money');
  assert.ok(ke[0].networks!.some((n) => n.id === 'MPESA'));
  assert.deepEqual(railsFor('FR', all), []);
  // Paystack only offers its own networks.
  const gh = railsFor('GH', { flutterwave: false, paystack: true });
  assert.equal(gh[0].provider, 'paystack');
  assert.deepEqual(railsFor('UG', { flutterwave: false, paystack: true }), []);
});

test('phone numbers get the dial code', () => {
  assert.equal(normalizeMsisdn('0712 345 678', 'KE'), '254712345678');
  assert.equal(normalizeMsisdn('+254712345678', 'KE'), '254712345678');
  assert.equal(normalizeMsisdn('12', 'KE'), null);
});

test('fees, rounding, conversion', () => {
  assert.equal(payoutFeeUsd('mobile_money', 10), 0.2);
  assert.equal(payoutFeeUsd('mobile_money', 100), 1.5);
  assert.equal(payoutFeeUsd('bank', 100), 1);
  assert.equal(roundLocal(1234.9, 'KES'), 1234);
  assert.equal(roundLocal(12.349, 'GHS'), 12.34);
  assert.equal(usdToDiamonds(10), 1000);
});

test('fraud checks flag risky withdrawals', () => {
  const ok = { amountUsd: 20, accountAgeDays: 30, deviceAgeHours: 400, paidBefore: 2, kycCountry: 'KE', locationCountry: 'KE', payoutCountry: 'KE' };
  assert.deepEqual(fraudReasons(ok), []);
  assert.deepEqual(fraudReasons({ ...ok, deviceAgeHours: 3 }), ['new_device']);
  assert.deepEqual(fraudReasons({ ...ok, locationCountry: 'NG' }), ['location_mismatch']);
  assert.deepEqual(fraudReasons({ ...ok, paidBefore: 0, amountUsd: 800 }), ['large_first_withdrawal']);
});
