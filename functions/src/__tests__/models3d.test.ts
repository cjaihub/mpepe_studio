import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { Document } from '@gltf-transform/core';
import { detectFormat, flatNormals, ModelError, parseObj, parseStl } from '../models3d/convert';
import { BUDGET, countTriangles, modelIO, optimizeModel, statsOf } from '../models3d/optimize';
import { cleanListing, median, priceBand } from '../models3d/listingLogic';
import { newShareCode, sharePlatform, validShareTarget } from '../commerce/shareLogic';

const CUBE_OBJ = `
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
v 0 0 1
v 1 0 1
v 1 1 1
v 0 1 1
usemtl body
f 1 2 3 4
f 5 6 7 8
usemtl sole
f 1 2 6 5
f -1 -2 -6 -5
`;

function binaryStl(triangles: number[][]): Uint8Array {
  const buf = Buffer.alloc(84 + triangles.length * 50);
  buf.writeUInt32LE(triangles.length, 80);
  triangles.forEach((t, i) => t.forEach((n, k) => buf.writeFloatLE(n, 84 + i * 50 + 12 + k * 4)));
  return buf;
}

/** A dense wavy grid: enough triangles to force simplification. */
async function gridGlb(n: number): Promise<Uint8Array> {
  const doc = new Document();
  const buffer = doc.createBuffer();
  const pos = new Float32Array((n + 1) * (n + 1) * 3);
  for (let y = 0; y <= n; y++) {
    for (let x = 0; x <= n; x++) {
      const i = (y * (n + 1) + x) * 3;
      pos[i] = x / n; pos[i + 1] = y / n; pos[i + 2] = Math.sin(x / 9) * 0.02;
    }
  }
  const idx = new Uint32Array(n * n * 6);
  let k = 0;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const a = y * (n + 1) + x, b = a + 1, c = a + n + 1, d = c + 1;
      idx.set([a, b, c, b, d, c], k);
      k += 6;
    }
  }
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(pos).setBuffer(buffer))
    .setIndices(doc.createAccessor().setType('SCALAR').setArray(idx).setBuffer(buffer))
    .setMaterial(doc.createMaterial('Leather'));
  doc.createScene().addChild(doc.createNode('grid').setMesh(doc.createMesh('grid').addPrimitive(prim)));
  return (await modelIO()).writeBinary(doc);
}

test('detectFormat trusts the glTF signature over the file name', () => {
  assert.equal(detectFormat('shoe.bin', Buffer.from('glTF....')), 'glb');
  assert.equal(detectFormat('shoe.glb', Buffer.from('nope')), null);
  assert.equal(detectFormat('Shoe.OBJ', Buffer.from('v 0 0')), 'obj');
  assert.equal(detectFormat('shoe.fbx', Buffer.from('Kayd')), null);
});

test('parseObj triangulates polygons, splits by material and reads relative indices', () => {
  const groups = parseObj(CUBE_OBJ);
  assert.deepEqual(groups.map((g) => g.material), ['body', 'sole']);
  assert.equal(groups[0].positions.length, 4 * 9); // two quads → four triangles
  assert.equal(groups[1].positions.length, 4 * 9);
  assert.throws(() => parseObj('v 0 0 0\nf 1 2 3'), ModelError);
});

test('parseStl reads binary and ASCII files', () => {
  const tri = [0, 0, 0, 1, 0, 0, 0, 1, 0];
  assert.deepEqual(Array.from(parseStl(binaryStl([tri, tri]))).slice(0, 9), tri);
  const ascii = 'solid a\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid a';
  assert.deepEqual(Array.from(parseStl(Buffer.from(ascii))), tri);
  assert.deepEqual(Array.from(flatNormals(tri)).slice(0, 3), [0, 0, 1]);
});

test('optimizeModel keeps small models whole and returns three readable files', async () => {
  const out = await optimizeModel(Buffer.from(CUBE_OBJ), 'obj');
  assert.equal(out.source.triangles, 8);
  assert.deepEqual(out.source.materials.sort(), ['body', 'sole']);
  assert.deepEqual(out.source.size, [1, 1, 1]);
  const io = await modelIO();
  for (const file of [out.mobile, out.hd, out.ar]) {
    const doc = await io.readBinary(file);
    assert.equal(countTriangles(doc), 8);
    assert.equal(statsOf(doc).materials.length, 2);
  }
});

test('optimizeModel simplifies heavy models down to the phone budget', async () => {
  const src = await gridGlb(400); // 320,000 triangles
  const out = await optimizeModel(src, 'glb');
  assert.equal(out.source.triangles, 320_000);
  assert.ok(out.mobileTriangles <= BUDGET.mobile.triangles * 1.05, `phone file has ${out.mobileTriangles} triangles`);
  assert.ok(out.mobile.byteLength < src.byteLength / 3, 'phone file should be much smaller than the source');
  assert.ok(countTriangles(await (await modelIO()).readBinary(out.hd)) === 320_000, 'tablet file keeps full detail under its budget');
});

test('optimizeModel refuses files it cannot show', async () => {
  await assert.rejects(optimizeModel(Buffer.from('not a model'), 'glb'), ModelError);
  await assert.rejects(optimizeModel(Buffer.from('{"asset":{"version":"2.0"},"buffers":[{"uri":"a.bin","byteLength":4}]}'), 'gltf'), /single \.glb/);
});

test('cleanListing bounds what the model returns', () => {
  const l = cleanListing({
    name: '  Retro Runner  '.padEnd(200, 'x'), description: 'd', category: 'Sneakers', condition: 'weird',
    colors: [{ name: 'Black', hex: '111111' }, { name: 'Bad', hex: 'zzz' }, 'nope'],
    tags: ['a', 'a', 'B', 4], price: { low: 50, typical: 20, high: 90 }, confidence: 7,
  });
  assert.equal(l.name.length, 120);
  assert.equal(l.condition, 'new');
  assert.deepEqual(l.colors, [{ name: 'Black', hex: '#111111' }]);
  assert.deepEqual(l.tags, ['a', 'b']);
  assert.deepEqual(l.price, { low: 20, typical: 50, high: 90 });
  assert.equal(l.confidence, 1);
  assert.equal(cleanListing(null).name, '');
});

test('priceBand blends shop prices with the estimate', () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([]), null);
  assert.deepEqual(priceBand(null, [], 'USD'), null);
  assert.deepEqual(priceBand({ low: 40, typical: 50, high: 60 }, [], 'USD'), { low: 40, typical: 50, high: 60, basis: 'estimate', samples: 0 });
  const b = priceBand({ low: 40, typical: 50, high: 60 }, [70, 80, 90, 100, 110], 'TZS')!;
  assert.equal(b.basis, 'oneova');
  assert.equal(b.samples, 5);
  assert.equal(b.typical, 90);
  assert.equal(b.typical % 1, 0);
});

test('share links: codes, targets and platforms', () => {
  const code = newShareCode();
  assert.match(code, /^[a-z0-9]{10}$/);
  assert.notEqual(code, newShareCode());
  assert.equal(validShareTarget('product', 'abc123'), true);
  assert.equal(validShareTarget('shop', 'a/b'), false);
  assert.equal(validShareTarget('order', 'abc'), false);
  assert.equal(sharePlatform('Mozilla/5.0 (Linux; Android 14; Pixel)'), 'android');
  assert.equal(sharePlatform('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)'), 'ios');
  assert.equal(sharePlatform('Mozilla/5.0 (Macintosh)'), 'desktop');
  assert.equal(sharePlatform('facebookexternalhit/1.1'), 'bot');
});
