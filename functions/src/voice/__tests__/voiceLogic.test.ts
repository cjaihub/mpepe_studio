import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { engineFor, signStreamToken, validVoiceUrl } from '../voiceLogic';

test('stream tokens match the Python voice server byte for byte', () => {
  // Made by services/voice/voice/logic.py sign_stream_token(b"k"*32, "user_123456", "call1", ttl_s=60, now=1000)
  const python = 'eyJjYWxsIjoiY2FsbDEiLCJleHAiOjEwNjAsInVpZCI6InVzZXJfMTIzNDU2In0.Jms7REC0ywoNU3z1W5M8FxKudUGlAqMfY4nwwziwA_w';
  assert.equal(signStreamToken(Buffer.from('k'.repeat(32)), 'user_123456', 'call1', 60, 1000), python);
});

test('only https Cloud Run URLs are called', () => {
  assert.equal(validVoiceUrl('https://oneova-voice-abc-uc.a.run.app/'), 'https://oneova-voice-abc-uc.a.run.app');
  assert.equal(validVoiceUrl('http://oneova-voice-abc-uc.a.run.app'), null);
  assert.equal(validVoiceUrl('https://evil.example.com'), null);
  assert.equal(validVoiceUrl('https://x.run.app?y=1'), null);
});

test('languages route to cloning or conversion', () => {
  assert.equal(engineFor('sw-KE'), 'clone');
  assert.equal(engineFor('yo'), 'convert');
});

import { splitForSpeak } from '../voice';

test('long translations are split into sentence chunks the voice server accepts', () => {
  const text = Array.from({ length: 30 }, (_, i) => `Sentence number ${i} is here.`).join(' ');
  const parts = splitForSpeak(text);
  assert.ok(parts.length > 1);
  assert.ok(parts.every((p) => p.length <= 400));
  assert.equal(parts.join(' ').split(' ').length, text.split(' ').length);
  assert.deepEqual(splitForSpeak('Hi.'), ['Hi.']);
});
