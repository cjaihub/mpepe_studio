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
(0, node_test_1.test)('defaults mirror the Dart contracts', () => {
    assert.equal((0, contracts_1.defaultSettings)('light').frameColor, '#3B4763');
    assert.equal((0, contracts_1.defaultSettings)('light').studioDim, 0);
    assert.equal((0, contracts_1.defaultSettings)().guestSize, 'm');
    assert.equal((0, contracts_1.emptyStage)('h').wall.length, contracts_1.Limits.wallSlots);
});
(0, node_test_1.test)('layout preset defaults to studio; gameTitle is optional', () => {
    assert.equal((0, contracts_1.defaultSettings)().layoutPreset, 'studio');
    assert.equal((0, contracts_1.defaultSettings)('light').layoutPreset, 'studio');
    const s = {
        schemaVersion: 1,
        streamId: 's',
        hostId: 'h',
        title: 'T',
        status: 'live',
        seq: 0,
        settings: Object.assign(Object.assign({}, (0, contracts_1.defaultSettings)()), { layoutPreset: 'gaming' }),
        stage: (0, contracts_1.emptyStage)('h'),
        table: { mode: 'goods', goods: null, screen: null, watch: null },
        counts: { viewers: 0, participants: 1, loves: 0, sparkles: 0, shares: 0 },
        gameTitle: 'Ludo',
    };
    const back = JSON.parse(JSON.stringify(s));
    assert.deepEqual(back, s);
    assert.ok(contracts_1.GAME_TITLE_MAX_LENGTH === 60);
    assert.deepEqual([...contracts_1.LAYOUT_PRESETS], ['studio', 'gaming']);
});
//# sourceMappingURL=contracts.test.js.map