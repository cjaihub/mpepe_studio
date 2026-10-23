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
const media_logic_1 = require("../media_logic");
(0, node_test_1.test)('publishing roles get cam/mic/screen and no data', () => {
    for (const r of ['host', 'coHost', 'guest']) {
        const g = (0, media_logic_1.grantForRole)(r, 'studio_x');
        assert.equal(g.room, 'studio_x');
        assert.equal(g.roomJoin, true);
        assert.equal(g.canSubscribe, true);
        assert.equal(g.canPublish, true, r);
        assert.deepEqual(g.canPublishSources, ['camera', 'microphone', 'screen_share']);
        assert.equal(g.canPublishData, false);
    }
});
(0, node_test_1.test)('viewer subscribes only', () => {
    const g = (0, media_logic_1.grantForRole)('viewer', 'studio_x');
    assert.equal(g.canSubscribe, true);
    assert.equal(g.canPublish, false);
    assert.deepEqual(g.canPublishSources, []);
    assert.equal(g.canPublishData, false);
    assert.equal(g.canUpdateOwnMetadata, false);
});
(0, node_test_1.test)('grant sources are a fresh copy per call', () => {
    const a = (0, media_logic_1.grantForRole)('host', 'r');
    a.canPublishSources.pop();
    assert.equal((0, media_logic_1.grantForRole)('host', 'r').canPublishSources.length, 3);
});
(0, node_test_1.test)('ttl ~6h, empty timeout ~10min', () => {
    assert.equal(media_logic_1.TOKEN_TTL_SECONDS, 21600);
    assert.equal(media_logic_1.ROOM_EMPTY_TIMEOUT_SECONDS, 600);
});
(0, node_test_1.test)('token refused for blocked users and ended streams', () => {
    assert.deepEqual((0, media_logic_1.tokenDecision)({ status: 'live', blocked: false }), { ok: true });
    assert.deepEqual((0, media_logic_1.tokenDecision)({ status: 'preparing', blocked: false }), { ok: true });
    const ended = (0, media_logic_1.tokenDecision)({ status: 'ended', blocked: false });
    assert.equal(ended.ok, false);
    assert.equal(!ended.ok && ended.code, 'failed-precondition');
    const blocked = (0, media_logic_1.tokenDecision)({ status: 'live', blocked: true });
    assert.equal(!blocked.ok && blocked.code, 'permission-denied');
});
(0, node_test_1.test)('initial state: host centered, empty wall, goods table, live', () => {
    const s = (0, media_logic_1.buildInitialState)({ streamId: 's1', hostId: 'h', title: 'T', settings: (0, contracts_1.defaultSettings)(), nowMs: 5 });
    assert.equal(s.status, 'live');
    assert.equal(s.seq, 0);
    assert.equal(s.stage.centerUid, 'h');
    assert.equal(s.stage.wall.length, contracts_1.Limits.wallSlots);
    assert.ok(s.stage.wall.every((w) => w === null));
    assert.equal(s.stage.updatedBy, 'h');
    assert.equal(s.table.mode, 'goods');
    assert.equal(s.counts.participants, 1);
});
(0, node_test_1.test)('host member gets accent 0 and role host', () => {
    const m = (0, media_logic_1.buildHostMember)('h', { displayName: 'Ana', avatarUrl: 'a' }, 9);
    assert.equal(m.role, 'host');
    assert.equal(m.accent, contracts_1.ACCENT_PALETTE[0]);
    assert.equal(m.micOn && m.camOn, true);
});
(0, node_test_1.test)('stream doc carries v1-required and v2 marker fields', () => {
    const d = (0, media_logic_1.buildStreamDoc)({ streamId: 's', hostId: 'h', title: 'T', profile: { displayName: 'A', avatarUrl: '' } });
    assert.equal(d.hostId, 'h');
    assert.equal(d.status, 'live');
    assert.equal(d.layoutMode, 'studio');
    assert.equal(d.studioVersion, 2);
    assert.equal(d.audienceMode, 'public');
});
(0, node_test_1.test)('profile falls back across user fields and token', () => {
    assert.deepEqual((0, media_logic_1.profileFrom)({ displayName: 'D', avatarUrl: 'x' }), { displayName: 'D', avatarUrl: 'x' });
    assert.deepEqual((0, media_logic_1.profileFrom)({ username: 'u', photoUrl: 'p' }), { displayName: 'u', avatarUrl: 'p' });
    assert.deepEqual((0, media_logic_1.profileFrom)(undefined, { name: 'n', picture: 'q' }), { displayName: 'n', avatarUrl: 'q' });
    assert.equal((0, media_logic_1.profileFrom)(undefined).displayName.length > 0, true);
});
(0, node_test_1.test)('start settings: argument overrides saved, non-objects ignored', () => {
    assert.deepEqual((0, media_logic_1.mergeStartSettings)({ theme: 'light', frameWidth: 3 }, { frameWidth: 8 }), { theme: 'light', frameWidth: 8 });
    assert.deepEqual((0, media_logic_1.mergeStartSettings)(undefined, 'x'), {});
    assert.deepEqual((0, media_logic_1.mergeStartSettings)([1], null), {});
});
function stateWith(wall, overflow = []) {
    const s = (0, media_logic_1.buildInitialState)({ streamId: 's', hostId: 'h', title: 'T', settings: (0, contracts_1.defaultSettings)(), nowMs: 0 });
    return Object.assign(Object.assign({}, s), { stage: Object.assign(Object.assign({}, s.stage), { wall, overflow }) });
}
(0, node_test_1.test)('own media only for publishing roles on stage', () => {
    const s = stateWith(['g1', null, null, null, null, null], ['o1']);
    assert.deepEqual((0, media_logic_1.stagePublishers)(s), ['h', 'g1', 'o1']);
    assert.equal((0, media_logic_1.canSetOwnMedia)('host', 'h', s), true);
    assert.equal((0, media_logic_1.canSetOwnMedia)('guest', 'g1', s), true);
    assert.equal((0, media_logic_1.canSetOwnMedia)('guest', 'o1', s), true);
    assert.equal((0, media_logic_1.canSetOwnMedia)('guest', 'g2', s), false);
    assert.equal((0, media_logic_1.canSetOwnMedia)('viewer', 'g1', s), false);
});
(0, node_test_1.test)('parseOwnMedia requires both booleans', () => {
    assert.deepEqual((0, media_logic_1.parseOwnMedia)({ micOn: false, camOn: true }), { micOn: false, camOn: true });
    assert.equal((0, media_logic_1.parseOwnMedia)({ micOn: 'no', camOn: true }), null);
    assert.equal((0, media_logic_1.parseOwnMedia)(null), null);
});
(0, node_test_1.test)('wireState strips Firestore timestamps', () => {
    const w = (0, media_logic_1.wireState)({ seq: 3, updatedAt: { _seconds: 1 }, createdAt: 1 });
    assert.deepEqual(w, { seq: 3 });
});
//# sourceMappingURL=media_logic.test.js.map