/**
 * LIVE STUDIO v2 — stage customization logic (workstream #6).
 *
 * Pure validation / clamping for `lsSetSettings`. No Firestore or LiveKit
 * imports, so it is unit-testable with node:test.
 */
import {
  FRAME_COLOR_OPTIONS,
  GuestSize,
  Limits,
  SpeakerMode,
  StudioSettings,
  StudioTheme,
  defaultSettings,
} from './contracts';

/**
 * Studio ids the server accepts.
 *
 * MUST STAY IN SYNC with the keys of `studios` in
 * assets/live_studio/studio-geometry.json (owned by the geometry workstream).
 * Adding a studio to the asset without adding it here makes lsSetSettings
 * reject it.
 */
export const KNOWN_STUDIO_IDS: readonly string[] = ['broadcast_curved_wall'];

export const SETTINGS_KEYS: readonly (keyof StudioSettings)[] = [
  'studioId',
  'theme',
  'frameWidth',
  'frameColor',
  'guestSize',
  'showNames',
  'studioDim',
  'speakerMode',
];

const THEMES: readonly StudioTheme[] = ['dark', 'light'];
const GUEST_SIZES: readonly GuestSize[] = ['s', 'm', 'l'];
const SPEAKER_MODES: readonly SpeakerMode[] = ['hostPinned', 'autoActiveSpeaker', 'manual'];

/** Studio dim slider step (SPEC §1.1: range 0–0.6, step 0.05). */
export const STUDIO_DIM_STEP = 0.05;

/** Thrown for a bad patch; the callable maps it to `invalid-argument`. */
export class SettingsValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SettingsValidationError';
  }
}

const fail = (m: string): never => {
  throw new SettingsValidationError(m);
};

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

export const clampFrameWidth = (n: number): number =>
  Math.min(Limits.frameWidthMax, Math.max(Limits.frameWidthMin, Math.round(n)));

export const clampStudioDim = (n: number): number => {
  const c = Math.min(Limits.studioDimMax, Math.max(Limits.studioDimMin, n));
  // Snap to the slider step and strip float noise (0.15000000000000002).
  return Number((Math.round(c / STUDIO_DIM_STEP) * STUDIO_DIM_STEP).toFixed(2));
};

/** Canonical option string for [color] in [theme], or null. Case-insensitive. */
export const frameColorOption = (theme: StudioTheme, color: string): string | null =>
  FRAME_COLOR_OPTIONS[theme].find((o) => o.toLowerCase() === color.toLowerCase()) ?? null;

/** The new theme's color at the same index (index 0 when unknown). */
export const mapFrameColor = (color: string, from: StudioTheme, to: StudioTheme): string => {
  const i = FRAME_COLOR_OPTIONS[from].findIndex((o) => o.toLowerCase() === color.toLowerCase());
  return FRAME_COLOR_OPTIONS[to][i >= 0 ? i : 0];
};

/**
 * Turns whatever is stored (host doc or studio/state.settings) into a valid
 * StudioSettings, filling theme defaults for missing or bad fields. Never throws.
 */
export function normalizeSettings(raw: unknown): StudioSettings {
  const j = isPlainObject(raw) ? raw : {};
  const theme: StudioTheme = THEMES.includes(j.theme as StudioTheme) ? (j.theme as StudioTheme) : 'dark';
  const d = defaultSettings(theme);
  const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const fw = num(j.frameWidth);
  const dim = num(j.studioDim);
  return {
    studioId:
      typeof j.studioId === 'string' && KNOWN_STUDIO_IDS.includes(j.studioId) ? j.studioId : d.studioId,
    theme,
    frameWidth: fw === null ? d.frameWidth : clampFrameWidth(fw),
    frameColor: (typeof j.frameColor === 'string' && frameColorOption(theme, j.frameColor)) || d.frameColor,
    guestSize: GUEST_SIZES.includes(j.guestSize as GuestSize) ? (j.guestSize as GuestSize) : d.guestSize,
    showNames: typeof j.showNames === 'boolean' ? j.showNames : d.showNames,
    studioDim: dim === null ? d.studioDim : clampStudioDim(dim),
    speakerMode: SPEAKER_MODES.includes(j.speakerMode as SpeakerMode)
      ? (j.speakerMode as SpeakerMode)
      : d.speakerMode,
  };
}

export interface SettingsPatchResult {
  next: StudioSettings;
  /** Keys whose value actually changed (empty = no-op). */
  changed: (keyof StudioSettings)[];
}

/**
 * Validates [partial] and applies it to [current] (assumed normalized).
 *
 * - unknown keys, wrong types and unknown enum values are rejected;
 * - frameWidth / studioDim are clamped (and rounded / snapped), not rejected;
 * - studioId must be in [KNOWN_STUDIO_IDS];
 * - frameColor must be one of the resulting theme's options;
 * - a theme switch without a frameColor maps the color to the same index in
 *   the new theme's options.
 */
export function applySettingsPatch(current: StudioSettings, partial: unknown): SettingsPatchResult {
  if (!isPlainObject(partial)) fail('settings must be an object.');
  const p = partial as Record<string, unknown>;
  const unknown = Object.keys(p).filter((k) => !SETTINGS_KEYS.includes(k as keyof StudioSettings));
  if (unknown.length) fail(`Unknown settings: ${unknown.join(', ')}.`);

  const next: StudioSettings = { ...current };

  if ('studioId' in p) {
    if (typeof p.studioId !== 'string' || !KNOWN_STUDIO_IDS.includes(p.studioId)) fail('Unknown studioId.');
    next.studioId = p.studioId as string;
  }
  if ('theme' in p) {
    if (!THEMES.includes(p.theme as StudioTheme)) fail('theme must be dark or light.');
    next.theme = p.theme as StudioTheme;
  }
  if ('frameWidth' in p) {
    if (typeof p.frameWidth !== 'number' || !Number.isFinite(p.frameWidth)) fail('frameWidth must be a number.');
    next.frameWidth = clampFrameWidth(p.frameWidth as number);
  }
  if ('frameColor' in p) {
    if (typeof p.frameColor !== 'string') fail('frameColor must be a string.');
    const opt = frameColorOption(next.theme, p.frameColor as string);
    if (!opt) fail(`frameColor must be one of ${FRAME_COLOR_OPTIONS[next.theme].join(', ')}.`);
    next.frameColor = opt as string;
  } else if (next.theme !== current.theme) {
    next.frameColor = mapFrameColor(current.frameColor, current.theme, next.theme);
  }
  if ('guestSize' in p) {
    if (!GUEST_SIZES.includes(p.guestSize as GuestSize)) fail('guestSize must be s, m or l.');
    next.guestSize = p.guestSize as GuestSize;
  }
  if ('showNames' in p) {
    if (typeof p.showNames !== 'boolean') fail('showNames must be a boolean.');
    next.showNames = p.showNames as boolean;
  }
  if ('studioDim' in p) {
    if (typeof p.studioDim !== 'number' || !Number.isFinite(p.studioDim)) fail('studioDim must be a number.');
    next.studioDim = clampStudioDim(p.studioDim as number);
  }
  if ('speakerMode' in p) {
    if (!SPEAKER_MODES.includes(p.speakerMode as SpeakerMode)) {
      fail('speakerMode must be hostPinned, autoActiveSpeaker or manual.');
    }
    next.speakerMode = p.speakerMode as SpeakerMode;
  }

  const changed = SETTINGS_KEYS.filter((k) => next[k] !== current[k]);
  return { next, changed };
}

/** Validates the callable's `streamId` argument: a non-empty id or null/absent. */
export function parseStreamId(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== 'string' || v.trim().length === 0 || v.length > 128 || v.includes('/')) {
    fail('streamId must be a stream id or null.');
  }
  return (v as string).trim();
}
