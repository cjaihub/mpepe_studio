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
const media_logic_1 = require("../media_logic");
const profile = { displayName: 'A', avatarUrl: '' };
(0, node_test_1.test)('kind defaults to studio and ignores gameTitle', () => {
    assert.deepEqual((0, media_logic_1.parseStartKind)(undefined), { kind: 'studio', gameTitle: null });
    assert.deepEqual((0, media_logic_1.parseStartKind)({ title: 'x' }), { kind: 'studio', gameTitle: null });
    assert.deepEqual((0, media_logic_1.parseStartKind)({ kind: 'studio', gameTitle: 'Ludo' }), { kind: 'studio', gameTitle: null });
});
(0, node_test_1.test)('gaming kind trims the game title', () => {
    assert.deepEqual((0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: '  Free Fire  ' }), {
        kind: 'gaming',
        gameTitle: 'Free Fire',
    });
    assert.deepEqual((0, media_logic_1.parseStartKind)({ kind: 'gaming' }), { kind: 'gaming', gameTitle: null });
    assert.deepEqual((0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: '   ' }), { kind: 'gaming', gameTitle: null });
    const max = 'x'.repeat(contracts_1.GAME_TITLE_MAX_LENGTH);
    assert.equal((0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: max }).gameTitle, max);
});
(0, node_test_1.test)('bad kind / gameTitle are rejected', () => {
    assert.throws(() => (0, media_logic_1.parseStartKind)({ kind: 'karaoke' }), media_logic_1.StartValidationError);
    assert.throws(() => (0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: 'x'.repeat(61) }), media_logic_1.StartValidationError);
    assert.throws(() => (0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: 'Ludo\nKing' }), media_logic_1.StartValidationError);
    assert.throws(() => (0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: 'Ludo\u0000' }), media_logic_1.StartValidationError);
    assert.throws(() => (0, media_logic_1.parseStartKind)({ kind: 'gaming', gameTitle: 42 }), media_logic_1.StartValidationError);
});
(0, node_test_1.test)('layout preset follows the kind, not saved settings', () => {
    const savedGaming = (0, settings_logic_1.normalizeSettings)({ layoutPreset: 'gaming' });
    assert.equal(savedGaming.layoutPreset, 'gaming');
    assert.equal((0, media_logic_1.applyStartKind)(savedGaming, 'studio').layoutPreset, 'studio');
    assert.equal((0, media_logic_1.applyStartKind)((0, contracts_1.defaultSettings)(), 'gaming').layoutPreset, 'gaming');
    assert.equal((0, settings_logic_1.normalizeSettings)({ layoutPreset: '??' }).layoutPreset, 'studio');
});
(0, node_test_1.test)('settings patch accepts layoutPreset', () => {
    const r = (0, settings_logic_1.applySettingsPatch)((0, contracts_1.defaultSettings)(), { layoutPreset: 'gaming' });
    assert.equal(r.next.layoutPreset, 'gaming');
    assert.deepEqual(r.changed, ['layoutPreset']);
    assert.throws(() => (0, settings_logic_1.applySettingsPatch)((0, contracts_1.defaultSettings)(), { layoutPreset: 'arena' }));
});
(0, node_test_1.test)('gaming state and stream doc', () => {
    const settings = (0, media_logic_1.applyStartKind)((0, contracts_1.defaultSettings)(), 'gaming');
    const s = (0, media_logic_1.buildInitialState)({ streamId: 's', hostId: 'h', title: 'T', settings, nowMs: 0, gameTitle: 'Ludo' });
    assert.equal(s.settings.layoutPreset, 'gaming');
    assert.equal(s.gameTitle, 'Ludo');
    const d = (0, media_logic_1.buildStreamDoc)({ streamId: 's', hostId: 'h', title: 'T', profile, kind: 'gaming', gameTitle: 'Ludo' });
    assert.equal(d.liveKind, 'gaming');
    assert.equal(d.category, 'Gaming');
    assert.equal(d.gameTitle, 'Ludo');
    assert.equal(d.studioVersion, 2);
});
(0, node_test_1.test)('studio state and stream doc carry no gaming fields', () => {
    const s = (0, media_logic_1.buildInitialState)({ streamId: 's', hostId: 'h', title: 'T', settings: (0, contracts_1.defaultSettings)(), nowMs: 0 });
    assert.equal('gameTitle' in s, false);
    const d = (0, media_logic_1.buildStreamDoc)({ streamId: 's', hostId: 'h', title: 'T', profile });
    assert.equal('liveKind' in d, false);
    assert.equal('category' in d, false);
    const g = (0, media_logic_1.buildStreamDoc)({ streamId: 's', hostId: 'h', title: 'T', profile, kind: 'gaming' });
    assert.equal(g.liveKind, 'gaming');
    assert.equal('gameTitle' in g, false);
});
//# sourceMappingURL=media_gaming_logic.test.js.map