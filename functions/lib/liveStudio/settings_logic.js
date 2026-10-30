"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapFrameColor = exports.frameColorOption = exports.clampStudioDim = exports.clampFrameWidth = exports.SettingsValidationError = exports.STUDIO_DIM_STEP = exports.SETTINGS_KEYS = exports.KNOWN_STUDIO_IDS = void 0;
exports.normalizeSettings = normalizeSettings;
exports.applySettingsPatch = applySettingsPatch;
exports.parseStreamId = parseStreamId;
/**
 * LIVE STUDIO v2 — stage customization logic (workstream #6).
 *
 * Pure validation / clamping for `lsSetSettings`. No Firestore or LiveKit
 * imports, so it is unit-testable with node:test.
 */
const contracts_1 = require("./contracts");
/**
 * Studio ids the server accepts.
 *
 * MUST STAY IN SYNC with the keys of `studios` in
 * assets/live_studio/studio-geometry.json (owned by the geometry workstream).
 * Adding a studio to the asset without adding it here makes lsSetSettings
 * reject it.
 */
exports.KNOWN_STUDIO_IDS = ['broadcast_curved_wall'];
exports.SETTINGS_KEYS = [
    'studioId',
    'theme',
    'frameWidth',
    'frameColor',
    'guestSize',
    'showNames',
    'studioDim',
    'speakerMode',
    'layoutPreset',
];
const THEMES = ['dark', 'light'];
const GUEST_SIZES = ['s', 'm', 'l'];
const SPEAKER_MODES = ['hostPinned', 'autoActiveSpeaker', 'manual'];
/** Studio dim slider step (SPEC §1.1: range 0–0.6, step 0.05). */
exports.STUDIO_DIM_STEP = 0.05;
/** Thrown for a bad patch; the callable maps it to `invalid-argument`. */
class SettingsValidationError extends Error {
    constructor(message) {
        super(message);
        this.name = 'SettingsValidationError';
    }
}
exports.SettingsValidationError = SettingsValidationError;
const fail = (m) => {
    throw new SettingsValidationError(m);
};
const isPlainObject = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
const clampFrameWidth = (n) => Math.min(contracts_1.Limits.frameWidthMax, Math.max(contracts_1.Limits.frameWidthMin, Math.round(n)));
exports.clampFrameWidth = clampFrameWidth;
const clampStudioDim = (n) => {
    const c = Math.min(contracts_1.Limits.studioDimMax, Math.max(contracts_1.Limits.studioDimMin, n));
    // Snap to the slider step and strip float noise (0.15000000000000002).
    return Number((Math.round(c / exports.STUDIO_DIM_STEP) * exports.STUDIO_DIM_STEP).toFixed(2));
};
exports.clampStudioDim = clampStudioDim;
/** Canonical option string for [color] in [theme], or null. Case-insensitive. */
const frameColorOption = (theme, color) => { var _a; return (_a = contracts_1.FRAME_COLOR_OPTIONS[theme].find((o) => o.toLowerCase() === color.toLowerCase())) !== null && _a !== void 0 ? _a : null; };
exports.frameColorOption = frameColorOption;
/** The new theme's color at the same index (index 0 when unknown). */
const mapFrameColor = (color, from, to) => {
    const i = contracts_1.FRAME_COLOR_OPTIONS[from].findIndex((o) => o.toLowerCase() === color.toLowerCase());
    return contracts_1.FRAME_COLOR_OPTIONS[to][i >= 0 ? i : 0];
};
exports.mapFrameColor = mapFrameColor;
/**
 * Turns whatever is stored (host doc or studio/state.settings) into a valid
 * StudioSettings, filling theme defaults for missing or bad fields. Never throws.
 */
function normalizeSettings(raw) {
    const j = isPlainObject(raw) ? raw : {};
    const theme = THEMES.includes(j.theme) ? j.theme : 'dark';
    const d = (0, contracts_1.defaultSettings)(theme);
    const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
    const fw = num(j.frameWidth);
    const dim = num(j.studioDim);
    return {
        studioId: typeof j.studioId === 'string' && exports.KNOWN_STUDIO_IDS.includes(j.studioId) ? j.studioId : d.studioId,
        theme,
        frameWidth: fw === null ? d.frameWidth : (0, exports.clampFrameWidth)(fw),
        frameColor: (typeof j.frameColor === 'string' && (0, exports.frameColorOption)(theme, j.frameColor)) || d.frameColor,
        guestSize: GUEST_SIZES.includes(j.guestSize) ? j.guestSize : d.guestSize,
        showNames: typeof j.showNames === 'boolean' ? j.showNames : d.showNames,
        studioDim: dim === null ? d.studioDim : (0, exports.clampStudioDim)(dim),
        speakerMode: SPEAKER_MODES.includes(j.speakerMode)
            ? j.speakerMode
            : d.speakerMode,
        layoutPreset: contracts_1.LAYOUT_PRESETS.includes(j.layoutPreset)
            ? j.layoutPreset
            : d.layoutPreset,
    };
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
function applySettingsPatch(current, partial) {
    if (!isPlainObject(partial))
        fail('settings must be an object.');
    const p = partial;
    const unknown = Object.keys(p).filter((k) => !exports.SETTINGS_KEYS.includes(k));
    if (unknown.length)
        fail(`Unknown settings: ${unknown.join(', ')}.`);
    const next = Object.assign({}, current);
    if ('studioId' in p) {
        if (typeof p.studioId !== 'string' || !exports.KNOWN_STUDIO_IDS.includes(p.studioId))
            fail('Unknown studioId.');
        next.studioId = p.studioId;
    }
    if ('theme' in p) {
        if (!THEMES.includes(p.theme))
            fail('theme must be dark or light.');
        next.theme = p.theme;
    }
    if ('frameWidth' in p) {
        if (typeof p.frameWidth !== 'number' || !Number.isFinite(p.frameWidth))
            fail('frameWidth must be a number.');
        next.frameWidth = (0, exports.clampFrameWidth)(p.frameWidth);
    }
    if ('frameColor' in p) {
        if (typeof p.frameColor !== 'string')
            fail('frameColor must be a string.');
        const opt = (0, exports.frameColorOption)(next.theme, p.frameColor);
        if (!opt)
            fail(`frameColor must be one of ${contracts_1.FRAME_COLOR_OPTIONS[next.theme].join(', ')}.`);
        next.frameColor = opt;
    }
    else if (next.theme !== current.theme) {
        next.frameColor = (0, exports.mapFrameColor)(current.frameColor, current.theme, next.theme);
    }
    if ('guestSize' in p) {
        if (!GUEST_SIZES.includes(p.guestSize))
            fail('guestSize must be s, m or l.');
        next.guestSize = p.guestSize;
    }
    if ('showNames' in p) {
        if (typeof p.showNames !== 'boolean')
            fail('showNames must be a boolean.');
        next.showNames = p.showNames;
    }
    if ('studioDim' in p) {
        if (typeof p.studioDim !== 'number' || !Number.isFinite(p.studioDim))
            fail('studioDim must be a number.');
        next.studioDim = (0, exports.clampStudioDim)(p.studioDim);
    }
    if ('speakerMode' in p) {
        if (!SPEAKER_MODES.includes(p.speakerMode)) {
            fail('speakerMode must be hostPinned, autoActiveSpeaker or manual.');
        }
        next.speakerMode = p.speakerMode;
    }
    if ('layoutPreset' in p) {
        if (!contracts_1.LAYOUT_PRESETS.includes(p.layoutPreset))
            fail('layoutPreset must be studio or gaming.');
        next.layoutPreset = p.layoutPreset;
    }
    const changed = exports.SETTINGS_KEYS.filter((k) => next[k] !== current[k]);
    return { next, changed };
}
/** Validates the callable's `streamId` argument: a non-empty id or null/absent. */
function parseStreamId(v) {
    if (v === null || v === undefined)
        return null;
    if (typeof v !== 'string' || v.trim().length === 0 || v.length > 128 || v.includes('/')) {
        fail('streamId must be a stream id or null.');
    }
    return v.trim();
}
//# sourceMappingURL=settings_logic.js.map