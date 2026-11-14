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
const engineLogic_1 = require("../models3d/engineLogic");
const PREFIX = 'users/u1/models3d/m123456/source/engine';
const PHOTOS = ['users/u1/models3d/m123456/photos/0.jpg', 'users/u1/models3d/m123456/photos/1.jpg'];
(0, node_test_1.test)('validEngineUrl accepts only https Cloud Run URLs', () => {
    assert.equal((0, engineLogic_1.validEngineUrl)('https://ova3d-model-trellis-abc-uc.a.run.app/'), 'https://ova3d-model-trellis-abc-uc.a.run.app');
    assert.equal((0, engineLogic_1.validEngineUrl)('http://ova3d.a.run.app'), null);
    assert.equal((0, engineLogic_1.validEngineUrl)('https://api.meshy.ai'), null);
    assert.equal((0, engineLogic_1.validEngineUrl)('https://user:pw@x.a.run.app'), null);
    assert.equal((0, engineLogic_1.validEngineUrl)('https://x.a.run.app?redirect=evil'), null);
    assert.equal((0, engineLogic_1.validEngineUrl)(''), null);
    assert.equal((0, engineLogic_1.validEngineUrl)(null), null);
    assert.equal((0, engineLogic_1.validEngineUrl)('not a url'), null);
});
(0, node_test_1.test)('buildEngineRequest sends gs:// inputs from the model folder only', () => {
    const r = (0, engineLogic_1.buildEngineRequest)('mpepe-2b4bd.firebasestorage.app', PHOTOS, PREFIX + '/');
    assert.equal(r.task, 'image_to_3d');
    assert.deepEqual(r.inputs, PHOTOS.map((p) => `gs://mpepe-2b4bd.firebasestorage.app/${p}`));
    assert.equal(r.output_uri, `gs://mpepe-2b4bd.firebasestorage.app/${PREFIX}`);
    assert.throws(() => (0, engineLogic_1.buildEngineRequest)('b-1', [], PREFIX));
    assert.throws(() => (0, engineLogic_1.buildEngineRequest)('b-1', ['a', 'b', 'c', 'd', 'e'], PREFIX));
    assert.throws(() => (0, engineLogic_1.buildEngineRequest)('b-1', ['shops/u2/products/p/1.jpg'], PREFIX));
    assert.throws(() => (0, engineLogic_1.buildEngineRequest)('b-1', ['users/u1/models3d/m123456/../../u2/x.jpg'], PREFIX));
    assert.throws(() => (0, engineLogic_1.buildEngineRequest)('Bad Bucket', PHOTOS, PREFIX));
});
(0, node_test_1.test)('readEngineResult returns the GLB path inside the output folder', () => {
    assert.equal((0, engineLogic_1.readEngineResult)({ outputs: { glb: 'model.glb' } }, PREFIX), `${PREFIX}/model.glb`);
    assert.throws(() => (0, engineLogic_1.readEngineResult)({ outputs: { glb: '../../other/model.glb' } }, PREFIX), /without a model/);
    assert.throws(() => (0, engineLogic_1.readEngineResult)({ outputs: {} }, PREFIX), /without a model/);
    assert.throws(() => (0, engineLogic_1.readEngineResult)(null, PREFIX), /without a model/);
});
(0, node_test_1.test)('engine errors read as plain next steps', () => {
    assert.match((0, engineLogic_1.engineErrorMessage)(422), /clearer photos/);
    assert.match((0, engineLogic_1.engineErrorMessage)(429), /busy/);
    assert.match((0, engineLogic_1.engineErrorMessage)(undefined), /too long/);
    assert.match((0, engineLogic_1.engineErrorMessage)(500), /Try again/);
});
(0, node_test_1.test)('estimated progress rises steadily and stays below the optimizer hand-off', () => {
    const a = (0, engineLogic_1.estimatedProgress)(0), b = (0, engineLogic_1.estimatedProgress)(60000), c = (0, engineLogic_1.estimatedProgress)(600000);
    assert.ok(a.progress >= 0.1 && a.progress < b.progress && b.progress < c.progress);
    assert.ok(c.progress < 0.72);
    assert.equal(a.stage, 'Building the shape from your photos');
    assert.equal(c.stage, 'Finishing the model');
});
//# sourceMappingURL=models3d_engine.test.js.map