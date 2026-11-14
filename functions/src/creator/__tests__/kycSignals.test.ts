import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { cleanCountrySignals, countryMismatch } from '../kycSignals';

test('only known keys and two-letter codes are kept', () => {
  assert.deepEqual(cleanCountrySignals({ location: 'ke', sim: 'TZ', evil: 'XX', network: 'KEN', phone: 5 }), { location: 'KE', sim: 'TZ' });
  assert.deepEqual(cleanCountrySignals('KE'), {});
  assert.deepEqual(cleanCountrySignals(['KE']), {});
});

test('mismatch uses location first, then network, then SIM', () => {
  assert.equal(countryMismatch('KE', { location: 'KE', sim: 'UG' }), false);
  assert.equal(countryMismatch('KE', { network: 'UG' }), true);
  assert.equal(countryMismatch('KE', { region: 'US' }), false);
  assert.equal(countryMismatch('KE', {}), false);
});
