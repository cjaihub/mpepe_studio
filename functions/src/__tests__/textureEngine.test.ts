import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { BUILT_IN, renderTexture, TEXTURE_KINDS, hexToRgb } from '../commerce/textureEngine';

test('every kind renders an opaque image of the asked size', () => {
  for (const kind of TEXTURE_KINDS) {
    const px = renderTexture({ kind, colors: ['#112233', '#ddeeff', '#884422'], size: 64 });
    assert.equal(px.length, 64 * 64 * 4);
    for (let i = 3; i < px.length; i += 4) assert.equal(px[i], 255);
  }
});

test('same spec and seed give the same pixels', () => {
  const a = renderTexture({ kind: 'marble', colors: ['#ffffff', '#000000'], size: 64, seed: 3 });
  const b = renderTexture({ kind: 'marble', colors: ['#ffffff', '#000000'], size: 64, seed: 3 });
  assert.deepEqual(a, b);
});

test('textures tile: left and right edges match closely', () => {
  const s = 128;
  const px = renderTexture({ kind: 'concrete', colors: ['#808080', '#c0c0c0'], size: s });
  let diff = 0;
  for (let y = 0; y < s; y++) {
    const l = (y * s) * 4, r = (y * s + s - 1) * 4;
    diff += Math.abs(px[l] - px[r]);
  }
  assert.ok(diff / s < 20, `edge difference ${diff / s}`);
});

test('built-in ids are unique and colors parse', () => {
  assert.equal(new Set(BUILT_IN.map((t) => t.id)).size, BUILT_IN.length);
  assert.deepEqual(hexToRgb('#0C4FA8'), [12, 79, 168]);
  assert.deepEqual(hexToRgb('nope'), [128, 128, 128]);
});
