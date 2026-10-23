import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  ACTION_ALLOW_LIST,
  DETECTORS,
  DetectorId,
  Hit,
  INCIDENT_COOLDOWN_MS,
  KEY_RING_SIZE,
  MEDIA_KEY_BYTES,
  SAMPLE_MAX_CHARS,
  StudioIncident,
  buildAdvisory,
  buildHealthSummary,
  buildIncident,
  bucketsFor,
  countLog,
  detectorsFor,
  e2eeEnabled,
  fallbackAdvice,
  guardMapping,
  incidentId,
  isValidKeyDoc,
  keyPayload,
  keyUpdateEvent,
  memberChangeNeedsRotation,
  monitorShouldRun,
  newMediaKey,
  rotateMediaKey,
  sanitizeSample,
  severityFor,
  signalForFailure,
  slideLog,
  sumBuckets,
  validateModelOutput,
} from '../security_logic';

const spec = (id: DetectorId) => DETECTORS.find((d) => d.id === id)!;

/** Feeds [n] hits spaced [stepMs] apart through a detector's sliding log. */
function feed(id: DetectorId, n: number, stepMs: number, values?: (i: number) => string): number {
  const s = spec(id);
  let log: Hit[] = [];
  const cap = Math.min(200, s.distinct ? s.criticalAt * 8 : s.criticalAt + 1);
  for (let i = 0; i < n; i++) {
    log = slideLog(log, values ? { t: 1_000_000 + i * stepMs, v: values(i) } : { t: 1_000_000 + i * stepMs }, s.windowMs, cap);
  }
  return countLog(log, !!s.distinct);
}

// ─── Detectors ──────────────────────────────────────────────────────────────

test('every detector has warn < critical and a positive window', () => {
  for (const d of DETECTORS) {
    assert.ok(d.warnAt < d.criticalAt, d.id);
    assert.ok(d.windowMs > 0, d.id);
    assert.ok(d.reason(3, d.windowMs).length > 0);
  }
});

test('severity thresholds', () => {
  const s = spec('comment_flood_user');
  assert.equal(severityFor(s, s.warnAt - 1), null);
  assert.equal(severityFor(s, s.warnAt), 'warn');
  assert.equal(severityFor(s, s.criticalAt - 1), 'warn');
  assert.equal(severityFor(s, s.criticalAt), 'critical');
});

test('comment flood per user: inside the window escalates, spread out does not', () => {
  const s = spec('comment_flood_user');
  assert.equal(severityFor(s, feed('comment_flood_user', s.warnAt, 1000)), 'warn'); // 25 in 25 s
  assert.equal(severityFor(s, feed('comment_flood_user', s.criticalAt, 500)), 'critical'); // 60 in 30 s
  // One every 3 s: only ~20 are ever inside 60 s.
  assert.equal(severityFor(s, feed('comment_flood_user', 300, 3000)), null);
});

test('sliding log drops expired hits and is capped', () => {
  let log: Hit[] = [];
  for (let i = 0; i < 10; i++) log = slideLog(log, { t: i * 1000 }, 3000, 100);
  assert.deepEqual(log.map((h) => h.t), [7000, 8000, 9000]);
  for (let i = 0; i < 50; i++) log = slideLog(log, { t: 10_000 + i }, 60_000, 5);
  assert.equal(log.length, 5);
  assert.equal(slideLog(undefined, { t: 1 }, 10, 3).length, 1);
  // garbage from the doc is ignored
  assert.equal(slideLog([{ t: 'x' } as unknown as Hit, { t: 5 }], { t: 6 }, 10, 5).length, 2);
});

test('distinct counting: duplicate identity and token sweeps', () => {
  const dup = spec('duplicate_identity_user');
  assert.equal(severityFor(dup, feed('duplicate_identity_user', 10, 1000, () => 'same')), null);
  assert.equal(severityFor(dup, feed('duplicate_identity_user', 2, 1000, (i) => `fp${i}`)), 'warn');
  assert.equal(severityFor(dup, feed('duplicate_identity_user', 4, 1000, (i) => `fp${i}`)), 'critical');
  const sweep = spec('token_sweep_user');
  assert.equal(severityFor(sweep, feed('token_sweep_user', 40, 1000, () => 'one-stream')), null);
  assert.equal(severityFor(sweep, feed('token_sweep_user', 25, 1000, (i) => `s${i}`)), 'critical');
  // 25 streams but spread over > 5 min: not a sweep
  assert.equal(severityFor(sweep, feed('token_sweep_user', 25, 60_000, (i) => `s${i}`)), null);
});

test('detector routing by signal and detail', () => {
  const ids = (k: Parameters<typeof detectorsFor>[0], d = {}) => detectorsFor(k, d).map((x) => x.id).sort();
  assert.deepEqual(ids('comment'), ['comment_flood_stream', 'comment_flood_user']);
  assert.deepEqual(ids('join_request'), ['join_request_flood_stream', 'join_request_flood_user']);
  assert.deepEqual(ids('exhausted', { bucket: 'react' }), ['error_storm_user', 'reaction_flood_user']);
  assert.deepEqual(ids('exhausted', { bucket: 'cmt_min' }), ['error_storm_user']);
  assert.deepEqual(ids('denied'), ['error_storm_user']);
  assert.deepEqual(ids('blocked_token'), ['blocked_retry_user']);
  assert.deepEqual(ids('token', { newAccount: false }), ['token_sweep_user']);
  assert.deepEqual(ids('token', { newAccount: true, fingerprint: 'f' }), ['duplicate_identity_user', 'raid_stream', 'token_sweep_user']);
});

test('reaction flood beyond the rate limit and blocked retries', () => {
  const r = spec('reaction_flood_user');
  assert.equal(severityFor(r, feed('reaction_flood_user', 20, 200)), 'warn');
  assert.equal(severityFor(r, feed('reaction_flood_user', 60, 100)), 'critical');
  const b = spec('blocked_retry_user');
  assert.equal(severityFor(b, feed('blocked_retry_user', 3, 60_000)), 'warn');
  assert.equal(severityFor(b, feed('blocked_retry_user', 10, 30_000)), 'critical');
});

test('stream buckets: raid over sharded counters', () => {
  const now = 1_000_000_123;
  const raid = spec('raid_stream');
  const buckets = bucketsFor(now, raid.windowMs);
  assert.equal(buckets.length, 13); // 60 s / 5 s, unaligned → one partial bucket more
  assert.ok(buckets[buckets.length - 1] <= now);
  const rows = buckets.flatMap((b) => [0, 1, 2, 3].map(() => ({ bucket: b, count: 3 }))); // 13×4×3 = 156
  rows.push({ bucket: buckets[0] - 5000, count: 999 }); // outside the window
  const n = sumBuckets(rows, now, raid.windowMs);
  assert.equal(n, 156);
  assert.equal(severityFor(raid, n), 'critical');
  assert.equal(severityFor(raid, sumBuckets(rows.slice(0, 10), now, raid.windowMs)), 'warn');
});

test('incident ids dedupe within the cooldown slot and allow escalation', () => {
  const t = 10 * INCIDENT_COOLDOWN_MS.warn;
  const a = incidentId('comment_flood_user', 'u/1', 'warn', t);
  assert.equal(a, incidentId('comment_flood_user', 'u/1', 'warn', t + 1000));
  assert.notEqual(a, incidentId('comment_flood_user', 'u/1', 'warn', t + INCIDENT_COOLDOWN_MS.warn));
  assert.notEqual(a, incidentId('comment_flood_user', 'u/1', 'critical', t));
  assert.ok(!a.includes('/'));
});

test('buildIncident: below threshold null; stream scope has no uid', () => {
  assert.equal(buildIncident({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 3, now: 1 }), null);
  const i = buildIncident({ spec: spec('raid_stream'), streamId: 's', uid: 'u', count: 150, now: 5 })!;
  assert.equal(i.uid, null);
  assert.equal(i.severity, 'critical');
  assert.equal(i.threshold, spec('raid_stream').criticalAt);
  const u = buildIncident({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 30, now: 5 })!;
  assert.equal(u.uid, 'u');
  assert.equal(u.severity, 'warn');
});

test('failures map to signals', () => {
  assert.deepEqual(signalForFailure('resource-exhausted', 'react'), { kind: 'exhausted', detail: { bucket: 'react' } });
  assert.deepEqual(signalForFailure('permission-denied'), { kind: 'denied', detail: { bucket: '' } });
  assert.equal(signalForFailure('not-found'), null);
});

test('only critical per-account incidents go to the guard', () => {
  const crit = buildIncident({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 99, now: 1 })!;
  assert.equal(guardMapping(crit)!.type, 'message_spike');
  const dup = buildIncident({ spec: spec('duplicate_identity_user'), streamId: 's', uid: 'u', count: 5, now: 1 })!;
  assert.equal(guardMapping(dup)!.type, 'session_reuse');
  assert.ok(String(guardMapping(dup)!.details.why).length > 0);
  const warn = buildIncident({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 30, now: 1 })!;
  assert.equal(guardMapping(warn), null);
  const raid = buildIncident({ spec: spec('raid_stream'), streamId: 's', uid: null, count: 500, now: 1 })!;
  assert.equal(guardMapping(raid), null);
});

// ─── Monitor ────────────────────────────────────────────────────────────────

const inc = (id: DetectorId, uid: string | null, count: number, atMs: number): StudioIncident =>
  buildIncident({ spec: spec(id), streamId: 's1', uid, count, now: atMs })!;

test('monitor throttle: once per 60 s', () => {
  assert.equal(monitorShouldRun(undefined, 1), true);
  assert.equal(monitorShouldRun(1000, 50_000), false);
  assert.equal(monitorShouldRun(1000, 61_000), true);
});

test('summary is PII-minimal: aliases, no uids, sanitized short samples', () => {
  const now = 10_000_000;
  const { summary, aliases } = buildHealthSummary({
    incidents: [inc('comment_flood_user', 'uid_secret_1', 70, now - 1000), inc('raid_stream', null, 40, now - 2000),
      inc('comment_flood_user', 'old', 70, now - 20 * 60_000)],
    metrics: { viewers: 120.4, participants: 3, chatPerMin: 88 },
    now,
    people: { uid_secret_1: { onStage: false, role: 'viewer' } },
    samples: { uid_secret_1: ['Visit https://spam.example now!!! mail me a@b.co @bob +1 555 123 4567 ' + 'x'.repeat(200), 'two', 'three', 'four'] },
  });
  const json = JSON.stringify(summary);
  assert.ok(!json.includes('uid_secret_1'));
  assert.ok(!json.includes('spam.example'));
  assert.ok(!json.includes('a@b.co'));
  assert.ok(!json.includes('@bob'));
  assert.ok(!json.includes('555'));
  assert.equal(summary.incidents.length, 2); // the 20-min-old one is dropped
  assert.equal(aliases.a1, 'uid_secret_1');
  assert.ok(summary.samples.length <= 3);
  for (const s of summary.samples) assert.ok(s.text.length <= SAMPLE_MAX_CHARS);
  assert.equal(summary.metrics.viewers, 120);
  assert.deepEqual(summary.allowedActions, ACTION_ALLOW_LIST);
  assert.equal(sanitizeSample(42), '');
  assert.equal(sanitizeSample('a\u0000b\nc'), 'a b c');
});

function ctx() {
  const now = 10_000_000;
  return buildHealthSummary({
    incidents: [inc('comment_flood_user', 'u1', 30, now), inc('duplicate_identity_user', 'u2', 2, now)],
    metrics: { viewers: 10, participants: 2, chatPerMin: 5 },
    now,
    people: { u1: { onStage: false, role: 'viewer' }, u2: { onStage: true, role: 'guest' } },
  });
}

test('model output: valid answer maps aliases back to uids', () => {
  const c = ctx();
  const r = validateModelOutput(
    '```json\n{"assessment":"Spam from one viewer.","actions":[{"type":"mute_user","account":"a1"},{"type":"remove_from_stage","account":"a2"},{"type":"slow_mode"}]}\n```',
    c,
  )!;
  assert.equal(r.assessment, 'Spam from one viewer.');
  assert.deepEqual(r.actions, [
    { type: 'mute_user', targetUid: 'u1' },
    { type: 'remove_from_stage', targetUid: 'u2' },
    { type: 'slow_mode' },
  ]);
});

test('model output: strict validation drops anything off-list', () => {
  const c = ctx();
  const r = validateModelOutput(
    {
      assessment: 'x'.repeat(1000),
      actions: [
        { type: 'delete_account', account: 'a1' }, // not allow-listed
        { type: 'block_user', account: 'a9' }, // unknown alias
        { type: 'block_user', account: 'u1' }, // raw uid is not an alias
        { type: 'remove_from_stage', account: 'a1' }, // a1 is not on stage
        { type: 'slow_mode', account: 'a1' }, // stream action with an account
        { type: 'end_live' }, // no critical incident
        { type: 'mute_user', account: 'a1' },
        { type: 'mute_user', account: 'a1' }, // duplicate
        { type: 'followers_only' },
        { type: 'pause_join_requests' },
        { type: 'slow_mode' }, // over 3
      ],
    },
    c,
  )!;
  assert.ok(r.assessment.length <= 280);
  assert.deepEqual(r.actions.map((a) => a.type), ['mute_user', 'followers_only', 'pause_join_requests']);
});

test('model output: unusable answers return null (→ fallback)', () => {
  const c = ctx();
  assert.equal(validateModelOutput('not json', c), null);
  assert.equal(validateModelOutput('[]', c), null);
  assert.equal(validateModelOutput({ assessment: '', actions: [{ type: 'slow_mode' }] }, c), null);
  assert.equal(validateModelOutput({ assessment: 'ok', actions: [] }, c), null);
  assert.equal(validateModelOutput({ assessment: 'ok', actions: [{ type: 'ban_everyone' }] }, c), null);
  assert.equal(validateModelOutput(null, c), null);
});

test('end_live allowed only with a critical incident', () => {
  const now = 1_000;
  const c = buildHealthSummary({ incidents: [inc('raid_stream', null, 500, now)], metrics: { viewers: 1, participants: 1, chatPerMin: 0 }, now });
  assert.deepEqual(validateModelOutput({ assessment: 'Raid.', actions: [{ type: 'end_live' }] }, c)!.actions, [{ type: 'end_live' }]);
});

test('fallback rules pick allow-listed actions', () => {
  const now = 5_000;
  const raid = fallbackAdvice([inc('raid_stream', null, 40, now)]);
  assert.deepEqual(raid.actions.map((a) => a.type), ['followers_only', 'pause_join_requests']);
  const spam = fallbackAdvice([inc('comment_flood_user', 'u1', 99, now), inc('comment_flood_stream', null, 500, now - 1)]);
  assert.deepEqual(spam.actions[0], { type: 'block_user', targetUid: 'u1' });
  assert.ok(spam.actions.some((a) => a.type === 'slow_mode'));
  const dupStage = fallbackAdvice([inc('duplicate_identity_user', 'u2', 2, now)], { u2: { onStage: true } });
  assert.deepEqual(dupStage.actions, [{ type: 'remove_from_stage', targetUid: 'u2' }]);
  for (const a of [...raid.actions, ...spam.actions]) assert.ok(ACTION_ALLOW_LIST.includes(a.type));
  assert.ok(spam.actions.length <= 3);
  assert.ok(spam.assessment.length > 0);
  assert.equal(fallbackAdvice([]).actions.length, 0);
});

test('advisory severity is the worst incident', () => {
  const now = 7;
  const a = buildAdvisory({
    streamId: 's1', now, source: 'rules', assessment: 'x', actions: [],
    incidents: [inc('comment_flood_user', 'u', 30, now), inc('raid_stream', null, 500, now)],
  });
  assert.equal(a.severity, 'critical');
  assert.equal(a.id, 'adv_7');
  assert.equal(a.incidentIds.length, 2);
});

// ─── E2EE keys ──────────────────────────────────────────────────────────────

let counter = 0;
const rnd = (n: number) => new Uint8Array(n).fill(++counter);

test('env switch defaults to on', () => {
  assert.equal(e2eeEnabled(undefined), true);
  assert.equal(e2eeEnabled('true'), true);
  assert.equal(e2eeEnabled(''), true);
  for (const off of ['false', 'FALSE', '0', 'off', 'no']) assert.equal(e2eeEnabled(off), false, off);
});

test('new key: 32 random bytes, index 0', () => {
  const k = newMediaKey(rnd, 100);
  assert.equal(Buffer.from(k.key, 'base64').length, MEDIA_KEY_BYTES);
  assert.equal(k.keyIndex, 0);
  assert.ok(isValidKeyDoc(k));
  assert.deepEqual(keyPayload(k), { key: k.key, keyIndex: 0 });
  assert.throws(() => newMediaKey(() => new Uint8Array(16), 1));
});

test('rotation: new bytes, next index, wraps around the ring', () => {
  const a = newMediaKey(rnd, 1);
  const b = rotateMediaKey(a, rnd, 2, 'blocked');
  assert.notEqual(a.key, b.key);
  assert.equal(b.keyIndex, 1);
  assert.equal(b.reason, 'blocked');
  let k = a;
  for (let i = 0; i < KEY_RING_SIZE; i++) k = rotateMediaKey(k, rnd, 3, 'x');
  assert.equal(k.keyIndex, 0);
  assert.equal(rotateMediaKey(null, rnd, 1, 'x').keyIndex, 0);
  assert.equal(isValidKeyDoc({ key: 'AAAA', keyIndex: 0 }), false);
  assert.equal(isValidKeyDoc({ ...a, keyIndex: KEY_RING_SIZE }), false);
});

test('rotation triggers: losing publish rights only', () => {
  assert.equal(memberChangeNeedsRotation({ role: 'guest' }, { role: 'viewer' }), true);
  assert.equal(memberChangeNeedsRotation({ role: 'coHost' }, undefined), true);
  assert.equal(memberChangeNeedsRotation({ role: 'coHost' }, { role: 'guest' }), false);
  assert.equal(memberChangeNeedsRotation({ role: 'viewer' }, { role: 'guest' }), false);
  assert.equal(memberChangeNeedsRotation(undefined, { role: 'guest' }), false);
  assert.equal(memberChangeNeedsRotation({ role: 'guest' }, { role: 'guest', micOn: false } as { role: string }), false);
});

test('key.update event never carries the key', () => {
  const e = keyUpdateEvent(3, 9);
  assert.deepEqual(e, { v: 1, type: 'key.update', keyIndex: 3, ts: 9 });
  assert.ok(!('key' in e));
});
