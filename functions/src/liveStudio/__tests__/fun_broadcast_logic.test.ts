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

import { GiftError, giftPrice, parseGift, pushRecent } from '../gift_logic';

test('gifts: catalog prices, quantity limits, host share, recent list', () => {
  assert.deepEqual(parseGift({ giftId: 'rose' }), { giftId: 'rose', qty: 1 });
  assert.throws(() => parseGift({ giftId: 'not_a_gift' }), GiftError);
  assert.throws(() => parseGift({ giftId: 'rose', qty: 0 }), GiftError);
  assert.throws(() => parseGift({ giftId: 'rose', qty: 1.5 }), GiftError);
  assert.deepEqual(giftPrice('crown', 3), { total: 150, hostCoins: 75 });
  assert.deepEqual(giftPrice('rose', 1), { total: 1, hostCoins: 0 });
  const g = { id: 'x', uid: 'u', name: 'n', avatarUrl: '', giftId: 'rose' as const, qty: 1, coins: 1, atMs: 0 };
  let list = undefined as ReturnType<typeof pushRecent> | undefined;
  for (let i = 0; i < 20; i++) list = pushRecent(list, { ...g, id: `g${i}` });
  assert.equal(list!.length, 15);
  assert.equal(list![0].id, 'g19');
});

import { fromGiphy, parseCommentGif, sanitizeGifQuery } from '../gif_logic';

test('gif comments accept only GIPHY media', () => {
  assert.equal(parseCommentGif(undefined), null);
  assert.deepEqual(parseCommentGif({ id: 'abc123', url: 'https://media2.giphy.com/media/abc123/200w.webp', w: 200, h: 150 }), {
    id: 'abc123',
    url: 'https://media2.giphy.com/media/abc123/200w.webp',
    w: 200,
    h: 150,
  });
  assert.equal(parseCommentGif({ id: 'a', url: 'https://evil.com/x.gif', w: 1, h: 1 }), 'invalid');
  assert.equal(parseCommentGif({ id: 'a', url: 'http://media.giphy.com/x.gif', w: 1, h: 1 }), 'invalid');
  assert.equal(parseCommentGif({ id: 'a', url: 'https://media.giphy.com/x.gif', w: 0, h: 1 }), 'invalid');
  const g = fromGiphy({ id: 'xyz', images: { fixed_width: { webp: 'https://media1.giphy.com/media/xyz/200w.webp?cid=1', width: '200', height: '100' } } });
  assert.equal(g?.url, 'https://media1.giphy.com/media/xyz/200w.webp');
  assert.equal(g?.h, 100);
  assert.equal(sanitizeGifQuery('  cats\n '), 'cats');
});
