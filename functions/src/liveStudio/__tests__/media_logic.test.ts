import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { ACCENT_PALETTE, Limits, StudioState, defaultSettings } from '../contracts';
import {
  ROOM_EMPTY_TIMEOUT_SECONDS,
  TOKEN_TTL_SECONDS,
  buildHostMember,
  buildInitialState,
  buildStreamDoc,
  canSetOwnMedia,
  grantForRole,
  mergeStartSettings,
  parseOwnMedia,
  profileFrom,
  stagePublishers,
  tokenDecision,
  wireState,
} from '../media_logic';

test('publishing roles get cam/mic/screen and no data', () => {
  for (const r of ['host', 'coHost', 'guest'] as const) {
    const g = grantForRole(r, 'studio_x');
    assert.equal(g.room, 'studio_x');
    assert.equal(g.roomJoin, true);
    assert.equal(g.canSubscribe, true);
    assert.equal(g.canPublish, true, r);
    assert.deepEqual(g.canPublishSources, ['camera', 'microphone', 'screen_share']);
    assert.equal(g.canPublishData, false);
  }
});

test('viewer subscribes only', () => {
  const g = grantForRole('viewer', 'studio_x');
  assert.equal(g.canSubscribe, true);
  assert.equal(g.canPublish, false);
  assert.deepEqual(g.canPublishSources, []);
  assert.equal(g.canPublishData, false);
  assert.equal(g.canUpdateOwnMetadata, false);
});

test('grant sources are a fresh copy per call', () => {
  const a = grantForRole('host', 'r');
  a.canPublishSources.pop();
  assert.equal(grantForRole('host', 'r').canPublishSources.length, 3);
});

test('ttl ~6h, empty timeout ~10min', () => {
  assert.equal(TOKEN_TTL_SECONDS, 21600);
  assert.equal(ROOM_EMPTY_TIMEOUT_SECONDS, 600);
});

test('token refused for blocked users and ended streams', () => {
  assert.deepEqual(tokenDecision({ status: 'live', blocked: false }), { ok: true });
  assert.deepEqual(tokenDecision({ status: 'preparing', blocked: false }), { ok: true });
  const ended = tokenDecision({ status: 'ended', blocked: false });
  assert.equal(ended.ok, false);
  assert.equal(!ended.ok && ended.code, 'failed-precondition');
  const blocked = tokenDecision({ status: 'live', blocked: true });
  assert.equal(!blocked.ok && blocked.code, 'permission-denied');
});

test('initial state: host centered, empty wall, goods table, live', () => {
  const s = buildInitialState({ streamId: 's1', hostId: 'h', title: 'T', settings: defaultSettings(), nowMs: 5 });
  assert.equal(s.status, 'live');
  assert.equal(s.seq, 0);
  assert.equal(s.stage.centerUid, 'h');
  assert.equal(s.stage.wall.length, Limits.wallSlots);
  assert.ok(s.stage.wall.every((w) => w === null));
  assert.equal(s.stage.updatedBy, 'h');
  assert.equal(s.table.mode, 'goods');
  assert.equal(s.counts.participants, 1);
});

test('host member gets accent 0 and role host', () => {
  const m = buildHostMember('h', { displayName: 'Ana', avatarUrl: 'a' }, 9);
  assert.equal(m.role, 'host');
  assert.equal(m.accent, ACCENT_PALETTE[0]);
  assert.equal(m.micOn && m.camOn, true);
});

test('stream doc carries v1-required and v2 marker fields', () => {
  const d = buildStreamDoc({ streamId: 's', hostId: 'h', title: 'T', profile: { displayName: 'A', avatarUrl: '' } });
  assert.equal(d.hostId, 'h');
  assert.equal(d.status, 'live');
  assert.equal(d.layoutMode, 'studio');
  assert.equal(d.studioVersion, 2);
  assert.equal(d.audienceMode, 'public');
});

test('profile falls back across user fields and token', () => {
  assert.deepEqual(profileFrom({ displayName: 'D', avatarUrl: 'x' }), { displayName: 'D', avatarUrl: 'x' });
  assert.deepEqual(profileFrom({ username: 'u', photoUrl: 'p' }), { displayName: 'u', avatarUrl: 'p' });
  assert.deepEqual(profileFrom(undefined, { name: 'n', picture: 'q' }), { displayName: 'n', avatarUrl: 'q' });
  assert.equal(profileFrom(undefined).displayName.length > 0, true);
});

test('start settings: argument overrides saved, non-objects ignored', () => {
  assert.deepEqual(mergeStartSettings({ theme: 'light', frameWidth: 3 }, { frameWidth: 8 }), { theme: 'light', frameWidth: 8 });
  assert.deepEqual(mergeStartSettings(undefined, 'x'), {});
  assert.deepEqual(mergeStartSettings([1], null), {});
});

function stateWith(wall: (string | null)[], overflow: string[] = []): StudioState {
  const s = buildInitialState({ streamId: 's', hostId: 'h', title: 'T', settings: defaultSettings(), nowMs: 0 });
  return { ...s, stage: { ...s.stage, wall, overflow } };
}

test('own media only for publishing roles on stage', () => {
  const s = stateWith(['g1', null, null, null, null, null], ['o1']);
  assert.deepEqual(stagePublishers(s), ['h', 'g1', 'o1']);
  assert.equal(canSetOwnMedia('host', 'h', s), true);
  assert.equal(canSetOwnMedia('guest', 'g1', s), true);
  assert.equal(canSetOwnMedia('guest', 'o1', s), true);
  assert.equal(canSetOwnMedia('guest', 'g2', s), false);
  assert.equal(canSetOwnMedia('viewer', 'g1', s), false);
});

test('parseOwnMedia requires both booleans', () => {
  assert.deepEqual(parseOwnMedia({ micOn: false, camOn: true }), { micOn: false, camOn: true });
  assert.equal(parseOwnMedia({ micOn: 'no', camOn: true }), null);
  assert.equal(parseOwnMedia(null), null);
});

test('wireState strips Firestore timestamps', () => {
  const w = wireState({ seq: 3, updatedAt: { _seconds: 1 }, createdAt: 1 }) as unknown as Record<string, unknown>;
  assert.deepEqual(w, { seq: 3 });
});
