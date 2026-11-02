import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as crypto from 'crypto';
import { decryptWith, encryptWith } from '../gmailUser';

const k = crypto.randomBytes(32);
const token = '1//0refresh-token-example';

test('round-trips a refresh token for the same user', () => {
  const blob = encryptWith(k, token, 'uidA');
  assert.ok(blob.startsWith('v2.'));
  assert.ok(!blob.includes(token));
  assert.equal(decryptWith(k, blob, 'uidA'), token);
});

test('every encryption uses a fresh IV', () => {
  assert.notEqual(encryptWith(k, token, 'uidA'), encryptWith(k, token, 'uidA'));
});

test('a blob copied to another user does not decrypt', () => {
  const blob = encryptWith(k, token, 'uidA');
  assert.throws(() => decryptWith(k, blob, 'uidB'));
});

test('a different key does not decrypt', () => {
  const blob = encryptWith(k, token, 'uidA');
  assert.throws(() => decryptWith(crypto.randomBytes(32), blob, 'uidA'));
});

test('tampered ciphertext is rejected', () => {
  const parts = encryptWith(k, token, 'uidA').split('.');
  const data = Buffer.from(parts[3], 'base64');
  data[0] ^= 0xff;
  parts[3] = data.toString('base64');
  assert.throws(() => decryptWith(k, parts.join('.'), 'uidA'));
});

test('reads blobs in the original iv.tag.data format', () => {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', k, iv);
  const enc = Buffer.concat([c.update(token, 'utf8'), c.final()]);
  const legacy = [iv, c.getAuthTag(), enc].map((b) => b.toString('base64')).join('.');
  assert.equal(decryptWith(k, legacy, 'anyUid'), token);
});

