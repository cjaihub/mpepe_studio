"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert/strict"));
const contracts_1 = require("../contracts");
const settings_logic_1 = require("../settings_logic");
const dark = () => (0, contracts_1.defaultSettings)('dark');
const rejects = (fn, re) => assert.throws(fn, (e) => e instanceof settings_logic_1.SettingsValidationError && (!re || re.test(e.message)));
(0, node_test_1.test)('settings keys cover the contract shape', () => {
    assert.deepEqual([...settings_logic_1.SETTINGS_KEYS].sort(), Object.keys(dark()).sort());
});
(0, node_test_1.test)('known studios include the default studio', () => {
    assert.ok(settings_logic_1.KNOWN_STUDIO_IDS.includes(dark().studioId));
});
(0, node_test_1.test)('non-object patches are rejected', () => {
    for (const p of [null, undefined, 3, 'x', [], true])
        rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), p));
});
(0, node_test_1.test)('unknown keys are rejected, naming them', () => {
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { theme: 'light', hacked: 1 }), /hacked/);
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { updatedAt: 1 }), /updatedAt/);
});
(0, node_test_1.test)('empty patch is a no-op', () => {
    const r = (0, settings_logic_1.applySettingsPatch)(dark(), {});
    assert.deepEqual(r.next, dark());
    assert.deepEqual(r.changed, []);
});
(0, node_test_1.test)('same value reports no change', () => {
    assert.deepEqual((0, settings_logic_1.applySettingsPatch)(dark(), { frameWidth: 4, showNames: true }).changed, []);
});
(0, node_test_1.test)('frameWidth is rounded and clamped to 0–12', () => {
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { frameWidth: 40 }).next.frameWidth, 12);
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { frameWidth: -3 }).next.frameWidth, 0);
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { frameWidth: 6.6 }).next.frameWidth, 7);
    assert.deepEqual((0, settings_logic_1.applySettingsPatch)(dark(), { frameWidth: 7 }).changed, ['frameWidth']);
    assert.equal((0, settings_logic_1.clampFrameWidth)(12.4), 12);
});
(0, node_test_1.test)('frameWidth rejects non-numbers', () => {
    for (const v of ['4', null, NaN, Infinity, true])
        rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { frameWidth: v }));
});
(0, node_test_1.test)('studioDim is clamped to 0–0.6 and snapped to 0.05', () => {
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { studioDim: 2 }).next.studioDim, 0.6);
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { studioDim: -1 }).next.studioDim, 0);
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { studioDim: 0.33 }).next.studioDim, 0.35);
    assert.equal((0, settings_logic_1.clampStudioDim)(0.1 + 0.05), 0.15);
    for (const v of ['0.2', null, NaN])
        rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { studioDim: v }));
});
(0, node_test_1.test)('studioId must be a known studio', () => {
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { studioId: 'not_a_studio' }), /studioId/);
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { studioId: 7 }));
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { studioId: settings_logic_1.KNOWN_STUDIO_IDS[0] }).next.studioId, settings_logic_1.KNOWN_STUDIO_IDS[0]);
});
(0, node_test_1.test)('theme must be dark or light', () => {
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { theme: 'sepia' }));
});
(0, node_test_1.test)('frameColor must be one of the theme options (case-insensitive, stored canonical)', () => {
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { frameColor: '#123456' }), /frameColor/);
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { frameColor: contracts_1.FRAME_COLOR_OPTIONS.light[0] }));
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { frameColor: 5 }));
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { frameColor: '#2f7bff' }).next.frameColor, '#2F7BFF');
});
(0, node_test_1.test)('switching theme maps frameColor by index', () => {
    for (let i = 0; i < 4; i++) {
        const cur = Object.assign(Object.assign({}, dark()), { frameColor: contracts_1.FRAME_COLOR_OPTIONS.dark[i] });
        const r = (0, settings_logic_1.applySettingsPatch)(cur, { theme: 'light' });
        assert.equal(r.next.frameColor, contracts_1.FRAME_COLOR_OPTIONS.light[i]);
        assert.deepEqual(r.changed.includes('theme'), true);
    }
    const back = (0, settings_logic_1.applySettingsPatch)(Object.assign(Object.assign({}, (0, contracts_1.defaultSettings)('light')), { frameColor: '#8C97AE' }), { theme: 'dark' });
    assert.equal(back.next.frameColor, '#2A3550');
});
(0, node_test_1.test)('theme switch with an explicit frameColor validates against the new theme', () => {
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { theme: 'light', frameColor: '#8C97AE' }).next.frameColor, '#8C97AE');
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { theme: 'light', frameColor: '#15151B' }));
});
(0, node_test_1.test)('mapFrameColor falls back to index 0 for an unknown color', () => {
    assert.equal((0, settings_logic_1.mapFrameColor)('#000000', 'dark', 'light'), contracts_1.FRAME_COLOR_OPTIONS.light[0]);
    assert.equal((0, settings_logic_1.frameColorOption)('light', '#ff2d75'), '#FF2D75');
    assert.equal((0, settings_logic_1.frameColorOption)('light', '#15151B'), null);
});
(0, node_test_1.test)('guestSize, showNames and speakerMode are validated', () => {
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { guestSize: 'l' }).next.guestSize, 'l');
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { guestSize: 'xl' }));
    assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { showNames: false }).next.showNames, false);
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { showNames: 'false' }));
    for (const m of ['hostPinned', 'autoActiveSpeaker', 'manual']) {
        assert.equal((0, settings_logic_1.applySettingsPatch)(dark(), { speakerMode: m }).next.speakerMode, m);
    }
    rejects(() => (0, settings_logic_1.applySettingsPatch)(dark(), { speakerMode: 'auto' }), /speakerMode/);
});
(0, node_test_1.test)('a multi-field patch reports every changed key', () => {
    const r = (0, settings_logic_1.applySettingsPatch)(dark(), { guestSize: 's', showNames: false, speakerMode: 'manual' });
    assert.deepEqual(r.changed, ['guestSize', 'showNames', 'speakerMode']);
});
(0, node_test_1.test)('applySettingsPatch does not mutate its input', () => {
    const cur = dark();
    (0, settings_logic_1.applySettingsPatch)(cur, { frameWidth: 9, theme: 'light' });
    assert.deepEqual(cur, dark());
});
(0, node_test_1.test)('normalizeSettings fills theme defaults and repairs bad stored values', () => {
    assert.deepEqual((0, settings_logic_1.normalizeSettings)(undefined), (0, contracts_1.defaultSettings)('dark'));
    assert.deepEqual((0, settings_logic_1.normalizeSettings)({ theme: 'light' }), (0, contracts_1.defaultSettings)('light'));
    const n = (0, settings_logic_1.normalizeSettings)({
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
    assert.deepEqual(n, Object.assign(Object.assign({}, (0, contracts_1.defaultSettings)('light')), { frameWidth: 12, studioDim: 0.6 }));
    assert.equal(n.updatedAt, undefined);
});
(0, node_test_1.test)('parseStreamId accepts null/absent and ids, rejects junk', () => {
    assert.equal((0, settings_logic_1.parseStreamId)(null), null);
    assert.equal((0, settings_logic_1.parseStreamId)(undefined), null);
    assert.equal((0, settings_logic_1.parseStreamId)('abc'), 'abc');
    for (const v of ['', '  ', 5, 'a/b', 'x'.repeat(129)])
        rejects(() => (0, settings_logic_1.parseStreamId)(v));
});
//# sourceMappingURL=settings.test.js.map