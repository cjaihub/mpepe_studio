import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { buildEngineRequest, engineErrorMessage, estimatedProgress, readEngineResult, validEngineUrl } from '../models3d/engineLogic';

const PREFIX = 'users/u1/models3d/m123456/source/engine';
const PHOTOS = ['users/u1/models3d/m123456/photos/0.jpg', 'users/u1/models3d/m123456/photos/1.jpg'];

test('validEngineUrl accepts only https Cloud Run URLs', () => {
  assert.equal(validEngineUrl('https://ova3d-model-trellis-abc-uc.a.run.app/'), 'https://ova3d-model-trellis-abc-uc.a.run.app');
  assert.equal(validEngineUrl('http://ova3d.a.run.app'), null);
  assert.equal(validEngineUrl('https://api.meshy.ai'), null);
  assert.equal(validEngineUrl('https://user:pw@x.a.run.app'), null);
  assert.equal(validEngineUrl('https://x.a.run.app?redirect=evil'), null);
  assert.equal(validEngineUrl(''), null);
  assert.equal(validEngineUrl(null), null);
  assert.equal(validEngineUrl('not a url'), null);
});

test('buildEngineRequest sends gs:// inputs from the model folder only', () => {
  const r = buildEngineRequest('mpepe-2b4bd.firebasestorage.app', PHOTOS, PREFIX + '/');
  assert.equal(r.task, 'image_to_3d');
  assert.deepEqual(r.inputs, PHOTOS.map((p) => `gs://mpepe-2b4bd.firebasestorage.app/${p}`));
  assert.equal(r.output_uri, `gs://mpepe-2b4bd.firebasestorage.app/${PREFIX}`);
  assert.throws(() => buildEngineRequest('b-1', [], PREFIX));
  assert.throws(() => buildEngineRequest('b-1', ['a', 'b', 'c', 'd', 'e'], PREFIX));
  assert.throws(() => buildEngineRequest('b-1', ['shops/u2/products/p/1.jpg'], PREFIX));
  assert.throws(() => buildEngineRequest('b-1', ['users/u1/models3d/m123456/../../u2/x.jpg'], PREFIX));
  assert.throws(() => buildEngineRequest('Bad Bucket', PHOTOS, PREFIX));
});

test('readEngineResult returns the GLB path inside the output folder', () => {
  assert.equal(readEngineResult({ outputs: { glb: 'model.glb' } }, PREFIX), `${PREFIX}/model.glb`);
  assert.throws(() => readEngineResult({ outputs: { glb: '../../other/model.glb' } }, PREFIX), /without a model/);
  assert.throws(() => readEngineResult({ outputs: {} }, PREFIX), /without a model/);
  assert.throws(() => readEngineResult(null, PREFIX), /without a model/);
});

test('engine errors read as plain next steps', () => {
  assert.match(engineErrorMessage(422), /clearer photos/);
  assert.match(engineErrorMessage(429), /busy/);
  assert.match(engineErrorMessage(undefined), /too long/);
  assert.match(engineErrorMessage(500), /Try again/);
});

test('estimated progress rises steadily and stays below the optimizer hand-off', () => {
  const a = estimatedProgress(0), b = estimatedProgress(60_000), c = estimatedProgress(600_000);
  assert.ok(a.progress >= 0.1 && a.progress < b.progress && b.progress < c.progress);
  assert.ok(c.progress < 0.72);
  assert.equal(a.stage, 'Building the shape from your photos');
  assert.equal(c.stage, 'Finishing the model');
});
