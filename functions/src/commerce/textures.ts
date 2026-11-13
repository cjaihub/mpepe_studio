/**
 * Hosted texture library for 3D products and live stages.
 *
 *   textureLibrary  the built-in library (`texture_library`). Missing
 *                   textures are rendered and uploaded on first use, so the
 *                   library fills itself; later calls only read.
 *   textureCreate   a seller's own colorway of any kind, hosted under
 *                   `shops/{uid}/textures/` and listed in
 *                   `biz_shops/{uid}/textures`.
 *
 * Images are seamless PNGs from textureEngine.ts; the app's 3D viewer puts
 * them on the model's materials with the stored roughness / metallic / scale.
 */
import * as crypto from 'crypto';
import { PNG } from 'pngjs';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage, getDownloadURL } from 'firebase-admin/storage';
import { BUILT_IN, MATERIAL, renderTexture, TEXTURE_KINDS, TextureKind, TextureSpec } from './textureEngine';

const db = () => getFirestore();
const SIZE = 512;
const MAX_PER_SHOP = 60;

async function host(path: string, spec: TextureSpec): Promise<string> {
  const png = new PNG({ width: SIZE, height: SIZE });
  png.data = Buffer.from(renderTexture({ ...spec, size: SIZE }));
  const file = getStorage().bucket().file(path);
  await file.save(PNG.sync.write(png), {
    contentType: 'image/png',
    metadata: { cacheControl: 'public, max-age=31536000, immutable' },
    resumable: false,
  });
  return getDownloadURL(file);
}

function docFor(name: string, spec: TextureSpec, url: string) {
  const m = MATERIAL[spec.kind];
  return {
    name, kind: spec.kind, category: m.category, colors: spec.colors, url,
    roughness: m.roughness, metallic: m.metallic, scale: m.scale,
  };
}

export const textureLibrary = onCall({ memory: '1GiB', timeoutSeconds: 300 }, async (req) => {
  if (!req.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const col = db().collection('texture_library');
  const have = new Set((await col.select().get()).docs.map((d) => d.id));
  const missing = BUILT_IN.filter((t) => !have.has(t.id));
  for (const [i, t] of missing.entries()) {
    try {
      const url = await host(`textures/library/${t.id}.png`, t.spec);
      await col.doc(t.id).set({
        ...docFor(t.name, t.spec, url), builtIn: true, order: BUILT_IN.indexOf(t), createdAt: FieldValue.serverTimestamp(),
      });
    } catch (e: any) {
      logger.error('texture render failed', t.id, i, e?.message ?? e);
    }
  }
  const all = await col.orderBy('order').get();
  return { textures: all.docs.map((d) => ({ id: d.id, ...d.data(), createdAt: null })) };
});

export const textureCreate = onCall({ memory: '512MiB', timeoutSeconds: 60 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const kind = String(req.data?.kind ?? '') as TextureKind;
  if (!TEXTURE_KINDS.includes(kind)) throw new HttpsError('invalid-argument', 'Pick a material.');
  const colors = (Array.isArray(req.data?.colors) ? req.data.colors : [])
    .map((c: unknown) => String(c))
    .filter((c: string) => /^#?[0-9a-fA-F]{6}$/.test(c))
    .slice(0, 4)
    .map((c: string) => (c.startsWith('#') ? c : `#${c}`));
  if (colors.length < 1) throw new HttpsError('invalid-argument', 'Pick at least one color.');
  const name = String(req.data?.name ?? MATERIAL[kind].label).trim().slice(0, 40) || MATERIAL[kind].label;
  const shopRef = db().collection('biz_shops').doc(uid);
  if (!(await shopRef.get()).exists) throw new HttpsError('failed-precondition', 'Set up your shop first.');
  const mine = shopRef.collection('textures');
  if ((await mine.count().get()).data().count >= MAX_PER_SHOP) {
    throw new HttpsError('resource-exhausted', `You can keep up to ${MAX_PER_SHOP} textures. Delete one to add more.`);
  }
  const id = crypto.randomBytes(8).toString('hex');
  const spec: TextureSpec = { kind, colors, seed: crypto.randomInt(1, 1_000_000) };
  const url = await host(`shops/${uid}/textures/${id}.png`, spec);
  const doc = { ...docFor(name, spec, url), builtIn: false, createdAt: FieldValue.serverTimestamp() };
  await mine.doc(id).set(doc);
  return { id, ...doc, createdAt: null };
});
