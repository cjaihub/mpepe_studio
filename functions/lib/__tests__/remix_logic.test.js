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
const remix_logic_1 = require("../remix_logic");
const gift_logic_1 = require("../liveStudio/gift_logic");
(0, node_test_1.test)('100-coin gift on a remix: platform 20, original 20, remixer 60', () => {
    const creator = Math.ceil(100 * gift_logic_1.HOST_SHARE);
    const s = (0, remix_logic_1.splitRemixCoins)(creator);
    assert.equal(creator, 80);
    assert.deepEqual(s, { remixerCoins: 60, originalCoins: 20 });
    assert.equal(remix_logic_1.REMIX_ORIGINAL_SHARE, 0.25);
});
(0, node_test_1.test)('small gifts never lose coins and still reach the remixer', () => {
    for (const c of [0, 1, 2, 3, 7, 999]) {
        const s = (0, remix_logic_1.splitRemixCoins)(c);
        assert.equal(s.remixerCoins + s.originalCoins, c);
        if (c > 0)
            assert.ok(s.remixerCoins >= 1);
    }
});
(0, node_test_1.test)('remix permission follows allowRemix, then allowDuet', () => {
    const base = { authorId: 'a', visibility: 'public' };
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign(Object.assign({}, base), { permissions: { allowRemix: true } }), 'b', 'a'), { ok: true });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign(Object.assign({}, base), { permissions: { allowRemix: false } }), 'b', 'a'), { ok: false, reason: 'not_allowed' });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign(Object.assign({}, base), { permissions: { allowDuet: false } }), 'b', 'a'), { ok: false, reason: 'not_allowed' });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign({}, base), 'b', 'a'), { ok: true });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign({}, base), 'a', 'a'), { ok: false, reason: 'own_post' });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign(Object.assign({}, base), { visibility: 'private' }), 'b', 'a'), { ok: false, reason: 'not_public' });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(Object.assign({}, base), 'b', 'x'), { ok: false, reason: 'bad_request' });
    assert.deepEqual((0, remix_logic_1.remixAllowed)(undefined, 'b', 'a'), { ok: false, reason: 'missing' });
});
//# sourceMappingURL=remix_logic.test.js.map