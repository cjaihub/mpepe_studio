import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  normalizeLang,
  sameLanguage,
  captionBody,
  cleanSegments,
  buildItems,
  applyTranslations,
  sourceHash,
  cleanSupport,
  validPostId,
  MAX_SEGMENTS,
} from '../reelTranslateLogic';

test('language codes become stable cache keys', () => {
  assert.equal(normalizeLang('SW'), 'sw');
  assert.equal(normalizeLang('yo'), 'yo');
  assert.equal(normalizeLang('pt_br'), 'pt-BR');
  assert.equal(normalizeLang('zh-hant'), 'zh-Hant');
  assert.equal(normalizeLang('haw'), 'haw');
  assert.equal(normalizeLang('und'), null);
  assert.equal(normalizeLang('Swahili'), null);
  assert.equal(normalizeLang('../x'), null);
  assert.equal(normalizeLang(42), null);
});

test('regions of one language count as the same language', () => {
  assert.ok(sameLanguage('pt', 'pt-BR'));
  assert.ok(!sameLanguage('sw', 'en'));
  assert.ok(!sameLanguage(null, 'en'));
});

test('hashtags are kept out of the text that gets translated', () => {
  assert.equal(captionBody('Habari za asubuhi #nairobi #fyp'), 'Habari za asubuhi');
  assert.equal(captionBody('#só #aqui'), '');
  assert.equal(captionBody('Line one #a\n  line two'), 'Line one\nline two');
});

test('caption tracks are cleaned and capped', () => {
  const segs = cleanSegments([
    { startMs: 0, endMs: 900, text: ' Hello ' },
    { startMs: 900, endMs: 800, text: 'bad times' },
    { startMs: 1000, endMs: 2000, text: '' },
    { startMs: 'x', endMs: 3000, text: 'nan' },
    null,
  ]);
  assert.deepEqual(segs, [{ startMs: 0, endMs: 900, text: 'Hello' }]);
  const many = Array.from({ length: MAX_SEGMENTS + 20 }, (_, i) => ({ startMs: i * 10, endMs: i * 10 + 5, text: `l${i}` }));
  assert.equal(cleanSegments(many).length, MAX_SEGMENTS);
  assert.deepEqual(cleanSegments('nope'), []);
});

test('translations map back onto the caption and the timed lines', () => {
  const segs = [
    { startMs: 0, endMs: 1000, text: 'Karibu' },
    { startMs: 1000, endMs: 2000, text: 'Asante' },
  ];
  const items = buildItems('Habari', segs);
  assert.deepEqual(items, ['Habari', 'Karibu', 'Asante']);
  const out = applyTranslations('Habari', segs, ['Hello', 'Welcome', '']);
  assert.deepEqual(out, {
    caption: 'Hello',
    segments: [
      { startMs: 0, endMs: 1000, text: 'Welcome' },
      { startMs: 1000, endMs: 2000, text: 'Asante' },
    ],
  });
  assert.equal(applyTranslations('Habari', segs, ['only one']), null);
  assert.deepEqual(applyTranslations('', segs, ['A', 'B'])?.caption, '');
});

test('the fingerprint changes when the caption or track changes', () => {
  const segs = [{ startMs: 0, endMs: 1000, text: 'a' }];
  const h = sourceHash('cap', segs);
  assert.equal(h, sourceHash('cap', [{ startMs: 0, endMs: 1000, text: 'a' }]));
  assert.notEqual(h, sourceHash('cap!', segs));
  assert.notEqual(h, sourceHash('cap', [{ startMs: 0, endMs: 1001, text: 'a' }]));
});

test('support and post ids are validated', () => {
  assert.equal(cleanSupport('good'), 'good');
  assert.equal(cleanSupport('great'), 'limited');
  assert.ok(validPostId('abcDEF123_-'));
  assert.ok(!validPostId('a/b/c'));
  assert.ok(!validPostId(''));
});
