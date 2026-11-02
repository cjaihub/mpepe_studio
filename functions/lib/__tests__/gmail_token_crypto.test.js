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
const gmailUser_1 = require("../gmailUser");
const k = crypto.randomBytes(32);
const token = '1//0refresh-token-example';
(0, node_test_1.test)('round-trips a refresh token for the same user', () => {
    const blob = (0, gmailUser_1.encryptWith)(k, token, 'uidA');
    assert.ok(blob.startsWith('v2.'));
    assert.ok(!blob.includes(token));
    assert.equal((0, gmailUser_1.decryptWith)(k, blob, 'uidA'), token);
});
(0, node_test_1.test)('every encryption uses a fresh IV', () => {
    assert.notEqual((0, gmailUser_1.encryptWith)(k, token, 'uidA'), (0, gmailUser_1.encryptWith)(k, token, 'uidA'));
});
(0, node_test_1.test)('a blob copied to another user does not decrypt', () => {
    const blob = (0, gmailUser_1.encryptWith)(k, token, 'uidA');
    assert.throws(() => (0, gmailUser_1.decryptWith)(k, blob, 'uidB'));
});
(0, node_test_1.test)('a different key does not decrypt', () => {
    const blob = (0, gmailUser_1.encryptWith)(k, token, 'uidA');
    assert.throws(() => (0, gmailUser_1.decryptWith)(crypto.randomBytes(32), blob, 'uidA'));
});
(0, node_test_1.test)('tampered ciphertext is rejected', () => {
    const parts = (0, gmailUser_1.encryptWith)(k, token, 'uidA').split('.');
    const data = Buffer.from(parts[3], 'base64');
    data[0] ^= 0xff;
    parts[3] = data.toString('base64');
    assert.throws(() => (0, gmailUser_1.decryptWith)(k, parts.join('.'), 'uidA'));
});
(0, node_test_1.test)('reads blobs in the original iv.tag.data format', () => {
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv('aes-256-gcm', k, iv);
    const enc = Buffer.concat([c.update(token, 'utf8'), c.final()]);
    const legacy = [iv, c.getAuthTag(), enc].map((b) => b.toString('base64')).join('.');
    assert.equal((0, gmailUser_1.decryptWith)(k, legacy, 'anyUid'), token);
});
//# sourceMappingURL=gmail_token_crypto.test.js.map