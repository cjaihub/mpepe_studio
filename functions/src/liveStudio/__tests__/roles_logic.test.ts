import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { ACCENT_PALETTE, StageLayout, StudioRole } from '../contracts';
import {
  ACTOR_MATRIX,
  MODERATION_ACTIONS,
  RolesAction,
  RolesError,
  StudioModerationAction,
  actorAllowed,
  allowsGuestRequests,
  assertDecision,
  authorizeModeration,
  cancelDecision,
  guestMemberPatch,
  leaveDecision,
  micTrackSids,
  offStagePatch,
  parseModerateArgs,
  parseRespondArgs,
  permissionForRole,
  pickAccent,
  placeOnStage,
  removeFromLayout,
  requestJoinDecision,
  respondDecision,
  stageCount,
  stageIsFull,
} from '../roles_logic';

const NOW = 5_000_000;
const ROLES: StudioRole[] = ['host', 'coHost', 'guest', 'viewer'];

const stage = (over: Partial<StageLayout> = {}): StageLayout => ({
  centerUid: 'host',
  wall: [null, null, null, null, null, null],
  overflow: [],
  pinnedUid: null,
  updatedAtMs: 0,
  updatedBy: '',
  ...over,
});

// ─── §6 matrix (actor side), table-driven ────────────────────────────────────

const Y = true, N = false;
// action → [host, coHost, guest, viewer]  (ARCHITECTURE §6)
const MATRIX: Record<RolesAction, [boolean, boolean, boolean, boolean]> = {
  requestJoin:     [N, N, N, Y],
  cancelRequest:   [N, N, N, Y],
  respondRequest:  [Y, Y, N, N],
  mute:            [Y, Y, N, N],
  removeFromStage: [Y, Y, N, N],
  block:           [Y, Y, N, N],
  promoteCoHost:   [Y, N, N, N],
  demoteCoHost:    [Y, N, N, N],
  leaveStage:      [N, Y, Y, N],
};

for (const [action, row] of Object.entries(MATRIX) as [RolesAction, boolean[]][]) {
  for (let i = 0; i < ROLES.length; i++) {
    test(`§6 ${action} by ${ROLES[i]} → ${row[i] ? 'allowed' : 'denied'}`, () => {
      assert.equal(actorAllowed(action, ROLES[i]), row[i]);
    });
  }
}

test('matrix covers every action', () => {
  assert.deepEqual(Object.keys(ACTOR_MATRIX).sort(), Object.keys(MATRIX).sort());
});

// ─── §6 target rules for lsModerate, table-driven ────────────────────────────

type Row = [StudioModerationAction, StudioRole /*actor*/, StudioRole /*target*/, boolean /*onStage*/, string /*ok|code*/];
const MOD_ROWS: Row[] = [
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
  test(`moderate ${action}: ${actorRole} → ${targetRole}${onStage ? ' (on stage)' : ''} = ${expected}`, () => {
    const d = authorizeModeration({
      action, actorUid: 'a', actorRole, targetUid: targetRole === 'host' ? 'host' : 't', targetRole, targetOnStage: onStage,
    });
    assert.equal(d.ok ? 'ok' : d.code, expected);
  });
}

test('nobody moderates themselves', () => {
  for (const action of MODERATION_ACTIONS) {
    const d = authorizeModeration({ action, actorUid: 'x', actorRole: 'host', targetUid: 'x', targetRole: 'guest', targetOnStage: true });
    assert.equal(d.ok, false, action);
  }
});

// ─── Requests ────────────────────────────────────────────────────────────────

test('requestJoin: viewer on a live stream with requests allowed', () => {
  const base = { role: 'viewer' as StudioRole, blocked: false, status: 'live' as const, allowGuestRequests: true };
  assert.equal(requestJoinDecision(base).ok, true);
  const code = (o: Partial<typeof base>) => {
    const d = requestJoinDecision({ ...base, ...o });
    return d.ok ? 'ok' : d.code;
  };
  assert.equal(code({ blocked: true }), 'permission-denied');
  assert.equal(code({ status: 'ended' as never }), 'failed-precondition');
  assert.equal(code({ status: 'preparing' as never }), 'failed-precondition');
  assert.equal(code({ allowGuestRequests: false }), 'failed-precondition');
  for (const r of ['host', 'coHost', 'guest'] as StudioRole[]) assert.equal(code({ role: r }), 'failed-precondition');
});

test('allowGuestRequests defaults to true', () => {
  assert.equal(allowsGuestRequests(undefined), true);
  assert.equal(allowsGuestRequests({}), true);
  assert.equal(allowsGuestRequests({ allowGuestRequests: true }), true);
  assert.equal(allowsGuestRequests({ allowGuestRequests: false }), false);
});

test('cancel only a pending request', () => {
  assert.equal(cancelDecision('pending').ok, true);
  for (const s of [null, undefined]) assert.equal((cancelDecision(s) as { code: string }).code, 'not-found');
  for (const s of ['approved', 'declined', 'cancelled'] as const) assert.equal(cancelDecision(s).ok, false);
});

test('respond: manager, pending, viewer, not blocked', () => {
  const base = { actorRole: 'host' as StudioRole, requestStatus: 'pending' as const, targetRole: 'viewer' as StudioRole, targetBlocked: false };
  assert.equal(respondDecision(base).ok, true);
  assert.equal(respondDecision({ ...base, actorRole: 'coHost' }).ok, true);
  assert.equal(respondDecision({ ...base, actorRole: 'guest' }).ok, false);
  assert.equal(respondDecision({ ...base, requestStatus: 'declined' as never }).ok, false);
  assert.equal(respondDecision({ ...base, requestStatus: null as never }).ok, false);
  assert.equal(respondDecision({ ...base, targetRole: 'guest' }).ok, false);
  assert.equal(respondDecision({ ...base, targetBlocked: true }).ok, false);
});

test('leave: guest and coHost only', () => {
  assert.equal(leaveDecision('guest').ok, true);
  assert.equal(leaveDecision('coHost').ok, true);
  assert.equal(leaveDecision('host').ok, false);
  assert.equal(leaveDecision('viewer').ok, false);
});

test('assertDecision throws RolesError with the code', () => {
  assert.throws(() => assertDecision({ ok: false, code: 'permission-denied', message: 'x' }),
    (e: unknown) => e instanceof RolesError && e.code === 'permission-denied');
  assert.doesNotThrow(() => assertDecision({ ok: true }));
});

// ─── Arg parsing ─────────────────────────────────────────────────────────────

test('parse args', () => {
  assert.deepEqual(parseRespondArgs({ uid: 'u', approve: true }), { uid: 'u', approve: true });
  assert.throws(() => parseRespondArgs({ uid: 'u' }), RolesError);
  assert.throws(() => parseRespondArgs({ uid: '', approve: true }), RolesError);
  assert.throws(() => parseRespondArgs({ uid: 'a/b', approve: true }), RolesError);
  assert.deepEqual(parseModerateArgs({ uid: 'u', action: 'promoteCoHost' }), { uid: 'u', action: 'promoteCoHost' });
  assert.throws(() => parseModerateArgs({ uid: 'u', action: 'nuke' }), RolesError);
  assert.throws(() => parseModerateArgs(null), RolesError);
});

// ─── Slot assignment ─────────────────────────────────────────────────────────

test('placeOnStage: first free wall index', () => {
  const r = placeOnStage(stage({ wall: ['a', null, 'c', null, null, null] }), 'g', NOW, 'host');
  assert.deepEqual(r.placement, { kind: 'wall', index: 1 });
  assert.deepEqual(r.stage.wall, ['a', 'g', 'c', null, null, null]);
  assert.equal(r.stage.updatedAtMs, NOW);
  assert.equal(r.stage.updatedBy, 'host');
});

test('placeOnStage: overflow when the wall is full', () => {
  const r = placeOnStage(stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1'] }), 'g', NOW, 'host');
  assert.deepEqual(r.placement, { kind: 'overflow' });
  assert.deepEqual(r.stage.overflow, ['o1', 'g']);
});

test('stage cap: 10 people (host + 6 wall + 3 overflow), then full', () => {
  const nine = stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1', 'o2'] });
  assert.equal(stageCount(nine), 9);
  assert.equal(stageIsFull(nine), false);
  const ten = placeOnStage(nine, 'o3', NOW, 'host').stage;
  assert.equal(stageCount(ten), 10);
  assert.equal(stageIsFull(ten), true);
  assert.throws(() => placeOnStage(ten, 'g', NOW, 'host'), (e: unknown) =>
    e instanceof RolesError && e.code === 'failed-precondition');
  // Someone already on a full stage stays a no-op.
  assert.deepEqual(placeOnStage(ten, 'a', NOW, 'host').placement, { kind: 'already' });
});

test('requestJoinDecision: refused when the stage is full', () => {
  const base = { role: 'viewer' as StudioRole, blocked: false, status: 'live' as const, allowGuestRequests: true };
  assert.equal(requestJoinDecision({ ...base, onStage: 9 }).ok, true);
  const d = requestJoinDecision({ ...base, onStage: 10 });
  assert.equal(d.ok, false);
  assert.equal(!d.ok && d.code, 'failed-precondition');
});

test('placeOnStage: already on stage is a no-op', () => {
  const s = stage({ wall: ['g', null, null, null, null, null] });
  const r = placeOnStage(s, 'g', NOW, 'host');
  assert.deepEqual(r.placement, { kind: 'already' });
  assert.equal(r.stage, s);
  assert.deepEqual(placeOnStage(s, 'host', NOW, 'x').placement, { kind: 'already' });
});

test('placeOnStage pads a short wall', () => {
  const r = placeOnStage(stage({ wall: ['a'] }), 'g', NOW, 'host');
  assert.equal(r.stage.wall.length, 6);
  assert.deepEqual(r.placement, { kind: 'wall', index: 1 });
});

// ─── Removal ─────────────────────────────────────────────────────────────────

test('remove from wall frees the slot and pulls the first overflow in', () => {
  const s = stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1', 'o2'] });
  const r = removeFromLayout(s, 'c', 'host', NOW, 'host')!;
  assert.deepEqual(r.wall, ['a', 'b', 'o1', 'd', 'e', 'f']);
  assert.deepEqual(r.overflow, ['o2']);
  assert.equal(r.centerUid, 'host');
});

test('remove from wall without overflow leaves the slot empty', () => {
  const r = removeFromLayout(stage({ wall: ['a', 'b', null, null, null, null] }), 'a', 'host', NOW, 'host')!;
  assert.deepEqual(r.wall, [null, 'b', null, null, null, null]);
});

test('remove from overflow', () => {
  const r = removeFromLayout(stage({ wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['o1', 'o2'] }), 'o2', 'host', NOW, 'h')!;
  assert.deepEqual(r.overflow, ['o1']);
  assert.deepEqual(r.wall, ['a', 'b', 'c', 'd', 'e', 'f']);
});

test('remove the center: host returns to the center and leaves their wall slot', () => {
  const s = stage({ centerUid: 'g', wall: ['a', 'host', 'c', null, null, null], pinnedUid: 'g' });
  const r = removeFromLayout(s, 'g', 'host', NOW, 'host')!;
  assert.equal(r.centerUid, 'host');
  assert.deepEqual(r.wall, ['a', null, 'c', null, null, null]);
  assert.equal(r.pinnedUid, null);
  assert.ok(!r.wall.includes('g'));
});

test('remove the center when the host was in overflow', () => {
  const s = stage({ centerUid: 'g', wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['host', 'o1'] });
  const r = removeFromLayout(s, 'g', 'host', NOW, 'host')!;
  assert.equal(r.centerUid, 'host');
  assert.deepEqual(r.overflow, ['o1']);
});

test('remove keeps an unrelated pin; returns undefined when absent', () => {
  const r = removeFromLayout(stage({ wall: ['a', 'b', null, null, null, null], pinnedUid: 'b' }), 'a', 'host', NOW, 'h')!;
  assert.equal(r.pinnedUid, 'b');
  assert.equal(removeFromLayout(stage(), 'nobody', 'host', NOW, 'h'), undefined);
});

// ─── Accent ──────────────────────────────────────────────────────────────────

test('pickAccent: first palette accent not used by current members', () => {
  const members = [
    { uid: 'host', accent: ACCENT_PALETTE[0], role: 'host' as StudioRole, joinedAtMs: 1 },
    { uid: 'a', accent: ACCENT_PALETTE[1], role: 'guest' as StudioRole, joinedAtMs: 2 },
    { uid: 'old', accent: ACCENT_PALETTE[2], role: 'viewer' as StudioRole, joinedAtMs: 3 }, // left the stage
  ];
  assert.equal(pickAccent(members, 'new'), ACCENT_PALETTE[2]);
  assert.equal(pickAccent([], 'new'), ACCENT_PALETTE[0]);
});

test('pickAccent: case-insensitive, ignores the target, cycles when full', () => {
  assert.equal(pickAccent([{ uid: 'h', accent: ACCENT_PALETTE[0].toLowerCase(), role: 'host', joinedAtMs: 0 }]), ACCENT_PALETTE[1]);
  assert.equal(pickAccent([{ uid: 'me', accent: ACCENT_PALETTE[0], role: 'guest', joinedAtMs: 0 }], 'me'), ACCENT_PALETTE[0]);
  const full = ACCENT_PALETTE.map((accent, i) => ({ uid: `u${i}`, accent, role: 'guest' as StudioRole, joinedAtMs: i }));
  assert.equal(pickAccent(full, 'x'), ACCENT_PALETTE[full.length % ACCENT_PALETTE.length]);
});

// ─── Members / LiveKit ───────────────────────────────────────────────────────

test('guest member patch and off-stage patch', () => {
  const m = guestMemberPatch({ uid: 'g', displayName: 'G', avatarUrl: 'u', accent: '#22C3D6', nowMs: NOW });
  assert.equal(m.role, 'guest');
  assert.equal(m.micOn, true);
  assert.equal(m.camOn, true);
  assert.equal(m.joinedAtMs, NOW);
  assert.ok(!('chatMuted' in m));
  assert.deepEqual(offStagePatch(), { role: 'viewer', micOn: false, camOn: false });
});

test('permissions: guest publishes cam/mic/screen, viewer nothing, no data for anyone', () => {
  assert.deepEqual(permissionForRole('guest'), {
    canPublish: true, canSubscribe: true, canPublishData: false, canPublishSources: ['camera', 'microphone', 'screen_share'],
  });
  assert.deepEqual(permissionForRole('viewer'), {
    canPublish: false, canSubscribe: true, canPublishData: false, canPublishSources: [],
  });
  for (const r of ROLES) assert.equal(permissionForRole(r).canPublishData, false);
});

test('micTrackSids picks mic tracks by source or name', () => {
  const sids = micTrackSids([
    { sid: 'TR_cam', source: 1, name: 'cam' },
    { sid: 'TR_mic', source: 2, name: 'x' },
    { sid: 'TR_mic2', source: 0, name: 'mic' },
    { sid: '', source: 2 },
  ], 2);
  assert.deepEqual(sids, ['TR_mic', 'TR_mic2']);
});
