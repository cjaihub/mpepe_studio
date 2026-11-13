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
const textureEngine_1 = require("../commerce/textureEngine");
(0, node_test_1.test)('every kind renders an opaque image of the asked size', () => {
    for (const kind of textureEngine_1.TEXTURE_KINDS) {
        const px = (0, textureEngine_1.renderTexture)({ kind, colors: ['#112233', '#ddeeff', '#884422'], size: 64 });
        assert.equal(px.length, 64 * 64 * 4);
        for (let i = 3; i < px.length; i += 4)
            assert.equal(px[i], 255);
    }
});
(0, node_test_1.test)('same spec and seed give the same pixels', () => {
    const a = (0, textureEngine_1.renderTexture)({ kind: 'marble', colors: ['#ffffff', '#000000'], size: 64, seed: 3 });
    const b = (0, textureEngine_1.renderTexture)({ kind: 'marble', colors: ['#ffffff', '#000000'], size: 64, seed: 3 });
    assert.deepEqual(a, b);
});
(0, node_test_1.test)('textures tile: left and right edges match closely', () => {
    const s = 128;
    const px = (0, textureEngine_1.renderTexture)({ kind: 'concrete', colors: ['#808080', '#c0c0c0'], size: s });
    let diff = 0;
    for (let y = 0; y < s; y++) {
        const l = (y * s) * 4, r = (y * s + s - 1) * 4;
        diff += Math.abs(px[l] - px[r]);
    }
    assert.ok(diff / s < 20, `edge difference ${diff / s}`);
});
(0, node_test_1.test)('built-in ids are unique and colors parse', () => {
    assert.equal(new Set(textureEngine_1.BUILT_IN.map((t) => t.id)).size, textureEngine_1.BUILT_IN.length);
    assert.deepEqual((0, textureEngine_1.hexToRgb)('#0C4FA8'), [12, 79, 168]);
    assert.deepEqual((0, textureEngine_1.hexToRgb)('nope'), [128, 128, 128]);
});
//# sourceMappingURL=textureEngine.test.js.map