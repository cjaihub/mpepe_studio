import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { FRAME_COLOR_OPTIONS, StudioSettings, defaultSettings } from '../contracts';
import {
  KNOWN_STUDIO_IDS,
  SETTINGS_KEYS,
  SettingsValidationError,
  applySettingsPatch,
  clampFrameWidth,
  clampStudioDim,
  frameColorOption,
  mapFrameColor,
  normalizeSettings,
  parseStreamId,
} from '../settings_logic';

const dark = (): StudioSettings => defaultSettings('dark');
const rejects = (fn: () => unknown, re?: RegExp) =>
  assert.throws(fn, (e: unknown) => e instanceof SettingsValidationError && (!re || re.test(e.message)));

test('settings keys cover the contract shape', () => {
  assert.deepEqual([...SETTINGS_KEYS].sort(), Object.keys(dark()).sort());
});

test('known studios include the default studio', () => {
  assert.ok(KNOWN_STUDIO_IDS.includes(dark().studioId));
});

test('non-object patches are rejected', () => {
  for (const p of [null, undefined, 3, 'x', [], true]) rejects(() => applySettingsPatch(dark(), p));
});

test('unknown keys are rejected, naming them', () => {
  rejects(() => applySettingsPatch(dark(), { theme: 'light', hacked: 1 }), /hacked/);
  rejects(() => applySettingsPatch(dark(), { updatedAt: 1 }), /updatedAt/);
});

test('empty patch is a no-op', () => {
  const r = applySettingsPatch(dark(), {});
  assert.deepEqual(r.next, dark());
  assert.deepEqual(r.changed, []);
});

test('same value reports no change', () => {
  assert.deepEqual(applySettingsPatch(dark(), { frameWidth: 4, showNames: true }).changed, []);
});

test('frameWidth is rounded and clamped to 0–12', () => {
  assert.equal(applySettingsPatch(dark(), { frameWidth: 40 }).next.frameWidth, 12);
  assert.equal(applySettingsPatch(dark(), { frameWidth: -3 }).next.frameWidth, 0);
  assert.equal(applySettingsPatch(dark(), { frameWidth: 6.6 }).next.frameWidth, 7);
  assert.deepEqual(applySettingsPatch(dark(), { frameWidth: 7 }).changed, ['frameWidth']);
  assert.equal(clampFrameWidth(12.4), 12);
});

test('frameWidth rejects non-numbers', () => {
  for (const v of ['4', null, NaN, Infinity, true]) rejects(() => applySettingsPatch(dark(), { frameWidth: v }));
});

test('studioDim is clamped to 0–0.6 and snapped to 0.05', () => {
  assert.equal(applySettingsPatch(dark(), { studioDim: 2 }).next.studioDim, 0.6);
  assert.equal(applySettingsPatch(dark(), { studioDim: -1 }).next.studioDim, 0);
  assert.equal(applySettingsPatch(dark(), { studioDim: 0.33 }).next.studioDim, 0.35);
  assert.equal(clampStudioDim(0.1 + 0.05), 0.15);
  for (const v of ['0.2', null, NaN]) rejects(() => applySettingsPatch(dark(), { studioDim: v }));
});

test('studioId must be a known studio', () => {
  rejects(() => applySettingsPatch(dark(), { studioId: 'not_a_studio' }), /studioId/);
  rejects(() => applySettingsPatch(dark(), { studioId: 7 }));
  assert.equal(applySettingsPatch(dark(), { studioId: KNOWN_STUDIO_IDS[0] }).next.studioId, KNOWN_STUDIO_IDS[0]);
});

test('theme must be dark or light', () => {
  rejects(() => applySettingsPatch(dark(), { theme: 'sepia' }));
});

test('frameColor must be one of the theme options (case-insensitive, stored canonical)', () => {
  rejects(() => applySettingsPatch(dark(), { frameColor: '#123456' }), /frameColor/);
  rejects(() => applySettingsPatch(dark(), { frameColor: FRAME_COLOR_OPTIONS.light[0] }));
  rejects(() => applySettingsPatch(dark(), { frameColor: 5 }));
  assert.equal(applySettingsPatch(dark(), { frameColor: '#2f7bff' }).next.frameColor, '#2F7BFF');
});

test('switching theme maps frameColor by index', () => {
  for (let i = 0; i < 4; i++) {
    const cur = { ...dark(), frameColor: FRAME_COLOR_OPTIONS.dark[i] };
    const r = applySettingsPatch(cur, { theme: 'light' });
    assert.equal(r.next.frameColor, FRAME_COLOR_OPTIONS.light[i]);
    assert.deepEqual(r.changed.includes('theme'), true);
  }
  const back = applySettingsPatch({ ...defaultSettings('light'), frameColor: '#8C97AE' }, { theme: 'dark' });
  assert.equal(back.next.frameColor, '#2A3550');
});

test('theme switch with an explicit frameColor validates against the new theme', () => {
  assert.equal(applySettingsPatch(dark(), { theme: 'light', frameColor: '#8C97AE' }).next.frameColor, '#8C97AE');
  rejects(() => applySettingsPatch(dark(), { theme: 'light', frameColor: '#15151B' }));
});

test('mapFrameColor falls back to index 0 for an unknown color', () => {
  assert.equal(mapFrameColor('#000000', 'dark', 'light'), FRAME_COLOR_OPTIONS.light[0]);
  assert.equal(frameColorOption('light', '#ff2d75'), '#FF2D75');
  assert.equal(frameColorOption('light', '#15151B'), null);
});

test('guestSize, showNames and speakerMode are validated', () => {
  assert.equal(applySettingsPatch(dark(), { guestSize: 'l' }).next.guestSize, 'l');
  rejects(() => applySettingsPatch(dark(), { guestSize: 'xl' }));
  assert.equal(applySettingsPatch(dark(), { showNames: false }).next.showNames, false);
  rejects(() => applySettingsPatch(dark(), { showNames: 'false' }));
  for (const m of ['hostPinned', 'autoActiveSpeaker', 'manual']) {
    assert.equal(applySettingsPatch(dark(), { speakerMode: m }).next.speakerMode, m);
  }
  rejects(() => applySettingsPatch(dark(), { speakerMode: 'auto' }), /speakerMode/);
});

test('a multi-field patch reports every changed key', () => {
  const r = applySettingsPatch(dark(), { guestSize: 's', showNames: false, speakerMode: 'manual' });
  assert.deepEqual(r.changed, ['guestSize', 'showNames', 'speakerMode']);
});

test('applySettingsPatch does not mutate its input', () => {
  const cur = dark();
  applySettingsPatch(cur, { frameWidth: 9, theme: 'light' });
  assert.deepEqual(cur, dark());
});

test('normalizeSettings fills theme defaults and repairs bad stored values', () => {
  assert.deepEqual(normalizeSettings(undefined), defaultSettings('dark'));
  assert.deepEqual(normalizeSettings({ theme: 'light' }), defaultSettings('light'));
  const n = normalizeSettings({
    theme: 'light',
    studioId: 'gone',
    frameWidth: 99,
    frameColor: '#15151B',
    guestSize: 'huge',
    showNames: 'yes',
    studioDim: 0.9,
    speakerMode: 'x',
    updatedAt: 123,
  });
  assert.deepEqual(n, { ...defaultSettings('light'), frameWidth: 12, studioDim: 0.6 });
  assert.equal((n as unknown as Record<string, unknown>).updatedAt, undefined);
});

test('parseStreamId accepts null/absent and ids, rejects junk', () => {
  assert.equal(parseStreamId(null), null);
  assert.equal(parseStreamId(undefined), null);
  assert.equal(parseStreamId('abc'), 'abc');
  for (const v of ['', '  ', 5, 'a/b', 'x'.repeat(129)]) rejects(() => parseStreamId(v));
});
