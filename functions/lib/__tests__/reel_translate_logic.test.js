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
const reelTranslateLogic_1 = require("../reelTranslateLogic");
(0, node_test_1.test)('language codes become stable cache keys', () => {
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('SW'), 'sw');
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('yo'), 'yo');
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('pt_br'), 'pt-BR');
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('zh-hant'), 'zh-Hant');
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('haw'), 'haw');
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('und'), null);
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('Swahili'), null);
    assert.equal((0, reelTranslateLogic_1.normalizeLang)('../x'), null);
    assert.equal((0, reelTranslateLogic_1.normalizeLang)(42), null);
});
(0, node_test_1.test)('regions of one language count as the same language', () => {
    assert.ok((0, reelTranslateLogic_1.sameLanguage)('pt', 'pt-BR'));
    assert.ok(!(0, reelTranslateLogic_1.sameLanguage)('sw', 'en'));
    assert.ok(!(0, reelTranslateLogic_1.sameLanguage)(null, 'en'));
});
(0, node_test_1.test)('hashtags are kept out of the text that gets translated', () => {
    assert.equal((0, reelTranslateLogic_1.captionBody)('Habari za asubuhi #nairobi #fyp'), 'Habari za asubuhi');
    assert.equal((0, reelTranslateLogic_1.captionBody)('#só #aqui'), '');
    assert.equal((0, reelTranslateLogic_1.captionBody)('Line one #a\n  line two'), 'Line one\nline two');
});
(0, node_test_1.test)('caption tracks are cleaned and capped', () => {
    const segs = (0, reelTranslateLogic_1.cleanSegments)([
        { startMs: 0, endMs: 900, text: ' Hello ' },
        { startMs: 900, endMs: 800, text: 'bad times' },
        { startMs: 1000, endMs: 2000, text: '' },
        { startMs: 'x', endMs: 3000, text: 'nan' },
        null,
    ]);
    assert.deepEqual(segs, [{ startMs: 0, endMs: 900, text: 'Hello' }]);
    const many = Array.from({ length: reelTranslateLogic_1.MAX_SEGMENTS + 20 }, (_, i) => ({ startMs: i * 10, endMs: i * 10 + 5, text: `l${i}` }));
    assert.equal((0, reelTranslateLogic_1.cleanSegments)(many).length, reelTranslateLogic_1.MAX_SEGMENTS);
    assert.deepEqual((0, reelTranslateLogic_1.cleanSegments)('nope'), []);
});
(0, node_test_1.test)('translations map back onto the caption and the timed lines', () => {
    var _a;
    const segs = [
        { startMs: 0, endMs: 1000, text: 'Karibu' },
        { startMs: 1000, endMs: 2000, text: 'Asante' },
    ];
    const items = (0, reelTranslateLogic_1.buildItems)('Habari', segs);
    assert.deepEqual(items, ['Habari', 'Karibu', 'Asante']);
    const out = (0, reelTranslateLogic_1.applyTranslations)('Habari', segs, ['Hello', 'Welcome', '']);
    assert.deepEqual(out, {
        caption: 'Hello',
        segments: [
            { startMs: 0, endMs: 1000, text: 'Welcome' },
            { startMs: 1000, endMs: 2000, text: 'Asante' },
        ],
    });
    assert.equal((0, reelTranslateLogic_1.applyTranslations)('Habari', segs, ['only one']), null);
    assert.deepEqual((_a = (0, reelTranslateLogic_1.applyTranslations)('', segs, ['A', 'B'])) === null || _a === void 0 ? void 0 : _a.caption, '');
});
(0, node_test_1.test)('the fingerprint changes when the caption or track changes', () => {
    const segs = [{ startMs: 0, endMs: 1000, text: 'a' }];
    const h = (0, reelTranslateLogic_1.sourceHash)('cap', segs);
    assert.equal(h, (0, reelTranslateLogic_1.sourceHash)('cap', [{ startMs: 0, endMs: 1000, text: 'a' }]));
    assert.notEqual(h, (0, reelTranslateLogic_1.sourceHash)('cap!', segs));
    assert.notEqual(h, (0, reelTranslateLogic_1.sourceHash)('cap', [{ startMs: 0, endMs: 1001, text: 'a' }]));
});
(0, node_test_1.test)('support and post ids are validated', () => {
    assert.equal((0, reelTranslateLogic_1.cleanSupport)('good'), 'good');
    assert.equal((0, reelTranslateLogic_1.cleanSupport)('great'), 'limited');
    assert.ok((0, reelTranslateLogic_1.validPostId)('abcDEF123_-'));
    assert.ok(!(0, reelTranslateLogic_1.validPostId)('a/b/c'));
    assert.ok(!(0, reelTranslateLogic_1.validPostId)(''));
});
//# sourceMappingURL=reel_translate_logic.test.js.map