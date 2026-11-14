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
 *   model3dGenerate       1–4 product photos → 3D on Oneova's own GPU server
 *   model3dWorker         converts, optimizes for phones / tablets / AR, hosts
 *   model3dSweep          fails jobs whose worker stopped
 *   model3dAttach         puts a ready model on one of the owner's products
 *   model3dDelete         removes a model and its files
 *   model3dLinkProvider / model3dUnlinkProvider   retired (no outside 3D
 *                         services); unlink clears a key from an old version
 *
 * Work continues when the app is closed; the owner gets a notification when
 * the model is ready.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getStorage, getDownloadURL } from 'firebase-admin/storage';
import { detectFormat, MAX_SOURCE_BYTES, ModelError, ModelFormat } from './convert';
import { optimizeModel } from './optimize';
import { estimatedProgress } from './engineLogic';
import { ENGINE_LABEL, EngineError, engineFor, linkProvider, runGeneration, unlinkProvider } from './providers';

const db = () => getFirestore();
const bucket = () => getStorage().bucket();

const MAX_MODELS = 200;
const MAX_RUNNING = 3;
const STUCK_MS = 20 * 60_000;
/** The worker runs for up to 540 s; the GPU call gets most of it. */
const ENGINE_TIMEOUT_MS = 480_000;

function uidOf(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

const safeId = (v: unknown) => {
  const s = String(v ?? '');
  if (!/^[A-Za-z0-9_-]{6,64}$/.test(s)) throw new HttpsError('invalid-argument', 'Missing id.');
  return s;
};

const libRef = (uid: string, id: string) => db().doc(`users/${uid}/models3d/${id}`);
const jobRef = (id: string) => db().collection('model3d_jobs').doc(id);
const root = (uid: string, id: string) => `users/${uid}/models3d/${id}`;

/** Updates what the owner sees: the current step, progress and a short activity log. */
async function report(uid: string, id: string, status: string, stage: string, progress: number, extra: Record<string, unknown> = {}) {
  await libRef(uid, id).set({
    status, stage, progress,
    steps: FieldValue.arrayUnion({ at: Date.now(), text: stage }),
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  }, { merge: true });
}

async function fail(uid: string, id: string, message: string) {
  await jobRef(id).set({ status: 'failed', active: false, error: message, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await report(uid, id, 'failed', message, 0, { error: message });
}

async function guardQuota(uid: string) {
  const col = db().collection(`users/${uid}/models3d`);
  if ((await col.count().get()).data().count >= MAX_MODELS) {
    throw new HttpsError('resource-exhausted', `Your library holds up to ${MAX_MODELS} models. Delete one to add more.`);
  }
  const running = await db().collection('model3d_jobs').where('uid', '==', uid).where('active', '==', true).count().get();
  if (running.data().count >= MAX_RUNNING) {
    throw new HttpsError('resource-exhausted', 'Three models are already being prepared. Wait for one to finish.');
  }
}

async function ownProduct(uid: string, raw: unknown): Promise<string | null> {
  if (raw == null || raw === '') return null;
  const productId = safeId(raw);
  const p = await db().collection('products').doc(productId).get();
  // The product may not be saved yet (the creator reserves its id first).
  if (p.exists && p.get('ownerId') !== uid) throw new HttpsError('permission-denied', 'This isn’t your product.');
  return productId;
}

const cleanName = (v: unknown, fallback: string) => String(v ?? '').trim().slice(0, 80) || fallback;

// ── Callables ───────────────────────────────────────────────────────────

export const model3dCreate = onCall(async (req) => {
  const uid = uidOf(req);
  const id = safeId(req.data?.modelId);
  const fileName = String(req.data?.fileName ?? '');
  if (!/^[A-Za-z0-9_.-]{1,80}$/.test(fileName)) throw new HttpsError('invalid-argument', 'Rename the file with plain letters and numbers.');
  await guardQuota(uid);
  const sourcePath = `${root(uid, id)}/source/${fileName}`;
  const file = bucket().file(sourcePath);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('not-found', 'The file did not finish uploading. Try again.');
  const [meta] = await file.getMetadata();
  const size = Number(meta.size ?? 0);
  if (size <= 0 || size > MAX_SOURCE_BYTES) throw new HttpsError('invalid-argument', '3D files must be under 100 MB.');
  const [head] = await file.download({ start: 0, end: 15 });
  const format = detectFormat(fileName, head);
  if (!format) throw new HttpsError('invalid-argument', 'Use a .glb, .gltf, .obj or .stl file.');
  if ((await jobRef(id).get()).exists) throw new HttpsError('already-exists', 'This model is already in your library.');
  const productId = await ownProduct(uid, req.data?.productId);
  const name = cleanName(req.data?.name, fileName.replace(/\.[^.]+$/, ''));
  await libRef(uid, id).set({
    name, kind: 'upload', format, sourceBytes: size, productId, status: 'queued', stage: 'Waiting to start', progress: 0.02,
    steps: [{ at: Date.now(), text: 'File received' }], createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  await jobRef(id).set({
    uid, kind: 'upload', status: 'queued', active: true, sourcePath, format, productId,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  return { modelId: id };
});

export const model3dGenerate = onCall(async (req) => {
  const uid = uidOf(req);
  const id = safeId(req.data?.modelId);
  const count = Number(req.data?.photoCount);
  if (!Number.isInteger(count) || count < 1 || count > 4) throw new HttpsError('invalid-argument', 'Add one to four photos.');
  await guardQuota(uid);
  const photoPaths: string[] = [];
  for (let i = 0; i < count; i++) {
    const path = `${root(uid, id)}/photos/${i}.jpg`;
    const [exists] = await bucket().file(path).exists();
    if (!exists) throw new HttpsError('not-found', 'A photo did not finish uploading. Try again.');
    photoPaths.push(path);
  }
  if ((await jobRef(id).get()).exists) throw new HttpsError('already-exists', 'This model is already in your library.');
  const productId = await ownProduct(uid, req.data?.productId);
  const engine = await engineFor(uid);
  const name = cleanName(req.data?.name, 'Product model');
  const [thumbUrl] = await Promise.all([getDownloadURL(bucket().file(photoPaths[0]))]);
  const base = {
    name, kind: 'generate', productId, photoCount: count, thumbUrl,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  };
  if (!engine) {
    // Kept in the library so it can start the moment an engine is available.
    await libRef(uid, id).set({
      ...base, status: 'needs_engine', progress: 0,
      stage: 'Photos saved. The 3D builder is switching on; tap Build now later.',
      steps: [{ at: Date.now(), text: 'Photos saved' }],
    });
    await jobRef(id).set({ uid, kind: 'generate', status: 'needs_engine', active: false, photoPaths, productId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    return { modelId: id, status: 'needs_engine' };
  }
  await libRef(uid, id).set({
    ...base, status: 'queued', stage: 'Waiting to start', progress: 0.02, engine: engine.id, engineOwner: engine.owner,
    steps: [{ at: Date.now(), text: count > 1 ? `${count} photos received` : 'Photo received' }],
  });
  await jobRef(id).set({
    uid, kind: 'generate', status: 'queued', active: true, photoPaths, productId, engineOwner: engine.owner,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  return { modelId: id, status: 'queued' };
});

/** Starts a model that was waiting for an engine (after linking a provider). */
export const model3dResume = onCall(async (req) => {
  const uid = uidOf(req);
  const id = safeId(req.data?.modelId);
  const job = await jobRef(id).get();
  if (job.get('uid') !== uid) throw new HttpsError('not-found', 'Model not found.');
  if (!['needs_engine', 'failed'].includes(String(job.get('status'))) || job.get('kind') !== 'generate') {
    throw new HttpsError('failed-precondition', 'This model is already being prepared.');
  }
  const engine = await engineFor(uid);
  if (!engine) throw new HttpsError('failed-precondition', 'The 3D builder isn’t switched on yet. Your photos are saved.');
  await guardQuota(uid);
  await report(uid, id, 'queued', 'Waiting to start', 0.02, { engine: engine.id, engineOwner: engine.owner, error: FieldValue.delete() });
  await job.ref.update({ status: 'queued', active: true, engineOwner: engine.owner, error: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
  return { ok: true };
});

export const model3dAttach = onCall({ memory: '512MiB', timeoutSeconds: 120 }, async (req) => {
  const uid = uidOf(req);
  const id = safeId(req.data?.modelId);
  const productId = safeId(req.data?.productId);
  const job = await jobRef(id).get();
  if (job.get('uid') !== uid || job.get('status') !== 'ready') throw new HttpsError('failed-precondition', 'This model isn’t ready yet.');
  const product = await db().collection('products').doc(productId).get();
  if (product.exists && product.get('ownerId') !== uid) throw new HttpsError('permission-denied', 'This isn’t your product.');
  const urls = await publish(uid, id, productId, product.exists);
  await libRef(uid, id).set({ productId, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return urls;
});

export const model3dDelete = onCall(async (req) => {
  const uid = uidOf(req);
  const id = safeId(req.data?.modelId);
  const job = await jobRef(id).get();
  if (job.exists && job.get('uid') !== uid) throw new HttpsError('not-found', 'Model not found.');
  await bucket().deleteFiles({ prefix: `${root(uid, id)}/` }).catch((e) => logger.warn('model files not removed', id, e?.message ?? e));
  await Promise.all([jobRef(id).delete(), libRef(uid, id).delete()]);
  return { ok: true };
});

/** Retired: Oneova doesn't use outside 3D services. Kept so old app builds get a clear answer. */
export const model3dLinkProvider = onCall(async (req) => {
  uidOf(req);
  return linkProvider();
});

/** Clears a provider key a seller linked in an earlier version. */
export const model3dUnlinkProvider = onCall(async (req) => {
  await unlinkProvider(uidOf(req));
  return { ok: true };
});

/** Whether photo → 3D can run right now. */
export const model3dEngineStatus = onCall(async (req) => {
  const engine = await engineFor(uidOf(req));
  return { available: engine !== null, owner: engine?.owner ?? null, engine: engine?.id ?? null, label: ENGINE_LABEL };
});

// ── Publishing to a product ─────────────────────────────────────────────

async function publish(uid: string, id: string, productId: string, productExists: boolean) {
  const lib = (await libRef(uid, id).get()).data() ?? {};
  const out: Record<string, string> = {};
  const stamp = crypto.randomBytes(4).toString('hex');
  for (const v of ['mobile', 'hd', 'ar'] as const) {
    const dest = bucket().file(`shops/${uid}/products/${productId}/model/${id}_${v}_${stamp}.glb`);
    await bucket().file(`${root(uid, id)}/out/${v}.glb`).copy(dest);
    await dest.setMetadata({ contentType: 'model/gltf-binary', cacheControl: 'public, max-age=31536000, immutable' });
    out[v] = await getDownloadURL(dest);
  }
  const fields = {
    model3dUrl: out.mobile,
    model3dHdUrl: out.hd,
    model3dArUrl: out.ar,
    model3dId: id,
    modelAnimations: lib.stats?.animations ?? [],
    updatedAt: FieldValue.serverTimestamp(),
  };
  // A product that isn't saved yet gets the model when the seller saves it.
  if (productExists) await db().collection('products').doc(productId).set(fields, { merge: true });
  return { model3dUrl: out.mobile, model3dHdUrl: out.hd, model3dArUrl: out.ar, modelAnimations: fields.modelAnimations };
}

// ── Worker ──────────────────────────────────────────────────────────────

async function process(id: string, job: FirebaseFirestore.DocumentData) {
  const uid = String(job.uid);
  const generated = job.kind === 'generate';
  const sourcePath = String(job.sourcePath ?? '');
  // Only files inside this model's own folder (the GPU server writes to source/engine/).
  if (!sourcePath.startsWith(`${root(uid, id)}/source/`)) throw new ModelError('The model file is missing. Try again.');
  await report(uid, id, generated ? 'optimizing' : 'converting', generated ? 'Collecting the finished model' : 'Reading your 3D file', generated ? 0.72 : 0.1);
  const [bytes] = await bucket().file(sourcePath).download();
  const format = (generated ? 'glb' : job.format) as ModelFormat;
  await report(uid, id, 'optimizing', 'Optimizing for phones, tablets and AR', generated ? 0.8 : 0.35);
  const out = await optimizeModel(bytes, format);
  await report(uid, id, 'optimizing', 'Hosting the optimized files', 0.92);
  const files: Record<string, { path: string; bytes: number; url: string }> = {};
  for (const [v, data] of [['mobile', out.mobile], ['hd', out.hd], ['ar', out.ar]] as const) {
    const file = bucket().file(`${root(uid, id)}/out/${v}.glb`);
    await file.save(Buffer.from(data), { contentType: 'model/gltf-binary', resumable: false, metadata: { cacheControl: 'private, max-age=86400' } });
    files[v] = { path: file.name, bytes: data.byteLength, url: await getDownloadURL(file) };
  }
  await jobRef(id).set({ status: 'ready', active: false, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const saved = Math.max(0, Math.round((1 - out.mobile.byteLength / bytes.byteLength) * 100));
  await report(uid, id, 'ready', saved > 0 ? `Ready · ${saved}% lighter on phones` : 'Ready', 1, {
    files, stats: { ...out.source, mobileTriangles: out.mobileTriangles }, sourceBytes: bytes.byteLength, error: FieldValue.delete(),
  });
  let route = '/shops/models';
  if (job.productId) {
    const product = await db().collection('products').doc(String(job.productId)).get();
    if (!product.exists || product.get('ownerId') === uid) {
      await publish(uid, id, String(job.productId), product.exists);
      if (product.exists) route = `/shops/product/edit?id=${job.productId}`;
    }
  }
  const name = String((await libRef(uid, id).get()).get('name') ?? 'Your model');
  await db().collection('notifications').doc(`model3d_${id}`).set({
    userId: uid, recipientId: uid, category: 'system', priority: 'normal', type: 'commerce',
    title: 'Your 3D model is ready', body: `${name} is optimized and in your library.`, deepLink: route,
    isRead: false, createdAt: FieldValue.serverTimestamp(),
  });
}

async function startGeneration(id: string, job: FirebaseFirestore.DocumentData) {
  const uid = String(job.uid);
  const engine = await engineFor(uid);
  if (!engine) {
    await jobRef(id).set({ status: 'needs_engine', active: false, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await report(uid, id, 'needs_engine', 'Photos saved. The 3D builder is switching on; tap Build now later.', 0);
    return;
  }
  await jobRef(id).set({ status: 'generating', generatingSince: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await report(uid, id, 'generating', 'Sending your photos to the 3D builder', 0.06);
  // The GPU server gives no live progress, so the owner sees a steady estimate.
  const started = Date.now();
  let lastStage = '';
  const ticker = setInterval(() => {
    const p = estimatedProgress(Date.now() - started);
    const first = p.stage !== lastStage;
    lastStage = p.stage;
    libRef(uid, id).set({
      status: 'generating', stage: p.stage, progress: p.progress, updatedAt: FieldValue.serverTimestamp(),
      ...(first ? { steps: FieldValue.arrayUnion({ at: Date.now(), text: p.stage }) } : {}),
    }, { merge: true }).catch(() => undefined);
    jobRef(id).set({ updatedAt: FieldValue.serverTimestamp() }, { merge: true }).catch(() => undefined);
  }, 15_000);
  let glbPath: string;
  try {
    glbPath = await runGeneration(engine, bucket().name, job.photoPaths as string[], `${root(uid, id)}/source/engine`, ENGINE_TIMEOUT_MS);
  } catch (e: any) {
    throw new ModelError(e instanceof EngineError ? e.message : 'The 3D builder could not build this model. Try again.');
  } finally {
    clearInterval(ticker);
  }
  const [exists] = await bucket().file(glbPath).exists();
  if (!exists) throw new ModelError('The 3D builder finished without a model. Try clearer photos.');
  // Hands over to a fresh worker run (full time budget for optimizing).
  await jobRef(id).set({ status: 'process', sourcePath: glbPath, format: 'glb', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

export const model3dWorker = onDocumentWritten(
  { document: 'model3d_jobs/{id}', memory: '4GiB', cpu: 2, timeoutSeconds: 540, concurrency: 1, retry: false },
  async (event) => {
    const after = event.data?.after.data();
    const before = event.data?.before.data();
    if (!after || after.status === before?.status) return;
    const id = event.params.id;
    try {
      if (after.status === 'queued' && after.kind === 'generate') await startGeneration(id, after);
      else if (after.status === 'queued' || after.status === 'process') await process(id, after);
    } catch (e: any) {
      const known = e instanceof ModelError;
      if (!known) logger.error('model3d worker failed', id, e?.message ?? e);
      await fail(String(after.uid), id, known ? e.message : 'Something went wrong while preparing this model. Try again.');
    }
  },
);

/** Fails jobs whose worker stopped (timeout, out of memory) so nothing spins forever. */
export const model3dSweep = onSchedule({ schedule: 'every 5 minutes', timeoutSeconds: 55 }, async () => {
  const stuck = await db().collection('model3d_jobs').where('active', '==', true)
    .where('updatedAt', '<', Timestamp.fromMillis(Date.now() - STUCK_MS)).limit(40).get();
  await Promise.all(stuck.docs.map((d) => fail(
    String(d.get('uid')), d.id,
    d.get('kind') === 'generate' ? 'This model took too long. Try again with fewer or clearer photos.' : 'This model could not be prepared. Try a smaller file.',
  )));
});
