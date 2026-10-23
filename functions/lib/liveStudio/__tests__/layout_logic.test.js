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
const layout_logic_1 = require("../layout_logic");
const NOW = 1000000;
const stage = (over = {}) => (Object.assign({ centerUid: 'host', wall: ['g1', 'g2', 'g3', 'g4', 'g5', 'g6'], overflow: ['o1'], pinnedUid: null, updatedAtMs: NOW - 10000, updatedBy: 'host' }, over));
const roles = {
    g1: 'guest', g2: 'guest', g3: 'guest', g4: 'guest', g5: 'guest', g6: 'guest', o1: 'guest',
    c1: 'coHost', v1: 'viewer',
};
const ctx = (over = {}) => (Object.assign({ actorUid: 'host', nowMs: NOW, mode: 'hostPinned', hostId: 'host', roles }, over));
const rejects = (fn, code) => assert.throws(fn, (e) => e instanceof layout_logic_1.LayoutError && e.code === code);
(0, node_test_1.test)('parseLayoutOp validates every op', () => {
    assert.deepEqual((0, layout_logic_1.parseLayoutOp)({ op: 'swap', index: 2 }), { op: 'swap', index: 2 });
    assert.deepEqual((0, layout_logic_1.parseLayoutOp)({ op: 'unpin', extra: 1 }), { op: 'unpin' });
    assert.deepEqual((0, layout_logic_1.parseLayoutOp)({ op: 'rotateIn', uid: 'o1', index: 5 }), { op: 'rotateIn', uid: 'o1', index: 5 });
    assert.deepEqual((0, layout_logic_1.parseLayoutOp)({ op: 'setMode', mode: 'manual' }), { op: 'setMode', mode: 'manual' });
    rejects(() => (0, layout_logic_1.parseLayoutOp)({ op: 'swap', index: 6 }), 'invalid-argument');
    rejects(() => (0, layout_logic_1.parseLayoutOp)({ op: 'swap', index: 1.5 }), 'invalid-argument');
    rejects(() => (0, layout_logic_1.parseLayoutOp)({ op: 'pin' }), 'invalid-argument');
    rejects(() => (0, layout_logic_1.parseLayoutOp)({ op: 'setMode', mode: 'loud' }), 'invalid-argument');
    rejects(() => (0, layout_logic_1.parseLayoutOp)({ op: 'rotateIn', uid: 'o1' }), 'invalid-argument');
    rejects(() => (0, layout_logic_1.parseLayoutOp)({ op: 'nuke' }), 'invalid-argument');
});
(0, node_test_1.test)('swap(index) exchanges wall[index] with the center and stamps', () => {
    const r = (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'swap', index: 2 }, ctx({ actorUid: 'c1' }));
    assert.equal(r.stage.centerUid, 'g3');
    assert.equal(r.stage.wall[2], 'host');
    assert.equal(r.stage.updatedAtMs, NOW);
    assert.equal(r.stage.updatedBy, 'c1');
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage({ wall: [null, null, null, null, null, null] }), { op: 'swap', index: 0 }, ctx()), 'failed-precondition');
});
(0, node_test_1.test)('swap rejects uids that are not stage members', () => {
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage({ wall: ['v1', null, null, null, null, null] }), { op: 'swap', index: 0 }, ctx()), 'failed-precondition');
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage({ wall: ['ghost', null, null, null, null, null] }), { op: 'swap', index: 0 }, ctx()), 'failed-precondition');
});
(0, node_test_1.test)('pin moves the person to the center and sets pinnedUid; unpin clears', () => {
    const r = (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'pin', uid: 'g4' }, ctx());
    assert.equal(r.stage.centerUid, 'g4');
    assert.equal(r.stage.wall[3], 'host');
    assert.equal(r.stage.pinnedUid, 'g4');
    const again = (0, layout_logic_1.applyLayoutOp)(r.stage, { op: 'pin', uid: 'g4' }, ctx());
    assert.deepEqual(again, {});
    const pinHost = (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'pin', uid: 'host' }, ctx());
    assert.equal(pinHost.stage.centerUid, 'host');
    assert.equal(pinHost.stage.pinnedUid, 'host');
    const u = (0, layout_logic_1.applyLayoutOp)(r.stage, { op: 'unpin' }, ctx());
    assert.equal(u.stage.pinnedUid, null);
    assert.deepEqual((0, layout_logic_1.applyLayoutOp)(stage(), { op: 'unpin' }, ctx()), {});
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'pin', uid: 'v1' }, ctx()), 'failed-precondition');
});
(0, node_test_1.test)('pin from overflow swaps the center into overflow', () => {
    const r = (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'pin', uid: 'o1' }, ctx());
    assert.equal(r.stage.centerUid, 'o1');
    assert.deepEqual(r.stage.overflow, ['host']);
});
(0, node_test_1.test)('setMode returns the new mode; hostPinned brings the host back', () => {
    assert.deepEqual((0, layout_logic_1.applyLayoutOp)(stage(), { op: 'setMode', mode: 'autoActiveSpeaker' }, ctx()), { mode: 'autoActiveSpeaker' });
    assert.deepEqual((0, layout_logic_1.applyLayoutOp)(stage(), { op: 'setMode', mode: 'hostPinned' }, ctx()), {});
    const away = stage({ centerUid: 'g2', wall: ['g1', 'host', 'g3', 'g4', 'g5', 'g6'] });
    const r = (0, layout_logic_1.applyLayoutOp)(away, { op: 'setMode', mode: 'hostPinned' }, ctx({ mode: 'manual' }));
    assert.equal(r.mode, 'hostPinned');
    assert.equal(r.stage.centerUid, 'host');
    assert.equal(r.stage.wall[1], 'g2');
});
(0, node_test_1.test)('rotateIn swaps an overflow member with the wall occupant', () => {
    const r = (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'rotateIn', uid: 'o1', index: 4 }, ctx());
    assert.equal(r.stage.wall[4], 'o1');
    assert.deepEqual(r.stage.overflow, ['g5']);
    const empty = stage({ wall: ['g1', 'g2', 'g3', 'g4', null, 'g6'] });
    const r2 = (0, layout_logic_1.applyLayoutOp)(empty, { op: 'rotateIn', uid: 'o1', index: 4 }, ctx());
    assert.deepEqual(r2.stage.overflow, []);
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'rotateIn', uid: 'g1', index: 4 }, ctx()), 'failed-precondition');
});
(0, node_test_1.test)('autoPromote: only in auto mode, not pinned, after the 4 s hold', () => {
    const auto = ctx({ mode: 'autoActiveSpeaker' });
    const r = (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'autoPromote', uid: 'g6' }, auto);
    assert.equal(r.stage.centerUid, 'g6');
    assert.equal(r.stage.wall[5], 'host'); // previous center → vacated slot
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'autoPromote', uid: 'g6' }, ctx({ mode: 'hostPinned' })), 'failed-precondition');
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'autoPromote', uid: 'g6' }, ctx({ mode: 'manual' })), 'failed-precondition');
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage({ pinnedUid: 'host' }), { op: 'autoPromote', uid: 'g6' }, auto), 'failed-precondition');
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage({ updatedAtMs: NOW - 3999 }), { op: 'autoPromote', uid: 'g6' }, auto), 'failed-precondition');
    assert.ok((0, layout_logic_1.applyLayoutOp)(stage({ updatedAtMs: NOW - 4000 }), { op: 'autoPromote', uid: 'g6' }, auto).stage);
    assert.deepEqual((0, layout_logic_1.applyLayoutOp)(stage(), { op: 'autoPromote', uid: 'host' }, auto), {});
    rejects(() => (0, layout_logic_1.applyLayoutOp)(stage(), { op: 'autoPromote', uid: 'v1' }, auto), 'failed-precondition');
});
(0, node_test_1.test)('missing wall entries are normalized to 6 slots', () => {
    const r = (0, layout_logic_1.applyLayoutOp)(Object.assign(Object.assign({}, stage()), { wall: ['g1'] }), { op: 'swap', index: 0 }, ctx());
    assert.equal(r.stage.wall.length, 6);
});
(0, node_test_1.test)('authorizeLayoutOp: host/coHost only; autoPromote leader only', () => {
    const ops = [
        { op: 'swap', index: 0 }, { op: 'pin', uid: 'g1' }, { op: 'unpin' },
        { op: 'setMode', mode: 'manual' }, { op: 'rotateIn', uid: 'o1', index: 0 },
    ];
    for (const op of ops) {
        (0, layout_logic_1.authorizeLayoutOp)(op, { uid: 'host', role: 'host' }, null);
        (0, layout_logic_1.authorizeLayoutOp)(op, { uid: 'c1', role: 'coHost' }, null);
        rejects(() => (0, layout_logic_1.authorizeLayoutOp)(op, { uid: 'g1', role: 'guest' }, null), 'permission-denied');
        rejects(() => (0, layout_logic_1.authorizeLayoutOp)(op, { uid: 'v1', role: 'viewer' }, null), 'permission-denied');
    }
    const ap = { op: 'autoPromote', uid: 'g1' };
    (0, layout_logic_1.authorizeLayoutOp)(ap, { uid: 'host', role: 'host' }, 'host');
    rejects(() => (0, layout_logic_1.authorizeLayoutOp)(ap, { uid: 'c1', role: 'coHost' }, 'host'), 'permission-denied');
    (0, layout_logic_1.authorizeLayoutOp)(ap, { uid: 'c1', role: 'coHost' }, 'c1');
    rejects(() => (0, layout_logic_1.authorizeLayoutOp)(ap, { uid: 'g1', role: 'guest' }, 'g1'), 'permission-denied');
});
(0, node_test_1.test)('electLeader mirrors the Dart election', () => {
    const members = [
        { uid: 'c2', role: 'coHost', joinedAtMs: 200 },
        { uid: 'c1', role: 'coHost', joinedAtMs: 100 },
        { uid: 'c0', role: 'coHost', joinedAtMs: 100 },
        { uid: 'g1', role: 'guest', joinedAtMs: 1 },
    ];
    assert.equal((0, layout_logic_1.electLeader)({ hostId: 'host', members, connected: new Set(['host', 'c1']), hostAbsentForMs: null }), 'host');
    assert.equal((0, layout_logic_1.electLeader)({ hostId: 'host', members, connected: new Set(['c1', 'c2']), hostAbsentForMs: 5000 }), null);
    assert.equal((0, layout_logic_1.electLeader)({ hostId: 'host', members, connected: new Set(['c0', 'c1', 'c2']), hostAbsentForMs: 10000 }), 'c0');
    assert.equal((0, layout_logic_1.electLeader)({ hostId: 'host', members, connected: new Set(['c1', 'c2']), hostAbsentForMs: null }), 'c1');
    assert.equal((0, layout_logic_1.electLeader)({ hostId: 'host', members, connected: new Set(['g1']), hostAbsentForMs: null }), null);
});
//# sourceMappingURL=layout_logic.test.js.map