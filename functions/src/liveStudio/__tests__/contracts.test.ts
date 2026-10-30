import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { GAME_TITLE_MAX_LENGTH, LAYOUT_PRESETS, StudioState, defaultSettings, emptyStage, Limits } from '../contracts';

test('defaults mirror the Dart contracts', () => {
  assert.equal(defaultSettings('light').frameColor, '#3B4763');
  assert.equal(defaultSettings('light').studioDim, 0);
  assert.equal(defaultSettings().guestSize, 'm');
  assert.equal(emptyStage('h').wall.length, Limits.wallSlots);
});

test('layout preset defaults to studio; gameTitle is optional', () => {
  assert.equal(defaultSettings().layoutPreset, 'studio');
  assert.equal(defaultSettings('light').layoutPreset, 'studio');
  const s: StudioState = {
    schemaVersion: 1,
    streamId: 's',
    hostId: 'h',
    title: 'T',
    status: 'live',
    seq: 0,
    settings: { ...defaultSettings(), layoutPreset: 'gaming' },
    stage: emptyStage('h'),
    table: { mode: 'goods', goods: null, screen: null, watch: null },
    counts: { viewers: 0, participants: 1, loves: 0, sparkles: 0, shares: 0 },
    gameTitle: 'Ludo',
  };
  const back = JSON.parse(JSON.stringify(s)) as StudioState;
  assert.deepEqual(back, s);
  assert.ok(GAME_TITLE_MAX_LENGTH === 60);
  assert.deepEqual([...LAYOUT_PRESETS], ['studio', 'gaming']);
});
