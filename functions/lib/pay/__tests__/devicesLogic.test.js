"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert/strict"));
const crypto = __importStar(require("crypto"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const devicesLogic_1 = require("../devicesLogic");
// Test-only certificates and key made by an openssl script (fake root, never used anywhere else).
const FIX = path.join(__dirname, '../../../src/pay/__tests__/fixtures');
const read = (f) => fs.readFileSync(path.join(FIX, f));
const der = (f) => new crypto.X509Certificate(read(f)).raw;
const root = read('root.pem').toString();
const otherRoot = read('other_root.pem').toString();
const leafPub = read('leaf_pub.der');
const leafKey = crypto.createPrivateKey(read('leaf.key'));
const challenge = Buffer.from(read('challenge.txt').toString().trim(), 'base64url');
function check(leaf, over = {}) {
    return (0, devicesLogic_1.verifyAndroidAttestation)(Object.assign({ chain: [der(leaf), der('root.pem')], publicKey: leafPub, challenge, rootPems: [root], revokedSerials: new Set() }, over));
}
(0, node_test_1.test)('canonical JSON sorts keys and drops spaces', () => {
    assert.equal((0, devicesLogic_1.canonicalJson)({ b: 1, a: { d: [1, 'x'], c: null } }), '{"a":{"c":null,"d":[1,"x"]},"b":1}');
});
(0, node_test_1.test)('a P-256 signature from the device key verifies; a changed payload does not', () => {
    const payload = (0, devicesLogic_1.proofPayload)({ purpose: 'verify', uid: 'u1', challengeId: 'c'.repeat(20), challenge: 'abc', deviceId: 'd'.repeat(20) });
    const sig = crypto.sign('sha256', payload, { key: leafKey, dsaEncoding: 'der' });
    assert.equal((0, devicesLogic_1.verifySignature)(leafPub, payload, sig), true);
    assert.equal((0, devicesLogic_1.verifySignature)(leafPub, Buffer.concat([payload, Buffer.from(' ')]), sig), false);
    assert.equal((0, devicesLogic_1.verifySignature)(leafPub, payload, Buffer.from('nope-nope')), false);
});
(0, node_test_1.test)('a non-P-256 key is refused', () => {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
    const spki = publicKey.export({ type: 'spki', format: 'der' });
    const sig = crypto.sign(null, Buffer.from('x'), privateKey);
    assert.equal((0, devicesLogic_1.verifySignature)(spki, Buffer.from('x'), sig), false);
});
(0, node_test_1.test)('hardware attestation: good chain passes as TEE, StrongBox is recognised', () => {
    assert.deepEqual(check('leaf_good.pem'), { ok: true, hardware: 'tee' });
    assert.deepEqual(check('leaf_strongbox.pem'), { ok: true, hardware: 'strongbox' });
});
(0, node_test_1.test)('hardware attestation refuses every bad case', () => {
    const reason = (r) => (r.ok ? 'ok' : r.reason);
    assert.equal(reason(check('leaf_software.pem')), 'software_key');
    assert.equal(reason(check('leaf_noauth.pem')), 'no_user_auth');
    assert.equal(reason(check('leaf_wrongpkg.pem')), 'wrong_app');
    assert.equal(reason(check('leaf_wrongchallenge.pem')), 'challenge_mismatch');
    assert.equal(reason(check('leaf_good.pem', { rootPems: [otherRoot] })), 'unknown_root');
    assert.equal(reason(check('leaf_otherroot.pem')), 'chain_signature');
    assert.equal(reason(check('leaf_good.pem', { publicKey: crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).publicKey.export({ type: 'spki', format: 'der' }) })), 'key_mismatch');
    assert.equal(reason(check('leaf_good.pem', { chain: [der('leaf_good.pem')] })), 'chain_length');
    const serial = (0, devicesLogic_1.serialKey)(new crypto.X509Certificate(read('leaf_good.pem')).serialNumber);
    assert.equal(reason(check('leaf_good.pem', { revokedSerials: new Set([serial]) })), 'revoked');
});
(0, node_test_1.test)('serials match Google status list format', () => {
    assert.equal((0, devicesLogic_1.serialKey)('00AB12'), 'ab12');
    assert.equal((0, devicesLogic_1.serialKey)('0'), '0');
});
(0, node_test_1.test)('devices approve only when trusted, not revoked, and large amounts wait out the cool-down', () => {
    const now = 1000000000;
    assert.equal((0, devicesLogic_1.deviceCanApprove)({ trustedAt: null }, now, false).reason, 'not_trusted');
    assert.equal((0, devicesLogic_1.deviceCanApprove)({ trustedAt: 1, revokedAt: 2 }, now, false).reason, 'revoked');
    const cooling = { trustedAt: now, coolDownUntil: now + devicesLogic_1.NEW_DEVICE_COOL_DOWN_MS };
    assert.equal((0, devicesLogic_1.deviceCanApprove)(cooling, now + 1000, false).ok, true);
    assert.equal((0, devicesLogic_1.deviceCanApprove)(cooling, now + 1000, true).reason, 'cool_down');
    assert.equal((0, devicesLogic_1.deviceCanApprove)(cooling, now + devicesLogic_1.NEW_DEVICE_COOL_DOWN_MS + 1, true).ok, true);
});
(0, node_test_1.test)('a step-up is fresh, single-use per device trust', () => {
    const now = 5000000000;
    assert.equal((0, devicesLogic_1.stepUpUsable)(null, null, now), false);
    assert.equal((0, devicesLogic_1.stepUpUsable)(now - 1000, null, now), true);
    assert.equal((0, devicesLogic_1.stepUpUsable)(now - devicesLogic_1.STEP_UP_WINDOW_MS - 1, null, now), false);
    assert.equal((0, devicesLogic_1.stepUpUsable)(now - 1000, now - 500, now), false); // already spent
    assert.equal((0, devicesLogic_1.stepUpUsable)(now - 1000, now - 5000, now), true);
});
//# sourceMappingURL=devicesLogic.test.js.map