import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { GAME_TITLE_MAX_LENGTH, defaultSettings } from '../contracts';
import { normalizeSettings, applySettingsPatch } from '../settings_logic';
import {
  StartValidationError,
  applyStartKind,
  buildInitialState,
  buildStreamDoc,
  parseStartKind,
} from '../media_logic';

const profile = { displayName: 'A', avatarUrl: '' };

test('kind defaults to studio and ignores gameTitle', () => {
  assert.deepEqual(parseStartKind(undefined), { kind: 'studio', gameTitle: null });
  assert.deepEqual(parseStartKind({ title: 'x' }), { kind: 'studio', gameTitle: null });
  assert.deepEqual(parseStartKind({ kind: 'studio', gameTitle: 'Ludo' }), { kind: 'studio', gameTitle: null });
});

test('gaming kind trims the game title', () => {
  assert.deepEqual(parseStartKind({ kind: 'gaming', gameTitle: '  Free Fire  ' }), {
    kind: 'gaming',
    gameTitle: 'Free Fire',
  });
  assert.deepEqual(parseStartKind({ kind: 'gaming' }), { kind: 'gaming', gameTitle: null });
  assert.deepEqual(parseStartKind({ kind: 'gaming', gameTitle: '   ' }), { kind: 'gaming', gameTitle: null });
  const max = 'x'.repeat(GAME_TITLE_MAX_LENGTH);
  assert.equal(parseStartKind({ kind: 'gaming', gameTitle: max }).gameTitle, max);
});

test('bad kind / gameTitle are rejected', () => {
  assert.throws(() => parseStartKind({ kind: 'karaoke' }), StartValidationError);
  assert.throws(() => parseStartKind({ kind: 'gaming', gameTitle: 'x'.repeat(61) }), StartValidationError);
  assert.throws(() => parseStartKind({ kind: 'gaming', gameTitle: 'Ludo\nKing' }), StartValidationError);
  assert.throws(() => parseStartKind({ kind: 'gaming', gameTitle: 'Ludo\u0000' }), StartValidationError);
  assert.throws(() => parseStartKind({ kind: 'gaming', gameTitle: 42 }), StartValidationError);
});

test('layout preset follows the kind, not saved settings', () => {
  const savedGaming = normalizeSettings({ layoutPreset: 'gaming' });
  assert.equal(savedGaming.layoutPreset, 'gaming');
  assert.equal(applyStartKind(savedGaming, 'studio').layoutPreset, 'studio');
  assert.equal(applyStartKind(defaultSettings(), 'gaming').layoutPreset, 'gaming');
  assert.equal(normalizeSettings({ layoutPreset: '??' }).layoutPreset, 'studio');
});

test('settings patch accepts layoutPreset', () => {
  const r = applySettingsPatch(defaultSettings(), { layoutPreset: 'gaming' });
  assert.equal(r.next.layoutPreset, 'gaming');
  assert.deepEqual(r.changed, ['layoutPreset']);
  assert.throws(() => applySettingsPatch(defaultSettings(), { layoutPreset: 'arena' }));
});

test('gaming state and stream doc', () => {
  const settings = applyStartKind(defaultSettings(), 'gaming');
  const s = buildInitialState({ streamId: 's', hostId: 'h', title: 'T', settings, nowMs: 0, gameTitle: 'Ludo' });
  assert.equal(s.settings.layoutPreset, 'gaming');
  assert.equal(s.gameTitle, 'Ludo');
  const d = buildStreamDoc({ streamId: 's', hostId: 'h', title: 'T', profile, kind: 'gaming', gameTitle: 'Ludo' });
  assert.equal(d.liveKind, 'gaming');
  assert.equal(d.category, 'Gaming');
  assert.equal(d.gameTitle, 'Ludo');
  assert.equal(d.studioVersion, 2);
});

test('studio state and stream doc carry no gaming fields', () => {
  const s = buildInitialState({ streamId: 's', hostId: 'h', title: 'T', settings: defaultSettings(), nowMs: 0 });
  assert.equal('gameTitle' in s, false);
  const d = buildStreamDoc({ streamId: 's', hostId: 'h', title: 'T', profile }) as Record<string, unknown>;
  assert.equal('liveKind' in d, false);
  assert.equal('category' in d, false);
  const g = buildStreamDoc({ streamId: 's', hostId: 'h', title: 'T', profile, kind: 'gaming' }) as Record<
    string,
    unknown
  >;
  assert.equal(g.liveKind, 'gaming');
  assert.equal('gameTitle' in g, false);
});
