import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { idHash, idStatusFor, normalizeIdNumber } from '../kycIdentity';

test('ID numbers are normalised and short or junk ones refused', () => {
  assert.equal(normalizeIdNumber(' ab 12-345 '), 'AB12345');
  assert.equal(normalizeIdNumber('12'), null);
  assert.equal(normalizeIdNumber(42), null);
});

test('the hash depends on the pepper and every part of the ID', () => {
  const a = idHash('pepper', 'ke', 'id_card', 'AB12345');
  assert.equal(a, idHash('pepper', 'KE', 'id_card', 'AB12345'));
  assert.notEqual(a, idHash('other', 'KE', 'id_card', 'AB12345'));
  assert.notEqual(a, idHash('pepper', 'UG', 'id_card', 'AB12345'));
  assert.notEqual(a, idHash('pepper', 'KE', 'passport', 'AB12345'));
  assert.match(a, /^[0-9a-f]{64}$/);
});

test('one ID, one person, plus accounts the owner linked', () => {
  assert.equal(idStatusFor(undefined, 'u1'), 'new');
  assert.equal(idStatusFor({ primaryUid: 'u1' }, 'u1'), 'same');
  assert.equal(idStatusFor({ primaryUid: 'u1', linkedUids: ['u2'] }, 'u2'), 'linked');
  assert.equal(idStatusFor({ primaryUid: 'u1', linkedUids: ['u2'] }, 'u3'), 'duplicate');
});
