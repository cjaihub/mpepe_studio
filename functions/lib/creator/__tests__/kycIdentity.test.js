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
const kycIdentity_1 = require("../kycIdentity");
(0, node_test_1.test)('ID numbers are normalised and short or junk ones refused', () => {
    assert.equal((0, kycIdentity_1.normalizeIdNumber)(' ab 12-345 '), 'AB12345');
    assert.equal((0, kycIdentity_1.normalizeIdNumber)('12'), null);
    assert.equal((0, kycIdentity_1.normalizeIdNumber)(42), null);
});
(0, node_test_1.test)('the hash depends on the pepper and every part of the ID', () => {
    const a = (0, kycIdentity_1.idHash)('pepper', 'ke', 'id_card', 'AB12345');
    assert.equal(a, (0, kycIdentity_1.idHash)('pepper', 'KE', 'id_card', 'AB12345'));
    assert.notEqual(a, (0, kycIdentity_1.idHash)('other', 'KE', 'id_card', 'AB12345'));
    assert.notEqual(a, (0, kycIdentity_1.idHash)('pepper', 'UG', 'id_card', 'AB12345'));
    assert.notEqual(a, (0, kycIdentity_1.idHash)('pepper', 'KE', 'passport', 'AB12345'));
    assert.match(a, /^[0-9a-f]{64}$/);
});
(0, node_test_1.test)('one ID, one person, plus accounts the owner linked', () => {
    assert.equal((0, kycIdentity_1.idStatusFor)(undefined, 'u1'), 'new');
    assert.equal((0, kycIdentity_1.idStatusFor)({ primaryUid: 'u1' }, 'u1'), 'same');
    assert.equal((0, kycIdentity_1.idStatusFor)({ primaryUid: 'u1', linkedUids: ['u2'] }, 'u2'), 'linked');
    assert.equal((0, kycIdentity_1.idStatusFor)({ primaryUid: 'u1', linkedUids: ['u2'] }, 'u3'), 'duplicate');
});
//# sourceMappingURL=kycIdentity.test.js.map