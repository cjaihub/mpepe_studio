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
const assert = __importStar(require("node:assert"));
const aiCostOptimizer_1 = require("../aiCostOptimizer");
const budgetGuard_1 = require("../budgetGuard");
(0, node_test_1.describe)('AI Cost Layer & Result Caching', () => {
    (0, node_test_1.test)('normalizePrompt trims, lowercases, and strips non-semantic punctuation', () => {
        const raw1 = '  Make it Warmer, and more contrast!!  ';
        const raw2 = 'make it warmer and more contrast';
        assert.strictEqual((0, aiCostOptimizer_1.normalizePrompt)(raw1), (0, aiCostOptimizer_1.normalizePrompt)(raw2));
        assert.strictEqual((0, aiCostOptimizer_1.normalizePrompt)(raw1), 'make it warmer and more contrast');
    });
    (0, node_test_1.test)('computeImageStatsBucketHash buckets similar lighting and color temperature', () => {
        const hash1 = (0, aiCostOptimizer_1.computeImageStatsBucketHash)({
            meanLuminanceBin: 4,
            cctKelvinBin: 3200,
            tintBin: 1,
            saturationBin: 2,
            dynamicRangeBin: 3,
        });
        const hash2 = (0, aiCostOptimizer_1.computeImageStatsBucketHash)({
            meanLuminanceBin: 4,
            cctKelvinBin: 3200,
            tintBin: 1,
            saturationBin: 2,
            dynamicRangeBin: 3,
        });
        const hashDifferent = (0, aiCostOptimizer_1.computeImageStatsBucketHash)({
            meanLuminanceBin: 8,
            cctKelvinBin: 6500,
            tintBin: 0,
            saturationBin: 3,
            dynamicRangeBin: 4,
        });
        assert.strictEqual(hash1, hash2);
        assert.notStrictEqual(hash1, hashDifferent);
    });
    (0, node_test_1.test)('generateAiResultCacheKey produces identical deterministic hash for semantically identical requests', () => {
        const key1 = (0, aiCostOptimizer_1.generateAiResultCacheKey)('cinematic_grade', '1.2.0', 'Make shadows teal, highlights warm!', { meanLuminanceBin: 3, cctKelvinBin: 4500 });
        const key2 = (0, aiCostOptimizer_1.generateAiResultCacheKey)('cinematic_grade', '1.2.0', 'make shadows teal highlights warm', { meanLuminanceBin: 3, cctKelvinBin: 4500 });
        const keyDifferentSkill = (0, aiCostOptimizer_1.generateAiResultCacheKey)('vintage_film', '1.2.0', 'make shadows teal highlights warm', { meanLuminanceBin: 3, cctKelvinBin: 4500 });
        assert.strictEqual(key1, key2);
        assert.notStrictEqual(key1, keyDifferentSkill);
        assert.strictEqual(key1.length, 64); // SHA-256 hex string length
    });
    (0, node_test_1.test)('selectAiModel routes to Flash-Lite for Free tier and cost conservation', () => {
        // Free user gets Flash-Lite
        assert.strictEqual((0, aiCostOptimizer_1.selectAiModel)('free', 'standard'), 'gemini-2.5-flash-lite');
        // Creative task on Pro gets Flash
        assert.strictEqual((0, aiCostOptimizer_1.selectAiModel)('pro', 'creative'), 'gemini-2.5-flash');
        // Amber spend forces even Pro creative task to Flash-Lite
        assert.strictEqual((0, aiCostOptimizer_1.selectAiModel)('pro', 'creative', undefined, 'amber'), 'gemini-2.5-flash-lite');
        // Red spend forces to Flash-Lite
        assert.strictEqual((0, aiCostOptimizer_1.selectAiModel)('biz', 'creative', undefined, 'red'), 'gemini-2.5-flash-lite');
        // Remote config override
        assert.strictEqual((0, aiCostOptimizer_1.selectAiModel)('biz', 'creative', 'flash_lite', 'green'), 'gemini-2.5-flash-lite');
    });
});
(0, node_test_1.describe)('Budget Guard Spend Level Evaluator', () => {
    (0, node_test_1.test)('evaluates normal spend as GREEN (<80%)', () => {
        const res = (0, budgetGuard_1.evaluateSpendLevel)(500, 1000);
        assert.strictEqual(res.level, 'green');
        assert.strictEqual(res.ratio, 0.5);
        assert.match(res.reason, /normal/);
    });
    (0, node_test_1.test)('evaluates spend at >=80% as AMBER', () => {
        const res = (0, budgetGuard_1.evaluateSpendLevel)(820, 1000);
        assert.strictEqual(res.level, 'amber');
        assert.strictEqual(res.ratio, 0.82);
        assert.match(res.reason, /Free-tier cloud jobs routed/);
    });
    (0, node_test_1.test)('evaluates spend at >=100% as RED kill-switch', () => {
        const res = (0, budgetGuard_1.evaluateSpendLevel)(1050, 1000);
        assert.strictEqual(res.level, 'red');
        assert.strictEqual(res.ratio, 1.05);
        assert.match(res.reason, /restricted to paid\/critical only/);
    });
    (0, node_test_1.test)('handles zero budget safely as green', () => {
        const res = (0, budgetGuard_1.evaluateSpendLevel)(0, 0);
        assert.strictEqual(res.level, 'green');
    });
});
//# sourceMappingURL=scale_cost.test.js.map