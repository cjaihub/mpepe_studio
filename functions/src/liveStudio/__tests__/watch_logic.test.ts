import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  EMPTY_WATCH,
  WatchError,
  applyWatchOp,
  fromYouTubeItem,
  normalizeWatch,
  parseWatchOp,
  targetPositionMs,
  validateBrowserUrl,
} from '../watch_logic';

const NOW = 1_000_000;
const VID = 'dQw4w9WgXcQ';

const isWatchError = (code: string) => (e: unknown) => e instanceof WatchError && e.code === code;

test('parseWatchOp: youtube needs an 11-char id and keeps only ytimg thumbs', () => {
  const op = parseWatchOp({ op: 'youtube', videoId: VID, title: ' Song ', thumbUrl: 'https://evil.example/x.jpg' });
  assert.deepEqual(op, { op: 'youtube', video: { videoId: VID, title: 'Song', channel: '', thumbUrl: '' } });
  const ok = parseWatchOp({ op: 'youtube', videoId: VID, thumbUrl: 'https://i.ytimg.com/vi/x/hq.jpg' });
  assert.equal(ok.op === 'youtube' && ok.video.thumbUrl, 'https://i.ytimg.com/vi/x/hq.jpg');
  assert.throws(() => parseWatchOp({ op: 'youtube', videoId: 'short' }), isWatchError('invalid-argument'));
  assert.throws(() => parseWatchOp({ op: 'youtube', videoId: 'aaaaaaaaaa/' }), isWatchError('invalid-argument'));
});

test('parseWatchOp: positions, rates and unknown ops', () => {
  assert.deepEqual(parseWatchOp({ op: 'seek', positionMs: 1500.4 }), { op: 'seek', positionMs: 1500 });
  assert.throws(() => parseWatchOp({ op: 'play', positionMs: -1 }), isWatchError('invalid-argument'));
  assert.throws(() => parseWatchOp({ op: 'play' }), isWatchError('invalid-argument'));
  assert.deepEqual(parseWatchOp({ op: 'rate', rate: 1.5 }), { op: 'rate', rate: 1.5 });
  assert.throws(() => parseWatchOp({ op: 'rate', rate: 3 }), isWatchError('invalid-argument'));
  assert.throws(() => parseWatchOp({ op: 'rip' }), isWatchError('invalid-argument'));
});

test('validateBrowserUrl: https public pages only, no look-alikes', () => {
  assert.equal(validateBrowserUrl('https://en.wikipedia.org/wiki/Flutter'), 'https://en.wikipedia.org/wiki/Flutter');
  for (const bad of [
    'http://example.com',
    'javascript:alert(1)',
    'file:///etc/passwd',
    'https://localhost/x',
    'https://192.168.1.1/',
    'https://user:pw@example.com/',
    'https://intranet/',
    'not a url',
    '',
  ]) {
    assert.throws(() => validateBrowserUrl(bad), (e: unknown) => e instanceof WatchError, bad);
  }
  assert.throws(() => validateBrowserUrl('https://faceb00k.com/'), isWatchError('failed-precondition'));
});

test('applyWatchOp: youtube starts playing at 0 and the target moves with the clock', () => {
  const w = applyWatchOp(EMPTY_WATCH, parseWatchOp({ op: 'youtube', videoId: VID }), 'host', NOW);
  assert.equal(w.kind, 'youtube');
  assert.equal(w.state, 'playing');
  assert.equal(w.rev, 1);
  assert.equal(w.by, 'host');
  assert.equal(targetPositionMs(w, NOW + 4000), 4000);
});

test('applyWatchOp: pause freezes, play re-anchors, rate keeps the position', () => {
  let w = applyWatchOp(EMPTY_WATCH, parseWatchOp({ op: 'youtube', videoId: VID }), 'host', NOW);
  w = applyWatchOp(w, { op: 'pause', positionMs: 3000 }, 'host', NOW + 3000);
  assert.equal(targetPositionMs(w, NOW + 99_000), 3000);
  w = applyWatchOp(w, { op: 'play', positionMs: 3000 }, 'host', NOW + 10_000);
  assert.equal(targetPositionMs(w, NOW + 12_000), 5000);
  w = applyWatchOp(w, { op: 'rate', rate: 2 }, 'host', NOW + 12_000);
  assert.equal(w.positionMs, 5000);
  assert.equal(targetPositionMs(w, NOW + 13_000), 7000);
  w = applyWatchOp(w, { op: 'ended' }, 'host', NOW + 14_000);
  assert.equal(w.state, 'ended');
  assert.equal(targetPositionMs(w, NOW + 20_000), 9000);
});

test('applyWatchOp: playback ops need a video; browser and stop replace the layer', () => {
  assert.throws(() => applyWatchOp(EMPTY_WATCH, { op: 'play', positionMs: 0 }, 'h', NOW), isWatchError('failed-precondition'));
  const b = applyWatchOp(EMPTY_WATCH, { op: 'browser', url: 'https://example.com/' }, 'h', NOW);
  assert.equal(b.kind, 'browser');
  assert.equal(b.youtube, null);
  const s = applyWatchOp(b, { op: 'stop' }, 'h', NOW + 1);
  assert.equal(s.kind, null);
  assert.equal(s.browser, null);
  assert.equal(s.rev, 2);
});

test('normalizeWatch: tolerates missing and malformed docs', () => {
  assert.deepEqual(normalizeWatch(null), EMPTY_WATCH);
  const n = normalizeWatch({ kind: 'tv', youtube: { videoId: 'x' }, state: 'weird', rate: 'fast' });
  assert.equal(n.kind, null);
  assert.equal(n.youtube, null);
  assert.equal(n.state, 'paused');
  assert.equal(n.rate, 1);
});

test('fromYouTubeItem: maps search.list items, drops channels and playlists', () => {
  const hit = fromYouTubeItem({
    id: { kind: 'youtube#video', videoId: VID },
    snippet: {
      title: 'Rock &amp; Roll &#39;Live&#39;',
      channelTitle: 'Band',
      liveBroadcastContent: 'live',
      thumbnails: { high: { url: 'https://i.ytimg.com/vi/x/hqdefault.jpg' } },
    },
  });
  assert.deepEqual(hit, {
    videoId: VID,
    title: "Rock & Roll 'Live'",
    channel: 'Band',
    thumbUrl: 'https://i.ytimg.com/vi/x/hqdefault.jpg',
    live: true,
  });
  assert.equal(fromYouTubeItem({ id: { kind: 'youtube#channel', channelId: 'UC1' } }), null);
  assert.equal(fromYouTubeItem(null), null);
});
