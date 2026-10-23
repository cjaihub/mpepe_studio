import { test, describe } from 'node:test';
import * as assert from 'node:assert/strict';
import { Limits } from '../contracts';
import {
  normalizeCommentText,
  isValidClientId,
  commentDocId,
  blockListModerator,
  composeModerators,
  moderateComment,
  setCommentModerator,
  foldForMatching,
  parseMuteMinutes,
  muteUntil,
  isChatMuted,
  canDeleteComment,
  canMuteChat,
  SecondWindowCounter,
  gateStep,
  shardBudget,
  shouldBroadcastComment,
  throttleDue,
  LeaseMemo,
  parseReaction,
  reactionField,
  pickShard,
  sumShards,
  reactionDeltas,
  flushDelayMs,
  simulateAggregation,
  streamIdFromRoom,
  resolveViewers,
  computeParticipants,
  stagePublishers,
  countsChanged,
  joinLineMode,
  systemLineId,
  displayNameOf,
  avatarOf,
  FLUSH_GRACE_MS,
  COMMENT_GATE_SHARDS,
} from '../social_logic';

describe('comment normalization', () => {
  test('trims and collapses whitespace', () => {
    assert.deepEqual(normalizeCommentText('  hello \n\n  world\t! '), { ok: true, text: 'hello world !' });
  });
  test('strips zero-width and control chars', () => {
    assert.deepEqual(normalizeCommentText('hi​\u0007 there'), { ok: true, text: 'hi there' });
  });
  test('rejects empty, whitespace-only and non-strings', () => {
    assert.equal(normalizeCommentText('   \n ').ok, false);
    assert.equal(normalizeCommentText(42).ok, false);
    assert.equal(normalizeCommentText(undefined).ok, false);
  });
  test('enforces the length cap after collapsing', () => {
    assert.equal(normalizeCommentText('a'.repeat(Limits.commentMaxLength)).ok, true);
    assert.equal(normalizeCommentText('a'.repeat(Limits.commentMaxLength + 1)).ok, false);
    // 300 raw chars that collapse to ≤ 200 are fine.
    assert.equal(normalizeCommentText('a' + ' '.repeat(298) + 'b').ok, true);
  });
  test('counts emoji as one character each', () => {
    assert.equal(normalizeCommentText('😀'.repeat(Limits.commentMaxLength)).ok, true);
  });
  test('clientId validation and deterministic ids', () => {
    assert.equal(isValidClientId('abcDEF12'), true);
    assert.equal(isValidClientId('short'), false);
    assert.equal(isValidClientId('has/slash12'), false);
    assert.equal(commentDocId('u1', 'abcDEF12'), 'u1_abcDEF12');
  });
});

describe('moderation hook', () => {
  test('block list rejects whole phrases, case/leet-insensitive', async () => {
    const m = blockListModerator({ blocked: ['bad phrase', 'spam'] });
    assert.equal((await m('this is a BAD   phrase ok', 'u')).allow, false);
    assert.equal((await m('5p4m', 'u')).allow, false);
    assert.equal((await m('spammer', 'u')).allow, true, 'no partial-word match');
    assert.equal((await m('all good', 'u')).allow, true);
  });
  test('masked terms are replaced, comment allowed', async () => {
    const m = blockListModerator({ blocked: [], masked: ['darn'] });
    const v = await m('oh Darn it', 'u');
    assert.equal(v.allow, true);
    assert.equal(v.text, 'oh •••• it');
  });
  test('fold strips diacritics', () => {
    assert.equal(foldForMatching('Ñoño Spä'), 'nono spa');
  });
  test('compose: first rejection wins, masks accumulate', async () => {
    const mask = blockListModerator({ blocked: [], masked: ['x'] });
    const reject = async (t: string) => ({ allow: !t.includes('no'), reason: 'nope', text: t });
    const c = composeModerators(mask, reject);
    assert.deepEqual(await c('a x b', 'u'), { allow: true, text: 'a • b' });
    assert.equal((await c('no x', 'u')).allow, false);
  });
  test('setCommentModerator replaces the active hook', async () => {
    setCommentModerator((t) => ({ allow: t !== 'blocked', text: t.toUpperCase() }));
    assert.deepEqual(await moderateComment('hi', 'u'), { allow: true, text: 'HI' });
    assert.equal((await moderateComment('blocked', 'u')).allow, false);
    setCommentModerator(blockListModerator());
    assert.equal((await moderateComment('kys', 'u')).allow, false, 'default list is active again');
  });
});

describe('mute and permissions', () => {
  test('mute minutes parsing', () => {
    assert.equal(parseMuteMinutes(5), 5);
    assert.equal(parseMuteMinutes(0), 0);
    assert.equal(parseMuteMinutes(2.9), 2);
    assert.equal(parseMuteMinutes(-1), null);
    assert.equal(parseMuteMinutes(1441), null);
    assert.equal(parseMuteMinutes('5'), null);
  });
  test('mute expiry', () => {
    const until = muteUntil(1000, 2);
    assert.equal(until, 121_000);
    assert.equal(isChatMuted(false, until, 120_999), true);
    assert.equal(isChatMuted(false, until, 121_000), false);
    assert.equal(isChatMuted(true, undefined, 0), true);
    assert.equal(isChatMuted(undefined, undefined, 0), false);
  });
  test('delete: author or manager', () => {
    assert.equal(canDeleteComment('viewer', 'a', 'a'), true);
    assert.equal(canDeleteComment('viewer', 'a', 'b'), false);
    assert.equal(canDeleteComment('guest', 'a', 'b'), false);
    assert.equal(canDeleteComment('coHost', 'a', 'b'), true);
    assert.equal(canDeleteComment('host', 'a', 'b'), true);
    assert.equal(canDeleteComment('viewer', '', ''), false);
  });
  test('mute chat: managers only, co-host cannot mute host, no self-mute', () => {
    assert.equal(canMuteChat('host', 'h', 'viewer', 'v'), true);
    assert.equal(canMuteChat('coHost', 'c', 'viewer', 'v'), true);
    assert.equal(canMuteChat('coHost', 'c', 'coHost', 'c2'), true);
    assert.equal(canMuteChat('coHost', 'c', 'host', 'h'), false);
    assert.equal(canMuteChat('guest', 'g', 'viewer', 'v'), false);
    assert.equal(canMuteChat('viewer', 'v', 'viewer', 'v2'), false);
    assert.equal(canMuteChat('host', 'h', 'host', 'h'), false);
  });
});

describe('comment broadcast sampler', () => {
  test('second window counter resets each second, per key', () => {
    const c = new SecondWindowCounter();
    assert.equal(c.hit('s', 1000), 1);
    assert.equal(c.hit('s', 1500), 2);
    assert.equal(c.hit('t', 1500), 1);
    assert.equal(c.count('s', 1999), 2);
    assert.equal(c.hit('s', 2000), 1);
    assert.equal(c.count('s', 3000), 0);
  });
  test('counter prunes when too many keys', () => {
    const c = new SecondWindowCounter(3);
    c.hit('a', 0); c.hit('b', 0); c.hit('c', 0);
    c.hit('d', 1000);
    assert.equal(c.count('a', 1000), 0);
    assert.equal(c.count('d', 1000), 1);
  });
  test('gateStep enforces the per-second budget and resets', () => {
    let doc: { sec: number; n: number } | undefined;
    let allowed = 0;
    for (let i = 0; i < 20; i++) {
      const s = gateStep(doc, 5000 + i * 10, 5);
      if (s.next) doc = s.next;
      if (s.allow) allowed++;
    }
    assert.equal(allowed, 5);
    assert.equal(gateStep(doc, 6000, 5).allow, true, 'next second resets');
  });
  test('shard budgets cover the global budget', () => {
    assert.ok(shardBudget() * COMMENT_GATE_SHARDS >= Limits.commentBroadcastPerSecond);
    assert.equal(shardBudget(25, 5), 5);
    assert.equal(shardBudget(1, 5), 1);
  });
  test('managers always broadcast; others need local and global budget', () => {
    assert.equal(shouldBroadcastComment({ role: 'host', localCountThisSecond: 999, globalAllow: false }), true);
    assert.equal(shouldBroadcastComment({ role: 'coHost', localCountThisSecond: 999, globalAllow: null }), true);
    assert.equal(shouldBroadcastComment({ role: 'viewer', localCountThisSecond: 1, globalAllow: true }), true);
    assert.equal(shouldBroadcastComment({ role: 'viewer', localCountThisSecond: 1, globalAllow: false }), false);
    assert.equal(shouldBroadcastComment({ role: 'viewer', localCountThisSecond: 1, globalAllow: null }), false, 'fail closed');
    assert.equal(shouldBroadcastComment({ role: 'guest', localCountThisSecond: 26, globalAllow: true }), false);
  });
  test('a 1000-comment burst in one second broadcasts ≤ 25 viewer comments + all host ones', () => {
    const local = new SecondWindowCounter();
    const docs: ({ sec: number; n: number } | undefined)[] = Array(COMMENT_GATE_SHARDS).fill(undefined);
    let sent = 0;
    let hostSent = 0;
    for (let i = 0; i < 1000; i++) {
      const now = 10_000 + i;
      const role = i % 100 === 0 ? 'host' : 'viewer';
      const n = local.hit('s', now);
      const k = pickShard((i * 7919 % 1000) / 1000, COMMENT_GATE_SHARDS);
      const step = gateStep(docs[k], now, shardBudget());
      if (role !== 'host' && step.next) docs[k] = step.next;
      const ok = shouldBroadcastComment({ role, localCountThisSecond: n, globalAllow: role === 'host' ? null : step.allow });
      if (ok && role === 'host') hostSent++;
      else if (ok) sent++;
    }
    assert.ok(sent <= Limits.commentBroadcastPerSecond, `sent ${sent}`);
    assert.ok(sent > 0);
    assert.equal(hostSent, 10);
  });
});

describe('throttles and leases', () => {
  test('throttleDue', () => {
    assert.equal(throttleDue(undefined, 0, 1000), true);
    assert.equal(throttleDue(1000, 1999, 1000), false);
    assert.equal(throttleDue(1000, 2000, 1000), true);
    assert.equal(throttleDue(10_000, 1000, 1000), true, 'clock went back by more than one interval');
    assert.equal(throttleDue(1500, 1000, 1000), false, 'small skew keeps the lease');
  });
  test('per-user 10 s system-line throttle', () => {
    let last: number | undefined;
    const emitted: number[] = [];
    for (let t = 0; t <= 30_000; t += 700) {
      if (throttleDue(last, t, 10_000)) {
        last = t;
        emitted.push(t);
      }
    }
    assert.deepEqual(emitted, [0, 10_500, 21_000]);
  });
  test('lease memo', () => {
    const m = new LeaseMemo();
    assert.equal(m.blocked('k', 0), false);
    m.hold('k', 500);
    assert.equal(m.blocked('k', 499), true);
    assert.equal(m.blocked('k', 500), false);
  });
});

describe('reactions', () => {
  test('parseReaction', () => {
    assert.deepEqual(parseReaction('love', 3), { ok: true, kind: 'love', n: 3 });
    assert.equal(parseReaction('sparkles', Limits.reactionMaxPerCall).ok, true);
    assert.equal(parseReaction('love', Limits.reactionMaxPerCall + 1).ok, false);
    assert.equal(parseReaction('love', 0).ok, false);
    assert.equal(parseReaction('love', 1.5).ok, false);
    assert.equal(parseReaction('fire', 1).ok, false);
    assert.equal(reactionField('love'), 'loves');
    assert.equal(reactionField('sparkles'), 'sparkles');
  });
  test('pickShard stays in range', () => {
    assert.equal(pickShard(0), 0);
    assert.equal(pickShard(0.999999), 9);
    assert.equal(pickShard(1), 9);
    assert.equal(pickShard(-1), 0);
  });
  test('sumShards ignores missing docs and bad fields', () => {
    assert.deepEqual(sumShards([{ loves: 2, sparkles: 1 }, undefined, { loves: 3, shares: 1, viewers: -1, x: 'y' }, { loves: 'NaN' }]), {
      loves: 5, sparkles: 1, shares: 1, viewers: -1,
    });
  });
  test('deltas are against the last flushed totals and never negative', () => {
    assert.deepEqual(reactionDeltas({ loves: 10, sparkles: 4 }, undefined), { loves: 10, sparkles: 4 });
    assert.deepEqual(reactionDeltas({ loves: 10, sparkles: 4 }, { loves: 7, sparkles: 4 }), { loves: 3, sparkles: 0 });
    assert.deepEqual(reactionDeltas({ loves: 5, sparkles: 0 }, { loves: 7 }), { loves: 0, sparkles: 0 });
  });
  test('late increments roll into the next window (never lost)', () => {
    let flushed: { loves: number; sparkles: number } | undefined;
    let shard = 0;
    const deltas: number[] = [];
    shard += 5; // window 1
    const d1 = reactionDeltas({ loves: shard, sparkles: 0 }, flushed);
    flushed = { loves: shard, sparkles: 0 };
    deltas.push(d1.loves);
    shard += 2; // landed after flush 1 read
    shard += 1; // window 2
    deltas.push(reactionDeltas({ loves: shard, sparkles: 0 }, flushed).loves);
    assert.deepEqual(deltas, [5, 3]);
  });
  test('flush delay waits for the window end plus grace', () => {
    assert.equal(flushDelayMs(1000, 1000, 500), 500 + FLUSH_GRACE_MS);
    assert.equal(flushDelayMs(1000, 1400, 500), 100 + FLUSH_GRACE_MS);
    assert.equal(flushDelayMs(1000, 9999, 500), 0);
  });
  test('100k calls spread over 10 s produce ≤ 20 flushes (one per 500 ms window)', () => {
    const calls = Array.from({ length: 100_000 }, (_, i) => Math.floor((i * 10_000) / 100_000));
    const flushes = simulateAggregation(calls, Limits.reactionAggregateWindowMs);
    assert.equal(flushes.length, 20);
    for (let i = 1; i < flushes.length; i++) assert.ok(flushes[i] - flushes[i - 1] >= Limits.reactionAggregateWindowMs);
  });
  test('idle windows produce no flush', () => {
    assert.deepEqual(simulateAggregation([0, 100, 5000]), [500, 5500]);
    assert.deepEqual(simulateAggregation([]), []);
  });
});

describe('presence and counts', () => {
  test('room name → stream id', () => {
    assert.equal(streamIdFromRoom('studio_abc123'), 'abc123');
    assert.equal(streamIdFromRoom('call_abc'), null);
    assert.equal(streamIdFromRoom('studio_'), null);
    assert.equal(streamIdFromRoom('studio_a/b'), null);
    assert.equal(streamIdFromRoom(undefined), null);
  });
  test('viewers prefer the room count, fall back to the clamped counter', () => {
    assert.equal(resolveViewers(1200, 3), 1200);
    assert.equal(resolveViewers(0, 7), 7);
    assert.equal(resolveViewers(undefined, -4), 0);
  });
  test('participants = stage + co-hosts + pending (deduped)', () => {
    const stage = stagePublishers({ centerUid: 'h', wall: ['a', null, 'b', null, null, null], overflow: ['c'] });
    assert.deepEqual(stage, ['h', 'a', 'b', 'c']);
    assert.equal(computeParticipants(stage, ['a', 'co'], 3), 5 + 3);
    assert.equal(computeParticipants([], [], 0), 0);
    assert.deepEqual(stagePublishers(undefined), []);
  });
  test('counts change detection', () => {
    assert.equal(countsChanged(undefined, { viewers: 1, participants: 1 }), true);
    assert.equal(countsChanged({ viewers: 1, participants: 1 }, { viewers: 1, participants: 1 }), false);
    assert.equal(countsChanged({ viewers: 1, participants: 1 }, { viewers: 2, participants: 1 }), true);
  });
  test('joined lines: always in small rooms, sampled ≤ 1/s in large rooms', () => {
    assert.equal(joinLineMode(10), 'always');
    assert.equal(joinLineMode(100), 'always');
    assert.equal(joinLineMode(101), 'sampled');
    let last: number | undefined;
    let lines = 0;
    for (let t = 0; t < 5000; t += 5) {
      if (joinLineMode(200_000) === 'always' || throttleDue(last, t, 1000)) {
        last = t;
        lines++;
      }
    }
    assert.equal(lines, 5);
  });
  test('counts broadcast at most every countsIntervalMs', () => {
    let last: number | undefined;
    let sent = 0;
    for (let t = 0; t < 10_000; t += 50) {
      if (throttleDue(last, t, Limits.countsIntervalMs)) {
        last = t;
        sent++;
      }
    }
    assert.equal(sent, 5);
  });
});

describe('misc', () => {
  test('system line ids are prefixed and unique-ish', () => {
    const a = systemLineId(1000, 0.1);
    const b = systemLineId(1000, 0.2);
    assert.match(a, /^sys_/);
    assert.notEqual(a, b);
  });
  test('profile name/avatar resolution', () => {
    assert.equal(displayNameOf({ displayName: '  Ada ' }), 'Ada');
    assert.equal(displayNameOf({ fullName: 'Grace', displayName: 'x' }), 'Grace');
    assert.equal(displayNameOf(undefined), 'Someone');
    assert.equal(avatarOf({ photoUrl: 'p' }), 'p');
    assert.equal(avatarOf({}), '');
  });
});
