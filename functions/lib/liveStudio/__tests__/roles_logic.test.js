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
const contracts_1 = require("../contracts");
const roles_logic_1 = require("../roles_logic");
const NOW = 5000000;
const ROLES = ['host', 'coHost', 'guest', 'viewer'];
const stage = (over = {}) => (Object.assign({ centerUid: 'host', wall: [null, null, null, null, null, null], overflow: [], pinnedUid: null, updatedAtMs: 0, updatedBy: '' }, over));
// ─── §6 matrix (actor side), table-driven ────────────────────────────────────
const Y = true, N = false;
// action → [host, coHost, guest, viewer]  (ARCHITECTURE §6)
const MATRIX = {
    requestJoin: [N, N, N, Y],
    cancelRequest: [N, N, N, Y],
    respondRequest: [Y, Y, N, N],
    mute: [Y, Y, N, N],
    removeFromStage: [Y, Y, N, N],
    block: [Y, Y, N, N],
    promoteCoHost: [Y, N, N, N],
    demoteCoHost: [Y, N, N, N],
    leaveStage: [N, Y, Y, N],
};
for (const [action, row] of Object.entries(MATRIX)) {
    for (let i = 0; i < ROLES.length; i++) {
        (0, node_test_1.test)(`§6 ${action} by ${ROLES[i]} → ${row[i] ? 'allowed' : 'denied'}`, () => {
            assert.equal((0, roles_logic_1.actorAllowed)(action, ROLES[i]), row[i]);
        });
    }
}
(0, node_test_1.test)('matrix covers every action', () => {
    assert.deepEqual(Object.keys(roles_logic_1.ACTOR_MATRIX).sort(), Object.keys(MATRIX).sort());
});
const MOD_ROWS = [
    // mute others: host ✅ · coHost ✅ (not the host)
    ['mute', 'host', 'guest', true, 'ok'],
    ['mute', 'host', 'coHost', true, 'ok'],
    ['mute', 'coHost', 'guest', true, 'ok'],
    ['mute', 'coHost', 'coHost', true, 'ok'],
    ['mute', 'coHost', 'host', true, 'permission-denied'],
    ['mute', 'guest', 'guest', true, 'permission-denied'],
    ['mute', 'viewer', 'guest', true, 'permission-denied'],
    ['mute', 'host', 'viewer', false, 'failed-precondition'],
    // remove from stage
    ['removeFromStage', 'host', 'guest', true, 'ok'],
    ['removeFromStage', 'host', 'coHost', true, 'ok'],
    ['removeFromStage', 'coHost', 'guest', true, 'ok'],
    ['removeFromStage', 'coHost', 'host', true, 'permission-denied'],
    ['removeFromStage', 'guest', 'guest', true, 'permission-denied'],
    ['removeFromStage', 'host', 'viewer', false, 'failed-precondition'],
    // block: coHost not the host or co-hosts
    ['block', 'host', 'guest', true, 'ok'],
    ['block', 'host', 'coHost', true, 'ok'],
    ['block', 'host', 'viewer', false, 'ok'],
    ['block', 'coHost', 'guest', true, 'ok'],
    ['block', 'coHost', 'viewer', false, 'ok'],
    ['block', 'coHost', 'coHost', true, 'permission-denied'],
    ['block', 'coHost', 'host', true, 'permission-denied'],
    ['block', 'guest', 'viewer', false, 'permission-denied'],
    ['block', 'viewer', 'viewer', false, 'permission-denied'],
    // promote / demote: host only
    ['promoteCoHost', 'host', 'guest', true, 'ok'],
    ['promoteCoHost', 'host', 'viewer', false, 'failed-precondition'],
    ['promoteCoHost', 'host', 'coHost', true, 'failed-precondition'],
    ['promoteCoHost', 'coHost', 'guest', true, 'permission-denied'],
    ['promoteCoHost', 'guest', 'guest', true, 'permission-denied'],
    ['demoteCoHost', 'host', 'coHost', true, 'ok'],
    ['demoteCoHost', 'host', 'guest', true, 'failed-precondition'],
    ['demoteCoHost', 'coHost', 'coHost', true, 'permission-denied'],
];
for (const [action, actorRole, targetRole, onStage, expected] of MOD_ROWS) {
    (0, node_test_1.test)(`moderate ${action}: ${actorRole} → ${targetRole}${onStage ? ' (on stage)' : ''} = ${expected}`, () => {
        const d = (0, roles_logic_1.authorizeModeration)({
            action, actorUid: 'a', actorRole, targetUid: targetRole === 'host' ? 'host' : 't', targetRole, targetOnStage: onStage,
        });
        assert.equal(d.ok ? 'ok' : d.code, expected);
    });
}
(0, node_test_1.test)('nobody moderates themselves', () => {
    for (const action of roles_logic_1.MODERATION_ACTIONS) {
        const d = (0, roles_logic_1.authorizeModeration)({ action, actorUid: 'x', actorRole: 'host', targetUid: 'x', targetRole: 'guest', targetOnStage: true });
        assert.equal(d.ok, false, action);
    }
});
// ─── Requests ────────────────────────────────────────────────────────────────
(0, node_test_1.test)('requestJoin: viewer on a live stream with requests allowed', () => {
    const base = { role: 'viewer', blocked: false, status: 'live', allowGuestRequests: true };
    assert.equal((0, roles_logic_1.requestJoinDecision)(base).ok, true);
    const code = (o) => {
        const d = (0, roles_logic_1.requestJoinDecision)(Object.assign(Object.assign({}, base), o));
        return d.ok ? 'ok' : d.code;
    };
    assert.equal(code({ blocked: true }), 'permission-denied');
    assert.equal(code({ status: 'ended' }), 'failed-precondition');
    assert.equal(code({ status: 'preparing' }), 'failed-precondition');
    assert.equal(code({ allowGuestRequests: false }), 'failed-precondition');
    for (const r of ['host', 'coHost', 'guest'])
        assert.equal(code({ role: r }), 'failed-precondition');
});
(0, node_test_1.test)('allowGuestRequests defaults to true', () => {
    assert.equal((0, roles_logic_1.allowsGuestRequests)(undefined), true);
    assert.equal((0, roles_logic_1.allowsGuestRequests)({}), true);
    assert.equal((0, roles_logic_1.allowsGuestRequests)({ allowGuestRequests: true }), true);
    assert.equal((0, roles_logic_1.allowsGuestRequests)({ allowGuestRequests: false }), false);
});
(0, node_test_1.test)('cancel only a pending request', () => {
    assert.equal((0, roles_logic_1.cancelDecision)('pending').ok, true);
    for (const s of [null, undefined])
        assert.equal((0, roles_logic_1.cancelDecision)(s).code, 'not-found');
    for (const s of ['approved', 'declined', 'cancelled'])
        assert.equal((0, roles_logic_1.cancelDecision)(s).ok, false);
});
(0, node_test_1.test)('respond: manager, pending, viewer, not blocked', () => {
    const base = { actorRole: 'host', requestStatus: 'pending', targetRole: 'viewer', targetBlocked: false };
    assert.equal((0, roles_logic_1.respondDecision)(base).ok, true);
    assert.equal((0, roles_logic_1.respondDecision)(Object.assign(Object.assign({}, base), { actorRole: 'coHost' })).ok, true);
    assert.equal((0, roles_logic_1.respondDecision)(Object.assign(Object.assign({}, base), { actorRole: 'guest' })).ok, false);
    assert.equal((0, roles_logic_1.respondDecision)(Object.assign(Object.assign({}, base), { requestStatus: 'declined' })).ok, false);
    assert.equal((0, roles_logic_1.respondDecision)(Object.assign(Object.assign({}, base), { requestStatus: null })).ok, false);
    assert.equal((0, roles_logic_1.respondDecision)(Object.assign(Object.assign({}, base), { targetRole: 'guest' })).ok, false);
    assert.equal((0, roles_logic_1.respondDecision)(Object.assign(Object.assign({}, base), { targetBlocked: true })).ok, false);
});
(0, node_test_1.test)('leave: guest and coHost only', () => {
    assert.equal((0, roles_logic_1.leaveDecision)('guest').ok, true);
    assert.equal((0, roles_logic_1.leaveDecision)('coHost').ok, true);
    assert.equal((0, roles_logic_1.leaveDecision)('host').ok, false);
    assert.equal((0, roles_logic_1.leaveDecision)('viewer').ok, false);
});
(0, node_test_1.test)('assertDecision throws RolesError with the code', () => {
    assert.throws(() => (0, roles_logic_1.assertDecision)({ ok: false, code: 'permission-denied', message: 'x' }), (e) => e instanceof roles_logic_1.RolesError && e.code === 'permission-denied');
    assert.doesNotThrow(() => (0, roles_logic_1.assertDecision)({ ok: true }));
});
// ─── Arg parsing ─────────────────────────────────────────────────────────────
(0, node_test_1.test)('parse args', () => {
    assert.deepEqual((0, roles_logic_1.parseRespondArgs)({ uid: 'u', approve: true }), { uid: 'u', approve: true });
    assert.throws(() => (0, roles_logic_1.parseRespondArgs)({ uid: 'u' }), roles_logic_1.RolesError);
    assert.throws(() => (0, roles_logic_1.parseRespondArgs)({ uid: '', approve: true }), roles_logic_1.RolesError);
    assert.throws(() => (0, roles_logic_1.parseRespondArgs)({ uid: 'a/b', approve: true }), roles_logic_1.RolesError);
    assert.deepEqual((0, roles_logic_1.parseModerateArgs)({ uid: 'u', action: 'promoteCoHost' }), { uid: 'u', action: 'promoteCoHost' });
    assert.throws(() => (0, roles_logic_1.parseModerateArgs)({ uid: 'u', action: 'nuke' }), roles_logic_1.RolesError);
    assert.throws(() => (0, roles_logic_1.parseModerateArgs)(null), roles_logic_1.RolesError);
});
// ─── Slot assignment ─────────────────────────────────────────────────────────
(0, node_test_1.test)('placeOnStage: first free wall index', () => {
    const r = (0, roles_logic_1.placeOnStage)(stage({ wall: ['a', null, 'c', null, null, null] }), 'g', NOW, 'host');
    assert.deepEqual(r.placement, { kind: 'wall', index: 1 });
    assert.deepEqual(r.stage.wall, ['a', 'g', 'c', null, null, null]);
    assert.equal(r.stage.updatedAtMs, NOW);
    assert.equal(r.stage.updatedBy, 'host');
});
(0, node_test_1.test)('placeOnStage: overflow when the wall is full', () => {
    const r = (0, roles_logic_1.placeOnStage)(stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1'] }), 'g', NOW, 'host');
    assert.deepEqual(r.placement, { kind: 'overflow' });
    assert.deepEqual(r.stage.overflow, ['o1', 'g']);
});
(0, node_test_1.test)('placeOnStage: already on stage is a no-op', () => {
    const s = stage({ wall: ['g', null, null, null, null, null] });
    const r = (0, roles_logic_1.placeOnStage)(s, 'g', NOW, 'host');
    assert.deepEqual(r.placement, { kind: 'already' });
    assert.equal(r.stage, s);
    assert.deepEqual((0, roles_logic_1.placeOnStage)(s, 'host', NOW, 'x').placement, { kind: 'already' });
});
(0, node_test_1.test)('placeOnStage pads a short wall', () => {
    const r = (0, roles_logic_1.placeOnStage)(stage({ wall: ['a'] }), 'g', NOW, 'host');
    assert.equal(r.stage.wall.length, 6);
    assert.deepEqual(r.placement, { kind: 'wall', index: 1 });
});
// ─── Removal ─────────────────────────────────────────────────────────────────
(0, node_test_1.test)('remove from wall frees the slot and pulls the first overflow in', () => {
    const s = stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1', 'o2'] });
    const r = (0, roles_logic_1.removeFromLayout)(s, 'c', 'host', NOW, 'host');
    assert.deepEqual(r.wall, ['a', 'b', 'o1', 'd', 'e', 'f']);
    assert.deepEqual(r.overflow, ['o2']);
    assert.equal(r.centerUid, 'host');
});
(0, node_test_1.test)('remove from wall without overflow leaves the slot empty', () => {
    const r = (0, roles_logic_1.removeFromLayout)(stage({ wall: ['a', 'b', null, null, null, null] }), 'a', 'host', NOW, 'host');
    assert.deepEqual(r.wall, [null, 'b', null, null, null, null]);
});
(0, node_test_1.test)('remove from overflow', () => {
    const r = (0, roles_logic_1.removeFromLayout)(stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1', 'o2'] }), 'o2', 'host', NOW, 'h');
    assert.deepEqual(r.overflow, ['o1']);
    assert.deepEqual(r.wall, ['a', 'b', 'c', 'd', 'e', 'f']);
});
(0, node_test_1.test)('remove the center: host returns to the center and leaves their wall slot', () => {
    const s = stage({ centerUid: 'g', wall: ['a', 'host', 'c', null, null, null], pinnedUid: 'g' });
    const r = (0, roles_logic_1.removeFromLayout)(s, 'g', 'host', NOW, 'host');
    assert.equal(r.centerUid, 'host');
    assert.deepEqual(r.wall, ['a', null, 'c', null, null, null]);
    assert.equal(r.pinnedUid, null);
    assert.ok(!r.wall.includes('g'));
});
(0, node_test_1.test)('remove the center when the host was in overflow', () => {
    const s = stage({ centerUid: 'g', wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['host', 'o1'] });
    const r = (0, roles_logic_1.removeFromLayout)(s, 'g', 'host', NOW, 'host');
    assert.equal(r.centerUid, 'host');
    assert.deepEqual(r.overflow, ['o1']);
});
(0, node_test_1.test)('remove keeps an unrelated pin; returns undefined when absent', () => {
    const r = (0, roles_logic_1.removeFromLayout)(stage({ wall: ['a', 'b', null, null, null, null], pinnedUid: 'b' }), 'a', 'host', NOW, 'h');
    assert.equal(r.pinnedUid, 'b');
    assert.equal((0, roles_logic_1.removeFromLayout)(stage(), 'nobody', 'host', NOW, 'h'), undefined);
});
// ─── Accent ──────────────────────────────────────────────────────────────────
(0, node_test_1.test)('pickAccent: first palette accent not used by current members', () => {
    const members = [
        { uid: 'host', accent: contracts_1.ACCENT_PALETTE[0], role: 'host', joinedAtMs: 1 },
        { uid: 'a', accent: contracts_1.ACCENT_PALETTE[1], role: 'guest', joinedAtMs: 2 },
        { uid: 'old', accent: contracts_1.ACCENT_PALETTE[2], role: 'viewer', joinedAtMs: 3 }, // left the stage
    ];
    assert.equal((0, roles_logic_1.pickAccent)(members, 'new'), contracts_1.ACCENT_PALETTE[2]);
    assert.equal((0, roles_logic_1.pickAccent)([], 'new'), contracts_1.ACCENT_PALETTE[0]);
});
(0, node_test_1.test)('pickAccent: case-insensitive, ignores the target, cycles when full', () => {
    assert.equal((0, roles_logic_1.pickAccent)([{ uid: 'h', accent: contracts_1.ACCENT_PALETTE[0].toLowerCase(), role: 'host', joinedAtMs: 0 }]), contracts_1.ACCENT_PALETTE[1]);
    assert.equal((0, roles_logic_1.pickAccent)([{ uid: 'me', accent: contracts_1.ACCENT_PALETTE[0], role: 'guest', joinedAtMs: 0 }], 'me'), contracts_1.ACCENT_PALETTE[0]);
    const full = contracts_1.ACCENT_PALETTE.map((accent, i) => ({ uid: `u${i}`, accent, role: 'guest', joinedAtMs: i }));
    assert.equal((0, roles_logic_1.pickAccent)(full, 'x'), contracts_1.ACCENT_PALETTE[full.length % contracts_1.ACCENT_PALETTE.length]);
});
// ─── Members / LiveKit ───────────────────────────────────────────────────────
(0, node_test_1.test)('guest member patch and off-stage patch', () => {
    const m = (0, roles_logic_1.guestMemberPatch)({ uid: 'g', displayName: 'G', avatarUrl: 'u', accent: '#22C3D6', nowMs: NOW });
    assert.equal(m.role, 'guest');
    assert.equal(m.micOn, true);
    assert.equal(m.camOn, true);
    assert.equal(m.joinedAtMs, NOW);
    assert.ok(!('chatMuted' in m));
    assert.deepEqual((0, roles_logic_1.offStagePatch)(), { role: 'viewer', micOn: false, camOn: false });
});
(0, node_test_1.test)('permissions: guest publishes cam/mic/screen, viewer nothing, no data for anyone', () => {
    assert.deepEqual((0, roles_logic_1.permissionForRole)('guest'), {
        canPublish: true, canSubscribe: true, canPublishData: false, canPublishSources: ['camera', 'microphone', 'screen_share'],
    });
    assert.deepEqual((0, roles_logic_1.permissionForRole)('viewer'), {
        canPublish: false, canSubscribe: true, canPublishData: false, canPublishSources: [],
    });
    for (const r of ROLES)
        assert.equal((0, roles_logic_1.permissionForRole)(r).canPublishData, false);
});
(0, node_test_1.test)('micTrackSids picks mic tracks by source or name', () => {
    const sids = (0, roles_logic_1.micTrackSids)([
        { sid: 'TR_cam', source: 1, name: 'cam' },
        { sid: 'TR_mic', source: 2, name: 'x' },
        { sid: 'TR_mic2', source: 0, name: 'mic' },
        { sid: '', source: 2 },
    ], 2);
    assert.deepEqual(sids, ['TR_mic', 'TR_mic2']);
});
//# sourceMappingURL=roles_logic.test.js.map