import { test, describe } from 'node:test';
import * as assert from 'node:assert';
import {
  generateAiResultCacheKey,
  normalizePrompt,
  computeImageStatsBucketHash,
  selectAiModel,
} from '../aiCostOptimizer';
import { evaluateSpendLevel, CloudSpendLevel } from '../budgetGuard';

describe('AI Cost Layer & Result Caching', () => {
  test('normalizePrompt trims, lowercases, and strips non-semantic punctuation', () => {
    const raw1 = '  Make it Warmer, and more contrast!!  ';
    const raw2 = 'make it warmer and more contrast';
    assert.strictEqual(normalizePrompt(raw1), normalizePrompt(raw2));
    assert.strictEqual(normalizePrompt(raw1), 'make it warmer and more contrast');
  });

  test('computeImageStatsBucketHash buckets similar lighting and color temperature', () => {
    const hash1 = computeImageStatsBucketHash({
      meanLuminanceBin: 4,
      cctKelvinBin: 3200,
      tintBin: 1,
      saturationBin: 2,
      dynamicRangeBin: 3,
    });
    const hash2 = computeImageStatsBucketHash({
      meanLuminanceBin: 4,
      cctKelvinBin: 3200,
      tintBin: 1,
      saturationBin: 2,
      dynamicRangeBin: 3,
    });
    const hashDifferent = computeImageStatsBucketHash({
      meanLuminanceBin: 8,
      cctKelvinBin: 6500,
      tintBin: 0,
      saturationBin: 3,
      dynamicRangeBin: 4,
    });

    assert.strictEqual(hash1, hash2);
    assert.notStrictEqual(hash1, hashDifferent);
  });

  test('generateAiResultCacheKey produces identical deterministic hash for semantically identical requests', () => {
    const key1 = generateAiResultCacheKey(
      'cinematic_grade',
      '1.2.0',
      'Make shadows teal, highlights warm!',
      { meanLuminanceBin: 3, cctKelvinBin: 4500 },
    );
    const key2 = generateAiResultCacheKey(
      'cinematic_grade',
      '1.2.0',
      'make shadows teal highlights warm',
      { meanLuminanceBin: 3, cctKelvinBin: 4500 },
    );
    const keyDifferentSkill = generateAiResultCacheKey(
      'vintage_film',
      '1.2.0',
      'make shadows teal highlights warm',
      { meanLuminanceBin: 3, cctKelvinBin: 4500 },
    );

    assert.strictEqual(key1, key2);
    assert.notStrictEqual(key1, keyDifferentSkill);
    assert.strictEqual(key1.length, 64); // SHA-256 hex string length
  });

  test('selectAiModel routes to Flash-Lite for Free tier and cost conservation', () => {
    // Free user gets Flash-Lite
    assert.strictEqual(selectAiModel('free', 'standard'), 'gemini-2.5-flash-lite');

    // Creative task on Pro gets Flash
    assert.strictEqual(selectAiModel('pro', 'creative'), 'gemini-2.5-flash');

    // Amber spend forces even Pro creative task to Flash-Lite
    assert.strictEqual(selectAiModel('pro', 'creative', undefined, 'amber'), 'gemini-2.5-flash-lite');

    // Red spend forces to Flash-Lite
    assert.strictEqual(selectAiModel('biz', 'creative', undefined, 'red'), 'gemini-2.5-flash-lite');

    // Remote config override
    assert.strictEqual(selectAiModel('biz', 'creative', 'flash_lite', 'green'), 'gemini-2.5-flash-lite');
  });
});

describe('Budget Guard Spend Level Evaluator', () => {
  test('evaluates normal spend as GREEN (<80%)', () => {
    const res = evaluateSpendLevel(500, 1000);
    assert.strictEqual(res.level, 'green' as CloudSpendLevel);
    assert.strictEqual(res.ratio, 0.5);
    assert.match(res.reason, /normal/);
  });

  test('evaluates spend at >=80% as AMBER', () => {
    const res = evaluateSpendLevel(820, 1000);
    assert.strictEqual(res.level, 'amber' as CloudSpendLevel);
    assert.strictEqual(res.ratio, 0.82);
    assert.match(res.reason, /Free-tier cloud jobs routed/);
  });

  test('evaluates spend at >=100% as RED kill-switch', () => {
    const res = evaluateSpendLevel(1050, 1000);
    assert.strictEqual(res.level, 'red' as CloudSpendLevel);
    assert.strictEqual(res.ratio, 1.05);
    assert.match(res.reason, /restricted to paid\/critical only/);
  });

  test('handles zero budget safely as green', () => {
    const res = evaluateSpendLevel(0, 0);
    assert.strictEqual(res.level, 'green' as CloudSpendLevel);
  });
});
