import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { StageLayout, StudioRole } from '../contracts';
import {
  LayoutContext,
  LayoutError,
  LayoutOp,
  applyLayoutOp,
  authorizeLayoutOp,
  electLeader,
  parseLayoutOp,
} from '../layout_logic';

const NOW = 1_000_000;

const stage = (over: Partial<StageLayout> = {}): StageLayout => ({
  centerUid: 'host',
  wall: ['g1', 'g2', 'g3', 'g4', 'g5', 'g6'],
  overflow: ['o1'],
  pinnedUid: null,
  updatedAtMs: NOW - 10_000,
  updatedBy: 'host',
  ...over,
});

const roles: Record<string, StudioRole> = {
  g1: 'guest', g2: 'guest', g3: 'guest', g4: 'guest', g5: 'guest', g6: 'guest', o1: 'guest',
  c1: 'coHost', v1: 'viewer',
};

const ctx = (over: Partial<LayoutContext> = {}): LayoutContext => ({
  actorUid: 'host', nowMs: NOW, mode: 'hostPinned', hostId: 'host', roles, ...over,
});

const rejects = (fn: () => unknown, code: string) =>
  assert.throws(fn, (e: unknown) => e instanceof LayoutError && e.code === code);

test('parseLayoutOp validates every op', () => {
  assert.deepEqual(parseLayoutOp({ op: 'swap', index: 2 }), { op: 'swap', index: 2 });
  assert.deepEqual(parseLayoutOp({ op: 'unpin', extra: 1 }), { op: 'unpin' });
  assert.deepEqual(parseLayoutOp({ op: 'rotateIn', uid: 'o1', index: 5 }), { op: 'rotateIn', uid: 'o1', index: 5 });
  assert.deepEqual(parseLayoutOp({ op: 'setMode', mode: 'manual' }), { op: 'setMode', mode: 'manual' });
  rejects(() => parseLayoutOp({ op: 'swap', index: 6 }), 'invalid-argument');
  rejects(() => parseLayoutOp({ op: 'swap', index: 1.5 }), 'invalid-argument');
  rejects(() => parseLayoutOp({ op: 'pin' }), 'invalid-argument');
  rejects(() => parseLayoutOp({ op: 'setMode', mode: 'loud' }), 'invalid-argument');
  rejects(() => parseLayoutOp({ op: 'rotateIn', uid: 'o1' }), 'invalid-argument');
  rejects(() => parseLayoutOp({ op: 'nuke' }), 'invalid-argument');
});

test('swap(index) exchanges wall[index] with the center and stamps', () => {
  const r = applyLayoutOp(stage(), { op: 'swap', index: 2 }, ctx({ actorUid: 'c1' }));
  assert.equal(r.stage!.centerUid, 'g3');
  assert.equal(r.stage!.wall[2], 'host');
  assert.equal(r.stage!.updatedAtMs, NOW);
  assert.equal(r.stage!.updatedBy, 'c1');
  rejects(() => applyLayoutOp(stage({ wall: [null, null, null, null, null, null] }), { op: 'swap', index: 0 }, ctx()), 'failed-precondition');
});

test('swap rejects uids that are not stage members', () => {
  rejects(() => applyLayoutOp(stage({ wall: ['v1', null, null, null, null, null] }), { op: 'swap', index: 0 }, ctx()), 'failed-precondition');
  rejects(() => applyLayoutOp(stage({ wall: ['ghost', null, null, null, null, null] }), { op: 'swap', index: 0 }, ctx()), 'failed-precondition');
});

test('pin moves the person to the center and sets pinnedUid; unpin clears', () => {
  const r = applyLayoutOp(stage(), { op: 'pin', uid: 'g4' }, ctx());
  assert.equal(r.stage!.centerUid, 'g4');
  assert.equal(r.stage!.wall[3], 'host');
  assert.equal(r.stage!.pinnedUid, 'g4');
  const again = applyLayoutOp(r.stage!, { op: 'pin', uid: 'g4' }, ctx());
  assert.deepEqual(again, {});
  const pinHost = applyLayoutOp(stage(), { op: 'pin', uid: 'host' }, ctx());
  assert.equal(pinHost.stage!.centerUid, 'host');
  assert.equal(pinHost.stage!.pinnedUid, 'host');
  const u = applyLayoutOp(r.stage!, { op: 'unpin' }, ctx());
  assert.equal(u.stage!.pinnedUid, null);
  assert.deepEqual(applyLayoutOp(stage(), { op: 'unpin' }, ctx()), {});
  rejects(() => applyLayoutOp(stage(), { op: 'pin', uid: 'v1' }, ctx()), 'failed-precondition');
});

test('pin from overflow swaps the center into overflow', () => {
  const r = applyLayoutOp(stage(), { op: 'pin', uid: 'o1' }, ctx());
  assert.equal(r.stage!.centerUid, 'o1');
  assert.deepEqual(r.stage!.overflow, ['host']);
});

test('setMode returns the new mode; hostPinned brings the host back', () => {
  assert.deepEqual(applyLayoutOp(stage(), { op: 'setMode', mode: 'autoActiveSpeaker' }, ctx()), { mode: 'autoActiveSpeaker' });
  assert.deepEqual(applyLayoutOp(stage(), { op: 'setMode', mode: 'hostPinned' }, ctx()), {});
  const away = stage({ centerUid: 'g2', wall: ['g1', 'host', 'g3', 'g4', 'g5', 'g6'] });
  const r = applyLayoutOp(away, { op: 'setMode', mode: 'hostPinned' }, ctx({ mode: 'manual' }));
  assert.equal(r.mode, 'hostPinned');
  assert.equal(r.stage!.centerUid, 'host');
  assert.equal(r.stage!.wall[1], 'g2');
});

test('rotateIn swaps an overflow member with the wall occupant', () => {
  const r = applyLayoutOp(stage(), { op: 'rotateIn', uid: 'o1', index: 4 }, ctx());
  assert.equal(r.stage!.wall[4], 'o1');
  assert.deepEqual(r.stage!.overflow, ['g5']);
  const empty = stage({ wall: ['g1', 'g2', 'g3', 'g4', null, 'g6'] });
  const r2 = applyLayoutOp(empty, { op: 'rotateIn', uid: 'o1', index: 4 }, ctx());
  assert.deepEqual(r2.stage!.overflow, []);
  rejects(() => applyLayoutOp(stage(), { op: 'rotateIn', uid: 'g1', index: 4 }, ctx()), 'failed-precondition');
});

test('autoPromote: only in auto mode, not pinned, after the 4 s hold', () => {
  const auto = ctx({ mode: 'autoActiveSpeaker' });
  const r = applyLayoutOp(stage(), { op: 'autoPromote', uid: 'g6' }, auto);
  assert.equal(r.stage!.centerUid, 'g6');
  assert.equal(r.stage!.wall[5], 'host'); // previous center → vacated slot
  rejects(() => applyLayoutOp(stage(), { op: 'autoPromote', uid: 'g6' }, ctx({ mode: 'hostPinned' })), 'failed-precondition');
  rejects(() => applyLayoutOp(stage(), { op: 'autoPromote', uid: 'g6' }, ctx({ mode: 'manual' })), 'failed-precondition');
  rejects(() => applyLayoutOp(stage({ pinnedUid: 'host' }), { op: 'autoPromote', uid: 'g6' }, auto), 'failed-precondition');
  rejects(() => applyLayoutOp(stage({ updatedAtMs: NOW - 3999 }), { op: 'autoPromote', uid: 'g6' }, auto), 'failed-precondition');
  assert.ok(applyLayoutOp(stage({ updatedAtMs: NOW - 4000 }), { op: 'autoPromote', uid: 'g6' }, auto).stage);
  assert.deepEqual(applyLayoutOp(stage(), { op: 'autoPromote', uid: 'host' }, auto), {});
  rejects(() => applyLayoutOp(stage(), { op: 'autoPromote', uid: 'v1' }, auto), 'failed-precondition');
});

test('missing wall entries are normalized to 6 slots', () => {
  const r = applyLayoutOp({ ...stage(), wall: ['g1'] }, { op: 'swap', index: 0 }, ctx());
  assert.equal(r.stage!.wall.length, 6);
});

test('authorizeLayoutOp: host/coHost only; autoPromote leader only', () => {
  const ops: LayoutOp[] = [
    { op: 'swap', index: 0 }, { op: 'pin', uid: 'g1' }, { op: 'unpin' },
    { op: 'setMode', mode: 'manual' }, { op: 'rotateIn', uid: 'o1', index: 0 },
  ];
  for (const op of ops) {
    authorizeLayoutOp(op, { uid: 'host', role: 'host' }, null);
    authorizeLayoutOp(op, { uid: 'c1', role: 'coHost' }, null);
    rejects(() => authorizeLayoutOp(op, { uid: 'g1', role: 'guest' }, null), 'permission-denied');
    rejects(() => authorizeLayoutOp(op, { uid: 'v1', role: 'viewer' }, null), 'permission-denied');
  }
  const ap: LayoutOp = { op: 'autoPromote', uid: 'g1' };
  authorizeLayoutOp(ap, { uid: 'host', role: 'host' }, 'host');
  rejects(() => authorizeLayoutOp(ap, { uid: 'c1', role: 'coHost' }, 'host'), 'permission-denied');
  authorizeLayoutOp(ap, { uid: 'c1', role: 'coHost' }, 'c1');
  rejects(() => authorizeLayoutOp(ap, { uid: 'g1', role: 'guest' }, 'g1'), 'permission-denied');
});

test('electLeader mirrors the Dart election', () => {
  const members = [
    { uid: 'c2', role: 'coHost' as StudioRole, joinedAtMs: 200 },
    { uid: 'c1', role: 'coHost' as StudioRole, joinedAtMs: 100 },
    { uid: 'c0', role: 'coHost' as StudioRole, joinedAtMs: 100 },
    { uid: 'g1', role: 'guest' as StudioRole, joinedAtMs: 1 },
  ];
  assert.equal(electLeader({ hostId: 'host', members, connected: new Set(['host', 'c1']), hostAbsentForMs: null }), 'host');
  assert.equal(electLeader({ hostId: 'host', members, connected: new Set(['c1', 'c2']), hostAbsentForMs: 5000 }), null);
  assert.equal(electLeader({ hostId: 'host', members, connected: new Set(['c0', 'c1', 'c2']), hostAbsentForMs: 10000 }), 'c0');
  assert.equal(electLeader({ hostId: 'host', members, connected: new Set(['c1', 'c2']), hostAbsentForMs: null }), 'c1');
  assert.equal(electLeader({ hostId: 'host', members, connected: new Set(['g1']), hostAbsentForMs: null }), null);
});
