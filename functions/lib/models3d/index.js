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
exports.model3dSweep = exports.model3dWorker = exports.model3dEngineStatus = exports.model3dUnlinkProvider = exports.model3dLinkProvider = exports.model3dDelete = exports.model3dAttach = exports.model3dResume = exports.model3dGenerate = exports.model3dCreate = void 0;
/**
 * Oneova 3D model service: every seller's private model library.
 *
 *   users/{uid}/models3d/{id}          what the owner sees (server-written;
 *                                      rules: owner reads, nobody writes)
 *   model3d_jobs/{id}                  the work queue (server only)
 *   Storage users/{uid}/models3d/{id}/ source/ + photos/ (owner uploads),
 *                                      out/ (optimized files, owner reads)
 *   Storage shops/{uid}/products/{productId}/model/  public copies, written
 *                                      only when the owner puts a model on a
 *                                      product
 *
 *   model3dCreate         an uploaded file (GLB, GLTF, OBJ, STL) → library
 *   model3dGenerate       1–4 product photos → 3D (linked or built-in engine)
 *   model3dWorker         converts, optimizes for phones / tablets / AR, hosts
 *   model3dSweep          follows running generations, fails stuck jobs
 *   model3dAttach         puts a ready model on one of the owner's products
 *   model3dDelete         removes a model and its files
 *   model3dLinkProvider / model3dUnlinkProvider   the owner's own engine key
 *
 * Work continues when the app is closed; the owner gets a notification when
 * the model is ready.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const convert_1 = require("./convert");
const optimize_1 = require("./optimize");
const providers_1 = require("./providers");
const db = () => (0, firestore_2.getFirestore)();
const bucket = () => (0, storage_1.getStorage)().bucket();
const MAX_MODELS = 200;
const MAX_RUNNING = 3;
const STUCK_MS = 40 * 60000;
function uidOf(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
const safeId = (v) => {
    const s = String(v !== null && v !== void 0 ? v : '');
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(s))
        throw new https_1.HttpsError('invalid-argument', 'Missing id.');
    return s;
};
const libRef = (uid, id) => db().doc(`users/${uid}/models3d/${id}`);
const jobRef = (id) => db().collection('model3d_jobs').doc(id);
const root = (uid, id) => `users/${uid}/models3d/${id}`;
/** Updates what the owner sees: the current step, progress and a short activity log. */
async function report(uid, id, status, stage, progress, extra = {}) {
    await libRef(uid, id).set(Object.assign({ status, stage, progress, steps: firestore_2.FieldValue.arrayUnion({ at: Date.now(), text: stage }), updatedAt: firestore_2.FieldValue.serverTimestamp() }, extra), { merge: true });
}
async function fail(uid, id, message) {
    await jobRef(id).set({ status: 'failed', active: false, error: message, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
    await report(uid, id, 'failed', message, 0, { error: message });
}
async function guardQuota(uid) {
    const col = db().collection(`users/${uid}/models3d`);
    if ((await col.count().get()).data().count >= MAX_MODELS) {
        throw new https_1.HttpsError('resource-exhausted', `Your library holds up to ${MAX_MODELS} models. Delete one to add more.`);
    }
    const running = await db().collection('model3d_jobs').where('uid', '==', uid).where('active', '==', true).count().get();
    if (running.data().count >= MAX_RUNNING) {
        throw new https_1.HttpsError('resource-exhausted', 'Three models are already being prepared. Wait for one to finish.');
    }
}
async function ownProduct(uid, raw) {
    if (raw == null || raw === '')
        return null;
    const productId = safeId(raw);
    const p = await db().collection('products').doc(productId).get();
    // The product may not be saved yet (the creator reserves its id first).
    if (p.exists && p.get('ownerId') !== uid)
        throw new https_1.HttpsError('permission-denied', 'This isn’t your product.');
    return productId;
}
const cleanName = (v, fallback) => String(v !== null && v !== void 0 ? v : '').trim().slice(0, 80) || fallback;
// ── Callables ───────────────────────────────────────────────────────────
exports.model3dCreate = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    var _e, _f;
    const uid = uidOf(req);
    const id = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.modelId);
    const fileName = String((_e = (_b = req.data) === null || _b === void 0 ? void 0 : _b.fileName) !== null && _e !== void 0 ? _e : '');
    if (!/^[A-Za-z0-9_.-]{1,80}$/.test(fileName))
        throw new https_1.HttpsError('invalid-argument', 'Rename the file with plain letters and numbers.');
    await guardQuota(uid);
    const sourcePath = `${root(uid, id)}/source/${fileName}`;
    const file = bucket().file(sourcePath);
    const [exists] = await file.exists();
    if (!exists)
        throw new https_1.HttpsError('not-found', 'The file did not finish uploading. Try again.');
    const [meta] = await file.getMetadata();
    const size = Number((_f = meta.size) !== null && _f !== void 0 ? _f : 0);
    if (size <= 0 || size > convert_1.MAX_SOURCE_BYTES)
        throw new https_1.HttpsError('invalid-argument', '3D files must be under 100 MB.');
    const [head] = await file.download({ start: 0, end: 15 });
    const format = (0, convert_1.detectFormat)(fileName, head);
    if (!format)
        throw new https_1.HttpsError('invalid-argument', 'Use a .glb, .gltf, .obj or .stl file.');
    if ((await jobRef(id).get()).exists)
        throw new https_1.HttpsError('already-exists', 'This model is already in your library.');
    const productId = await ownProduct(uid, (_c = req.data) === null || _c === void 0 ? void 0 : _c.productId);
    const name = cleanName((_d = req.data) === null || _d === void 0 ? void 0 : _d.name, fileName.replace(/\.[^.]+$/, ''));
    await libRef(uid, id).set({
        name, kind: 'upload', format, sourceBytes: size, productId, status: 'queued', stage: 'Waiting to start', progress: 0.02,
        steps: [{ at: Date.now(), text: 'File received' }], createdAt: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    await jobRef(id).set({
        uid, kind: 'upload', status: 'queued', active: true, sourcePath, format, productId,
        createdAt: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    return { modelId: id };
});
exports.model3dGenerate = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    const uid = uidOf(req);
    const id = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.modelId);
    const count = Number((_b = req.data) === null || _b === void 0 ? void 0 : _b.photoCount);
    if (!Number.isInteger(count) || count < 1 || count > 4)
        throw new https_1.HttpsError('invalid-argument', 'Add one to four photos.');
    await guardQuota(uid);
    const photoPaths = [];
    for (let i = 0; i < count; i++) {
        const path = `${root(uid, id)}/photos/${i}.jpg`;
        const [exists] = await bucket().file(path).exists();
        if (!exists)
            throw new https_1.HttpsError('not-found', 'A photo did not finish uploading. Try again.');
        photoPaths.push(path);
    }
    if ((await jobRef(id).get()).exists)
        throw new https_1.HttpsError('already-exists', 'This model is already in your library.');
    const productId = await ownProduct(uid, (_c = req.data) === null || _c === void 0 ? void 0 : _c.productId);
    const engine = await (0, providers_1.engineFor)(uid);
    const name = cleanName((_d = req.data) === null || _d === void 0 ? void 0 : _d.name, 'Product model');
    const [thumbUrl] = await Promise.all([(0, storage_1.getDownloadURL)(bucket().file(photoPaths[0]))]);
    const base = {
        name, kind: 'generate', productId, photoCount: count, thumbUrl,
        createdAt: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp(),
    };
    if (!engine) {
        // Kept in the library so it can start the moment an engine is available.
        await libRef(uid, id).set(Object.assign(Object.assign({}, base), { status: 'needs_engine', progress: 0, stage: 'Photos saved. Link a 3D provider to build this model.', steps: [{ at: Date.now(), text: 'Photos saved' }] }));
        await jobRef(id).set({ uid, kind: 'generate', status: 'needs_engine', active: false, photoPaths, productId, createdAt: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp() });
        return { modelId: id, status: 'needs_engine' };
    }
    await libRef(uid, id).set(Object.assign(Object.assign({}, base), { status: 'queued', stage: 'Waiting to start', progress: 0.02, engine: engine.id, engineOwner: engine.owner, steps: [{ at: Date.now(), text: count > 1 ? `${count} photos received` : 'Photo received' }] }));
    await jobRef(id).set({
        uid, kind: 'generate', status: 'queued', active: true, photoPaths, productId, engineOwner: engine.owner,
        createdAt: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    return { modelId: id, status: 'queued' };
});
/** Starts a model that was waiting for an engine (after linking a provider). */
exports.model3dResume = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = uidOf(req);
    const id = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.modelId);
    const job = await jobRef(id).get();
    if (job.get('uid') !== uid)
        throw new https_1.HttpsError('not-found', 'Model not found.');
    if (!['needs_engine', 'failed'].includes(String(job.get('status'))) || job.get('kind') !== 'generate') {
        throw new https_1.HttpsError('failed-precondition', 'This model is already being prepared.');
    }
    const engine = await (0, providers_1.engineFor)(uid);
    if (!engine)
        throw new https_1.HttpsError('failed-precondition', 'Link a 3D provider first.');
    await guardQuota(uid);
    await report(uid, id, 'queued', 'Waiting to start', 0.02, { engine: engine.id, engineOwner: engine.owner, error: firestore_2.FieldValue.delete() });
    await job.ref.update({ status: 'queued', active: true, engineOwner: engine.owner, error: firestore_2.FieldValue.delete(), updatedAt: firestore_2.FieldValue.serverTimestamp() });
    return { ok: true };
});
exports.model3dAttach = (0, https_1.onCall)({ memory: '512MiB', timeoutSeconds: 120 }, async (req) => {
    var _a, _b;
    const uid = uidOf(req);
    const id = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.modelId);
    const productId = safeId((_b = req.data) === null || _b === void 0 ? void 0 : _b.productId);
    const job = await jobRef(id).get();
    if (job.get('uid') !== uid || job.get('status') !== 'ready')
        throw new https_1.HttpsError('failed-precondition', 'This model isn’t ready yet.');
    const product = await db().collection('products').doc(productId).get();
    if (product.exists && product.get('ownerId') !== uid)
        throw new https_1.HttpsError('permission-denied', 'This isn’t your product.');
    const urls = await publish(uid, id, productId, product.exists);
    await libRef(uid, id).set({ productId, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
    return urls;
});
exports.model3dDelete = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = uidOf(req);
    const id = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.modelId);
    const job = await jobRef(id).get();
    if (job.exists && job.get('uid') !== uid)
        throw new https_1.HttpsError('not-found', 'Model not found.');
    await bucket().deleteFiles({ prefix: `${root(uid, id)}/` }).catch((e) => { var _a; return logger.warn('model files not removed', id, (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e); });
    await Promise.all([jobRef(id).delete(), libRef(uid, id).delete()]);
    return { ok: true };
});
exports.model3dLinkProvider = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c, _d;
    const uid = uidOf(req);
    const engine = String((_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.engine) !== null && _c !== void 0 ? _c : '');
    if (!(engine in providers_1.ENGINES))
        throw new https_1.HttpsError('invalid-argument', 'Unknown provider.');
    await (0, providers_1.linkProvider)(uid, engine, String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.apiKey) !== null && _d !== void 0 ? _d : ''));
    return { ok: true };
});
exports.model3dUnlinkProvider = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = uidOf(req);
    const engine = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.engine) !== null && _b !== void 0 ? _b : '');
    if (!(engine in providers_1.ENGINES))
        throw new https_1.HttpsError('invalid-argument', 'Unknown provider.');
    await (0, providers_1.unlinkProvider)(uid, engine);
    return { ok: true };
});
/** Whether photo → 3D can run for this seller, and with whose engine. */
exports.model3dEngineStatus = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const engine = await (0, providers_1.engineFor)(uidOf(req));
    return { available: engine !== null, owner: (_a = engine === null || engine === void 0 ? void 0 : engine.owner) !== null && _a !== void 0 ? _a : null, engine: (_b = engine === null || engine === void 0 ? void 0 : engine.id) !== null && _b !== void 0 ? _b : null };
});
// ── Publishing to a product ─────────────────────────────────────────────
async function publish(uid, id, productId, productExists) {
    var _a;
    var _b, _c;
    const lib = (_b = (await libRef(uid, id).get()).data()) !== null && _b !== void 0 ? _b : {};
    const out = {};
    const stamp = crypto.randomBytes(4).toString('hex');
    for (const v of ['mobile', 'hd', 'ar']) {
        const dest = bucket().file(`shops/${uid}/products/${productId}/model/${id}_${v}_${stamp}.glb`);
        await bucket().file(`${root(uid, id)}/out/${v}.glb`).copy(dest);
        await dest.setMetadata({ contentType: 'model/gltf-binary', cacheControl: 'public, max-age=31536000, immutable' });
        out[v] = await (0, storage_1.getDownloadURL)(dest);
    }
    const fields = {
        model3dUrl: out.mobile,
        model3dHdUrl: out.hd,
        model3dArUrl: out.ar,
        model3dId: id,
        modelAnimations: (_c = (_a = lib.stats) === null || _a === void 0 ? void 0 : _a.animations) !== null && _c !== void 0 ? _c : [],
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    };
    // A product that isn't saved yet gets the model when the seller saves it.
    if (productExists)
        await db().collection('products').doc(productId).set(fields, { merge: true });
    return { model3dUrl: out.mobile, model3dHdUrl: out.hd, model3dArUrl: out.ar, modelAnimations: fields.modelAnimations };
}
// ── Worker ──────────────────────────────────────────────────────────────
async function process(id, job) {
    var _a;
    const uid = String(job.uid);
    let bytes;
    let format;
    if (job.remoteGlbUrl) {
        await report(uid, id, 'optimizing', 'Collecting the finished model', 0.72);
        const res = await fetch(String(job.remoteGlbUrl), { signal: AbortSignal.timeout(120000) });
        if (!res.ok)
            throw new convert_1.ModelError('The finished model could not be collected. Try again.');
        bytes = Buffer.from(await res.arrayBuffer());
        format = 'glb';
        // Keep the engine's original in the private library too.
        await bucket().file(`${root(uid, id)}/source/generated.glb`).save(bytes, { contentType: 'model/gltf-binary', resumable: false });
    }
    else {
        await report(uid, id, 'converting', 'Reading your 3D file', 0.1);
        [bytes] = await bucket().file(String(job.sourcePath)).download();
        format = job.format;
    }
    await report(uid, id, 'optimizing', 'Optimizing for phones, tablets and AR', job.remoteGlbUrl ? 0.8 : 0.35);
    const out = await (0, optimize_1.optimizeModel)(bytes, format);
    await report(uid, id, 'optimizing', 'Hosting the optimized files', 0.92);
    const files = {};
    for (const [v, data] of [['mobile', out.mobile], ['hd', out.hd], ['ar', out.ar]]) {
        const file = bucket().file(`${root(uid, id)}/out/${v}.glb`);
        await file.save(Buffer.from(data), { contentType: 'model/gltf-binary', resumable: false, metadata: { cacheControl: 'private, max-age=86400' } });
        files[v] = { path: file.name, bytes: data.byteLength, url: await (0, storage_1.getDownloadURL)(file) };
    }
    await jobRef(id).set({ status: 'ready', active: false, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
    const saved = Math.max(0, Math.round((1 - out.mobile.byteLength / bytes.byteLength) * 100));
    await report(uid, id, 'ready', saved > 0 ? `Ready · ${saved}% lighter on phones` : 'Ready', 1, {
        files, stats: Object.assign(Object.assign({}, out.source), { mobileTriangles: out.mobileTriangles }), sourceBytes: bytes.byteLength, error: firestore_2.FieldValue.delete(),
    });
    let route = '/shops/models';
    if (job.productId) {
        const product = await db().collection('products').doc(String(job.productId)).get();
        if (!product.exists || product.get('ownerId') === uid) {
            await publish(uid, id, String(job.productId), product.exists);
            if (product.exists)
                route = `/shops/product/edit?id=${job.productId}`;
        }
    }
    const name = String((_a = (await libRef(uid, id).get()).get('name')) !== null && _a !== void 0 ? _a : 'Your model');
    await db().collection('notifications').doc(`model3d_${id}`).set({
        userId: uid, recipientId: uid, category: 'system', priority: 'normal', type: 'commerce',
        title: 'Your 3D model is ready', body: `${name} is optimized and in your library.`, deepLink: route,
        isRead: false, createdAt: firestore_2.FieldValue.serverTimestamp(),
    });
}
async function startGeneration(id, job) {
    const uid = String(job.uid);
    const engine = await (0, providers_1.engineOf)(uid, job.engineOwner === 'user' ? 'user' : 'oneova');
    if (!engine) {
        await jobRef(id).set({ status: 'needs_engine', active: false, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
        await report(uid, id, 'needs_engine', 'Link a 3D provider to build this model.', 0);
        return;
    }
    await report(uid, id, 'generating', 'Sending your photos to the 3D engine', 0.06);
    const urls = await Promise.all(job.photoPaths.map((p) => (0, storage_1.getDownloadURL)(bucket().file(p))));
    let task;
    try {
        task = await (0, providers_1.submitGeneration)(engine, urls);
    }
    catch (e) {
        const msg = (e === null || e === void 0 ? void 0 : e.status) === 402 ? `Your ${providers_1.ENGINES[engine.id].label} account is out of credits.`
            : (e === null || e === void 0 ? void 0 : e.status) === 401 || (e === null || e === void 0 ? void 0 : e.status) === 403 ? `${providers_1.ENGINES[engine.id].label} no longer accepts the linked key. Link it again.`
                : 'The 3D engine did not accept these photos. Try clearer photos on a plain background.';
        throw new convert_1.ModelError(msg);
    }
    await jobRef(id).set({ status: 'generating', task, generatingSince: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
    await report(uid, id, 'generating', 'Building the shape from your photos', 0.1);
}
exports.model3dWorker = (0, firestore_1.onDocumentWritten)({ document: 'model3d_jobs/{id}', memory: '4GiB', cpu: 2, timeoutSeconds: 540, concurrency: 1, retry: false }, async (event) => {
    var _a, _b;
    var _c;
    const after = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after.data();
    const before = (_b = event.data) === null || _b === void 0 ? void 0 : _b.before.data();
    if (!after || after.status === (before === null || before === void 0 ? void 0 : before.status))
        return;
    const id = event.params.id;
    try {
        if (after.status === 'queued' && after.kind === 'generate')
            await startGeneration(id, after);
        else if (after.status === 'queued' || after.status === 'process')
            await process(id, after);
    }
    catch (e) {
        const known = e instanceof convert_1.ModelError;
        if (!known)
            logger.error('model3d worker failed', id, (_c = e === null || e === void 0 ? void 0 : e.message) !== null && _c !== void 0 ? _c : e);
        await fail(String(after.uid), id, known ? e.message : 'Something went wrong while preparing this model. Try again.');
    }
});
const STAGES = [
    [0.25, 'Building the shape from your photos'],
    [0.6, 'Refining edges and details'],
    [0.9, 'Painting the texture from your photos'],
    [1.01, 'Finishing the model'],
];
/** Follows running generations and fails jobs that stopped moving. */
exports.model3dSweep = (0, scheduler_1.onSchedule)({ schedule: 'every 1 minutes', timeoutSeconds: 55 }, async () => {
    const running = await db().collection('model3d_jobs').where('status', '==', 'generating').limit(40).get();
    await Promise.all(running.docs.map(async (doc) => {
        var _a;
        var _b, _c, _d;
        const job = doc.data();
        const uid = String(job.uid);
        try {
            const engine = await (0, providers_1.engineOf)(uid, job.engineOwner === 'user' ? 'user' : 'oneova');
            if (!engine)
                return fail(uid, doc.id, 'The linked 3D provider was removed before the model finished.');
            const s = await (0, providers_1.pollGeneration)(engine, job.task);
            if (s.state === 'failed')
                return fail(uid, doc.id, (_b = s.error) !== null && _b !== void 0 ? _b : 'The engine could not build this model.');
            if (s.state === 'done') {
                // Hands over to the worker (it has the memory for optimizing).
                await doc.ref.update({ status: 'process', remoteGlbUrl: s.glbUrl, updatedAt: firestore_2.FieldValue.serverTimestamp() });
                return;
            }
            const since = (_c = (_a = job.generatingSince) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _c !== void 0 ? _c : Date.now();
            if (Date.now() - since > STUCK_MS)
                return fail(uid, doc.id, 'This model took too long. Try again with clearer photos.');
            const stage = STAGES.find(([limit]) => s.progress < limit)[1];
            await libRef(uid, doc.id).set({ status: 'generating', stage, progress: 0.1 + s.progress * 0.6, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
        }
        catch (e) {
            logger.warn('model3d poll failed', doc.id, (_d = e === null || e === void 0 ? void 0 : e.message) !== null && _d !== void 0 ? _d : e);
        }
    }));
    // Jobs whose worker died (out of memory, timeout) would otherwise spin forever.
    const stuck = await db().collection('model3d_jobs').where('active', '==', true)
        .where('updatedAt', '<', firestore_2.Timestamp.fromMillis(Date.now() - STUCK_MS)).limit(20).get();
    await Promise.all(stuck.docs
        .filter((d) => d.get('status') !== 'generating')
        .map((d) => fail(String(d.get('uid')), d.id, 'This model could not be prepared. Try a smaller file.')));
});
//# sourceMappingURL=index.js.map