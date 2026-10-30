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
const fun_logic_1 = require("../fun_logic");
const broadcast_logic_1 = require("../broadcast_logic");
(0, node_test_1.test)('poll validation and voting', () => {
    const p = (0, fun_logic_1.newPoll)({ question: ' Best song? ', options: ['A', 'B', 'C'], seconds: 30 }, 'p1', 1000);
    assert.equal(p.question, 'Best song?');
    assert.deepEqual(p.counts, [0, 0, 0]);
    assert.equal(p.endsAtMs, 31000);
    assert.ok((0, fun_logic_1.pollAccepting)(p, 5000));
    assert.ok(!(0, fun_logic_1.pollAccepting)(p, 31000));
    let q = (0, fun_logic_1.applyVote)(p, null, 1);
    q = (0, fun_logic_1.applyVote)(q, 1, 2);
    assert.deepEqual(q.counts, [0, 0, 1]);
    assert.throws(() => (0, fun_logic_1.applyVote)(q, null, 3), fun_logic_1.FunError);
    assert.throws(() => (0, fun_logic_1.newPoll)({ question: 'x', options: ['a'] }, 'p', 0), fun_logic_1.FunError);
    assert.throws(() => (0, fun_logic_1.newPoll)({ question: 'x', options: ['a', 'A'] }, 'p', 0), fun_logic_1.FunError);
    assert.equal((0, fun_logic_1.newPoll)({ question: 'x', options: ['a', 'b'], seconds: 1 }, 'p', 0).endsAtMs, 15000);
});
(0, node_test_1.test)('timer and ops', () => {
    const t = (0, fun_logic_1.newTimer)({ seconds: 99999 }, 0);
    assert.equal(t.label, 'Countdown');
    assert.equal(t.endsAtMs, 3600000);
    assert.equal((0, fun_logic_1.parseOp)('celebrate'), 'celebrate');
    assert.throws(() => (0, fun_logic_1.parseOp)('nuke'), fun_logic_1.FunError);
});
(0, node_test_1.test)('raffle picks distinct recent commenters, never the host', () => {
    var _a;
    const now = 20 * 60 * 1000;
    const c = (uid, ts) => ({ uid, name: uid, avatarUrl: '', ts });
    const e = (0, fun_logic_1.raffleEntrants)([c('h', now), c('a', now), c('a', now - 1), c('b', now - 5000), c('old', 0)], now, ['h']);
    assert.deepEqual(e.map((x) => x.uid), ['a', 'b']);
    assert.equal((_a = (0, fun_logic_1.pickWinner)(e, 0.99)) === null || _a === void 0 ? void 0 : _a.uid, 'b');
    assert.equal((0, fun_logic_1.pickWinner)([], 0.5), null);
});
(0, node_test_1.test)('destinations validate, default ingest and mask the key', () => {
    const d = (0, broadcast_logic_1.parseDestination)({ platform: 'youtube', key: 'abcd-1234' }, 'd1');
    assert.equal((0, broadcast_logic_1.ingestUrl)(d), 'rtmp://a.rtmp.youtube.com/live2/abcd-1234');
    assert.equal((0, broadcast_logic_1.masked)(d).keyHint, '••••1234');
    assert.equal('key' in (0, broadcast_logic_1.masked)(d), false);
    const tt = (0, broadcast_logic_1.parseDestination)({ platform: 'tiktok', url: 'rtmp://push.tiktok.com/live/', key: 'k1', label: 'My TikTok' }, 'd2');
    assert.equal((0, broadcast_logic_1.ingestUrl)(tt), 'rtmp://push.tiktok.com/live/k1');
    assert.throws(() => (0, broadcast_logic_1.parseDestination)({ platform: 'tiktok', key: 'k' }, 'x'), broadcast_logic_1.BroadcastError);
    assert.throws(() => (0, broadcast_logic_1.parseDestination)({ platform: 'custom', url: 'http://x', key: 'k' }, 'x'), broadcast_logic_1.BroadcastError);
    assert.throws(() => (0, broadcast_logic_1.parseDestination)({ platform: 'youtube', key: 'a b' }, 'x'), broadcast_logic_1.BroadcastError);
    assert.equal((0, broadcast_logic_1.recordingPath)('h', 's'), 'users/h/files/live_recordings/s.mp4');
});
const gift_logic_1 = require("../gift_logic");
(0, node_test_1.test)('gifts: catalog prices, quantity limits, host share, recent list', () => {
    assert.deepEqual((0, gift_logic_1.parseGift)({ giftId: 'rose' }), { giftId: 'rose', qty: 1 });
    assert.throws(() => (0, gift_logic_1.parseGift)({ giftId: 'car' }), gift_logic_1.GiftError);
    assert.throws(() => (0, gift_logic_1.parseGift)({ giftId: 'rose', qty: 0 }), gift_logic_1.GiftError);
    assert.throws(() => (0, gift_logic_1.parseGift)({ giftId: 'rose', qty: 1.5 }), gift_logic_1.GiftError);
    assert.deepEqual((0, gift_logic_1.giftPrice)('crown', 3), { total: 150, hostCoins: 75 });
    assert.deepEqual((0, gift_logic_1.giftPrice)('rose', 1), { total: 1, hostCoins: 0 });
    const g = { id: 'x', uid: 'u', name: 'n', avatarUrl: '', giftId: 'rose', qty: 1, coins: 1, atMs: 0 };
    let list = undefined;
    for (let i = 0; i < 20; i++)
        list = (0, gift_logic_1.pushRecent)(list, Object.assign(Object.assign({}, g), { id: `g${i}` }));
    assert.equal(list.length, 15);
    assert.equal(list[0].id, 'g19');
});
//# sourceMappingURL=fun_broadcast_logic.test.js.map