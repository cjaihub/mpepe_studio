import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { FunError, applyVote, newPoll, newTimer, parseOp, pickWinner, pollAccepting, raffleEntrants } from '../fun_logic';
import { BroadcastError, ingestUrl, masked, parseDestination, recordingPath } from '../broadcast_logic';

test('poll validation and voting', () => {
  const p = newPoll({ question: ' Best song? ', options: ['A', 'B', 'C'], seconds: 30 }, 'p1', 1000);
  assert.equal(p.question, 'Best song?');
  assert.deepEqual(p.counts, [0, 0, 0]);
  assert.equal(p.endsAtMs, 31_000);
  assert.ok(pollAccepting(p, 5000));
  assert.ok(!pollAccepting(p, 31_000));
  let q = applyVote(p, null, 1);
  q = applyVote(q, 1, 2);
  assert.deepEqual(q.counts, [0, 0, 1]);
  assert.throws(() => applyVote(q, null, 3), FunError);
  assert.throws(() => newPoll({ question: 'x', options: ['a'] }, 'p', 0), FunError);
  assert.throws(() => newPoll({ question: 'x', options: ['a', 'A'] }, 'p', 0), FunError);
  assert.equal(newPoll({ question: 'x', options: ['a', 'b'], seconds: 1 }, 'p', 0).endsAtMs, 15_000);
});

test('timer and ops', () => {
  const t = newTimer({ seconds: 99999 }, 0);
  assert.equal(t.label, 'Countdown');
  assert.equal(t.endsAtMs, 3_600_000);
  assert.equal(parseOp('celebrate'), 'celebrate');
  assert.throws(() => parseOp('nuke'), FunError);
});

test('raffle picks distinct recent commenters, never the host', () => {
  const now = 20 * 60 * 1000;
  const c = (uid: string, ts: number) => ({ uid, name: uid, avatarUrl: '', ts });
  const e = raffleEntrants([c('h', now), c('a', now), c('a', now - 1), c('b', now - 5000), c('old', 0)], now, ['h']);
  assert.deepEqual(e.map((x) => x.uid), ['a', 'b']);
  assert.equal(pickWinner(e, 0.99)?.uid, 'b');
  assert.equal(pickWinner([], 0.5), null);
});

test('destinations validate, default ingest and mask the key', () => {
  const d = parseDestination({ platform: 'youtube', key: 'abcd-1234' }, 'd1');
  assert.equal(ingestUrl(d), 'rtmp://a.rtmp.youtube.com/live2/abcd-1234');
  assert.equal(masked(d).keyHint, '••••1234');
  assert.equal('key' in masked(d), false);
  const tt = parseDestination({ platform: 'tiktok', url: 'rtmp://push.tiktok.com/live/', key: 'k1', label: 'My TikTok' }, 'd2');
  assert.equal(ingestUrl(tt), 'rtmp://push.tiktok.com/live/k1');
  assert.throws(() => parseDestination({ platform: 'tiktok', key: 'k' }, 'x'), BroadcastError);
  assert.throws(() => parseDestination({ platform: 'custom', url: 'http://x', key: 'k' }, 'x'), BroadcastError);
  assert.throws(() => parseDestination({ platform: 'youtube', key: 'a b' }, 'x'), BroadcastError);
  assert.equal(recordingPath('h', 's'), 'users/h/files/live_recordings/s.mp4');
});
