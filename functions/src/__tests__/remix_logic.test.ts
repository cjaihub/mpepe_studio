import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { REMIX_ORIGINAL_SHARE, splitRemixCoins, remixAllowed } from '../remix_logic';
import { HOST_SHARE } from '../liveStudio/gift_logic';

test('100-coin gift on a remix: platform 20, original 20, remixer 60', () => {
  const creator = Math.ceil(100 * HOST_SHARE);
  const s = splitRemixCoins(creator);
  assert.equal(creator, 80);
  assert.deepEqual(s, { remixerCoins: 60, originalCoins: 20 });
  assert.equal(REMIX_ORIGINAL_SHARE, 0.25);
});

test('small gifts never lose coins and still reach the remixer', () => {
  for (const c of [0, 1, 2, 3, 7, 999]) {
    const s = splitRemixCoins(c);
    assert.equal(s.remixerCoins + s.originalCoins, c);
    if (c > 0) assert.ok(s.remixerCoins >= 1);
  }
});

test('remix permission follows allowRemix, then allowDuet', () => {
  const base = { authorId: 'a', visibility: 'public' };
  assert.deepEqual(remixAllowed({ ...base, permissions: { allowRemix: true } }, 'b', 'a'), { ok: true });
  assert.deepEqual(remixAllowed({ ...base, permissions: { allowRemix: false } }, 'b', 'a'), { ok: false, reason: 'not_allowed' });
  assert.deepEqual(remixAllowed({ ...base, permissions: { allowDuet: false } }, 'b', 'a'), { ok: false, reason: 'not_allowed' });
  assert.deepEqual(remixAllowed({ ...base }, 'b', 'a'), { ok: true });
  assert.deepEqual(remixAllowed({ ...base }, 'a', 'a'), { ok: false, reason: 'own_post' });
  assert.deepEqual(remixAllowed({ ...base, visibility: 'private' }, 'b', 'a'), { ok: false, reason: 'not_public' });
  assert.deepEqual(remixAllowed({ ...base }, 'b', 'x'), { ok: false, reason: 'bad_request' });
  assert.deepEqual(remixAllowed(undefined, 'b', 'a'), { ok: false, reason: 'missing' });
});
