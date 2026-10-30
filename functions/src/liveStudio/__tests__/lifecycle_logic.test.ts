import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  FIRST_HEARTBEAT_GRACE_MS,
  HEARTBEAT_STALE_MS,
  HOST_LEFT_GRACE_MS,
  NO_HEARTBEAT_MAX_MS,
  orphanReason,
  parseStartExtras,
  toMs,
} from '../lifecycle_logic';

const now = 10_000_000_000;
const live = (o: Partial<{ createdMs: number | null; heartbeatMs: number | null; hostLeftMs: number | null; status: unknown }>) => ({
  status: 'live',
  createdMs: now - 60 * 60 * 1000,
  heartbeatMs: null,
  hostLeftMs: null,
  ...o,
});

test('ended lives are never swept', () => {
  assert.equal(orphanReason(live({ status: 'ended', heartbeatMs: 0 }), now), null);
});

test('fresh heartbeat keeps the live open', () => {
  assert.equal(orphanReason(live({ heartbeatMs: now - 10_000 }), now), null);
});

test('stale heartbeat ends the live', () => {
  assert.equal(orphanReason(live({ heartbeatMs: now - HEARTBEAT_STALE_MS }), now), 'timeout');
});

test('host left the room past the grace', () => {
  const left = now - HOST_LEFT_GRACE_MS;
  assert.equal(orphanReason(live({ heartbeatMs: left - 5_000, hostLeftMs: left }), now), 'host_left');
  // Back within the grace or heartbeating again afterwards: keep it.
  assert.equal(orphanReason(live({ heartbeatMs: now - 5_000, hostLeftMs: now - 30_000 }), now), null);
  assert.equal(orphanReason(live({ heartbeatMs: now - 1_000, hostLeftMs: left }), now), null);
});

test('lives from builds without heartbeat get a long timeout only', () => {
  assert.equal(orphanReason(live({ createdMs: now - 60_000 }), now), null);
  assert.equal(orphanReason(live({ createdMs: now - NO_HEARTBEAT_MAX_MS }), now), 'timeout');
  assert.equal(orphanReason(live({ createdMs: now - FIRST_HEARTBEAT_GRACE_MS - HOST_LEFT_GRACE_MS, hostLeftMs: now - HOST_LEFT_GRACE_MS }), now), 'host_left');
  assert.equal(orphanReason(live({ createdMs: now - 30_000, hostLeftMs: now - HOST_LEFT_GRACE_MS }), now), null);
});

test('start extras are optional and sanitized', () => {
  assert.deepEqual(parseStartExtras(undefined), {
    category: null,
    coverUrl: null,
    audienceMode: 'public',
    allowGuestRequests: true,
  });
  assert.deepEqual(
    parseStartExtras({ category: ' Music ', coverUrl: 'https://x/y.jpg', audienceMode: 'followers', allowGuestRequests: false }),
    { category: 'Music', coverUrl: 'https://x/y.jpg', audienceMode: 'followers', allowGuestRequests: false },
  );
  const bad = parseStartExtras({ category: 'a\nb', coverUrl: 'http://x', audienceMode: 'vip', allowGuestRequests: 'no' });
  assert.equal(bad.category, null);
  assert.equal(bad.coverUrl, null);
  assert.equal(bad.audienceMode, 'public');
  assert.equal(bad.allowGuestRequests, true);
});

test('toMs reads numbers, dates and timestamps', () => {
  assert.equal(toMs(5), 5);
  assert.equal(toMs(new Date(7)), 7);
  assert.equal(toMs({ toMillis: () => 9 }), 9);
  assert.equal(toMs('x'), null);
});
