import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { chatModeRequirement, parseChatMode, readChatMode, followDocId, isAcceptedFollow, SLOW_MAX_S, SLOW_MIN_S } from '../controls_logic';

test('parseChatMode validates and clamps', () => {
  assert.deepEqual(parseChatMode({ mode: 'open' }), { ok: true, value: { mode: 'open', slowSeconds: 0 } });
  assert.deepEqual(parseChatMode({ mode: 'slow' }), { ok: true, value: { mode: 'slow', slowSeconds: 15 } });
  assert.deepEqual(parseChatMode({ mode: 'slow', slowSeconds: 1 }), { ok: true, value: { mode: 'slow', slowSeconds: SLOW_MIN_S } });
  assert.deepEqual(parseChatMode({ mode: 'slow', slowSeconds: 9999 }), { ok: true, value: { mode: 'slow', slowSeconds: SLOW_MAX_S } });
  assert.equal(parseChatMode({ mode: 'party' }).ok, false);
  assert.equal(parseChatMode({ mode: 'slow', slowSeconds: 'x' }).ok, false);
});

test('readChatMode falls back to open on bad data', () => {
  assert.equal(readChatMode(undefined).mode, 'open');
  assert.equal(readChatMode({ mode: 'nope' }).mode, 'open');
  assert.equal(readChatMode({ mode: 'followers' }).mode, 'followers');
});

test('managers are exempt; viewers and guests are limited', () => {
  const slow = { mode: 'slow' as const, slowSeconds: 20 };
  const fol = { mode: 'followers' as const, slowSeconds: 0 };
  assert.deepEqual(chatModeRequirement(slow, 'host'), { kind: 'none' });
  assert.deepEqual(chatModeRequirement(slow, 'coHost'), { kind: 'none' });
  assert.deepEqual(chatModeRequirement(slow, 'viewer'), { kind: 'slow', seconds: 20 });
  assert.deepEqual(chatModeRequirement(fol, 'guest'), { kind: 'follower' });
  assert.deepEqual(chatModeRequirement({ mode: 'open', slowSeconds: 0 }, 'viewer'), { kind: 'none' });
});

test('follow doc id matches RelationshipRepository', () => {
  assert.equal(followDocId('viewer1', 'host1'), 'viewer1_host1');
  assert.equal(isAcceptedFollow('accepted'), true);
  assert.equal(isAcceptedFollow('pending'), false);
});
