import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import {
  canonicalJson, deviceCanApprove, proofPayload, serialKey, stepUpUsable, verifyAndroidAttestation, verifySignature,
  NEW_DEVICE_COOL_DOWN_MS, STEP_UP_WINDOW_MS,
} from '../devicesLogic';

// Test-only certificates and key made by an openssl script (fake root, never used anywhere else).
const FIX = path.join(__dirname, '../../../src/pay/__tests__/fixtures');
const read = (f: string) => fs.readFileSync(path.join(FIX, f));
const der = (f: string) => new crypto.X509Certificate(read(f)).raw;
const root = read('root.pem').toString();
const otherRoot = read('other_root.pem').toString();
const leafPub = read('leaf_pub.der');
const leafKey = crypto.createPrivateKey(read('leaf.key'));
const challenge = Buffer.from(read('challenge.txt').toString().trim(), 'base64url');

function check(leaf: string, over: Partial<Parameters<typeof verifyAndroidAttestation>[0]> = {}) {
  return verifyAndroidAttestation({
    chain: [der(leaf), der('root.pem')], publicKey: leafPub, challenge, rootPems: [root], revokedSerials: new Set(), ...over,
  });
}

test('canonical JSON sorts keys and drops spaces', () => {
  assert.equal(canonicalJson({ b: 1, a: { d: [1, 'x'], c: null } }), '{"a":{"c":null,"d":[1,"x"]},"b":1}');
});

test('a P-256 signature from the device key verifies; a changed payload does not', () => {
  const payload = proofPayload({ purpose: 'verify', uid: 'u1', challengeId: 'c'.repeat(20), challenge: 'abc', deviceId: 'd'.repeat(20) });
  const sig = crypto.sign('sha256', payload, { key: leafKey, dsaEncoding: 'der' });
  assert.equal(verifySignature(leafPub, payload, sig), true);
  assert.equal(verifySignature(leafPub, Buffer.concat([payload, Buffer.from(' ')]), sig), false);
  assert.equal(verifySignature(leafPub, payload, Buffer.from('nope-nope')), false);
});

test('a non-P-256 key is refused', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const spki = publicKey.export({ type: 'spki', format: 'der' });
  const sig = crypto.sign(null, Buffer.from('x'), privateKey);
  assert.equal(verifySignature(spki, Buffer.from('x'), sig), false);
});

test('hardware attestation: good chain passes as TEE, StrongBox is recognised', () => {
  assert.deepEqual(check('leaf_good.pem'), { ok: true, hardware: 'tee' });
  assert.deepEqual(check('leaf_strongbox.pem'), { ok: true, hardware: 'strongbox' });
});

test('hardware attestation refuses every bad case', () => {
  const reason = (r: ReturnType<typeof check>) => (r.ok ? 'ok' : r.reason);
  assert.equal(reason(check('leaf_software.pem')), 'software_key');
  assert.equal(reason(check('leaf_noauth.pem')), 'no_user_auth');
  assert.equal(reason(check('leaf_wrongpkg.pem')), 'wrong_app');
  assert.equal(reason(check('leaf_wrongchallenge.pem')), 'challenge_mismatch');
  assert.equal(reason(check('leaf_good.pem', { rootPems: [otherRoot] })), 'unknown_root');
  assert.equal(reason(check('leaf_otherroot.pem')), 'chain_signature');
  assert.equal(reason(check('leaf_good.pem', { publicKey: crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).publicKey.export({ type: 'spki', format: 'der' }) })), 'key_mismatch');
  assert.equal(reason(check('leaf_good.pem', { chain: [der('leaf_good.pem')] })), 'chain_length');
  const serial = serialKey(new crypto.X509Certificate(read('leaf_good.pem')).serialNumber);
  assert.equal(reason(check('leaf_good.pem', { revokedSerials: new Set([serial]) })), 'revoked');
});

test('serials match Google status list format', () => {
  assert.equal(serialKey('00AB12'), 'ab12');
  assert.equal(serialKey('0'), '0');
});

test('devices approve only when trusted, not revoked, and large amounts wait out the cool-down', () => {
  const now = 1_000_000_000;
  assert.equal(deviceCanApprove({ trustedAt: null }, now, false).reason, 'not_trusted');
  assert.equal(deviceCanApprove({ trustedAt: 1, revokedAt: 2 }, now, false).reason, 'revoked');
  const cooling = { trustedAt: now, coolDownUntil: now + NEW_DEVICE_COOL_DOWN_MS };
  assert.equal(deviceCanApprove(cooling, now + 1000, false).ok, true);
  assert.equal(deviceCanApprove(cooling, now + 1000, true).reason, 'cool_down');
  assert.equal(deviceCanApprove(cooling, now + NEW_DEVICE_COOL_DOWN_MS + 1, true).ok, true);
});

test('a step-up is fresh, single-use per device trust', () => {
  const now = 5_000_000_000;
  assert.equal(stepUpUsable(null, null, now), false);
  assert.equal(stepUpUsable(now - 1000, null, now), true);
  assert.equal(stepUpUsable(now - STEP_UP_WINDOW_MS - 1, null, now), false);
  assert.equal(stepUpUsable(now - 1000, now - 500, now), false); // already spent
  assert.equal(stepUpUsable(now - 1000, now - 5000, now), true);
});
