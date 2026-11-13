/**
 * Photo → 3D engines.
 *
 * A seller can link their own provider account (their key is encrypted and
 * kept server-side in `model3d_keys/{uid}`, which no client can read), or
 * Oneova's built-in engine is used when the platform key exists
 * (optional secret MESHY_API_KEY). With neither, generation is off and the
 * app says so; uploads and the private library keep working.
 *
 * Secrets (both optional, see optionalSecrets.ts):
 *   MODEL3D_VAULT_KEY  32 random bytes, base64 (`openssl rand -base64 32`);
 *                      needed before sellers can link their own account
 *   MESHY_API_KEY      Oneova's own engine key (built-in generation)
 */
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { decryptWith, encryptWith } from '../gmailUser';
import { optionalSecret } from '../optionalSecrets';

export type EngineId = 'meshy';
export const ENGINES: Record<EngineId, { label: string; keyHint: string }> = {
  meshy: { label: 'Meshy', keyHint: 'msy_…' },
};

export interface Engine { id: EngineId; key: string; owner: 'user' | 'oneova' }

const db = () => getFirestore();
const keysRef = (uid: string) => db().collection('model3d_keys').doc(uid);
const statusRef = (uid: string, engine: EngineId) => db().doc(`users/${uid}/model_providers/${engine}`);

async function vaultKey(): Promise<Buffer> {
  const k = await optionalSecret('MODEL3D_VAULT_KEY');
  const buf = k ? Buffer.from(k, 'base64') : Buffer.alloc(0);
  if (buf.length !== 32) throw new HttpsError('failed-precondition', 'Linking your own 3D provider is not switched on yet.');
  return buf;
}

async function meshy(key: string, method: 'GET' | 'POST', path: string, body?: unknown): Promise<any> {
  const res = await fetch(`https://api.meshy.ai${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(30_000),
  });
  const text = await res.text();
  let json: any = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
  if (!res.ok) {
    const err = new Error(String(json?.message ?? `The 3D engine answered ${res.status}.`)) as Error & { status?: number };
    err.status = res.status;
    throw err;
  }
  return json;
}

/** Saves a seller's own provider key after checking it works. */
export async function linkProvider(uid: string, engine: EngineId, apiKey: string): Promise<void> {
  const key = apiKey.trim();
  if (key.length < 12 || key.length > 200 || /\s/.test(key)) throw new HttpsError('invalid-argument', 'That key doesn’t look right.');
  const vault = await vaultKey();
  try {
    await meshy(key, 'GET', '/openapi/v1/image-to-3d?page_size=1');
  } catch (e: any) {
    if (e?.status === 401 || e?.status === 403) throw new HttpsError('permission-denied', `${ENGINES[engine].label} did not accept this key.`);
    throw new HttpsError('unavailable', `${ENGINES[engine].label} can’t be reached right now. Try again in a minute.`);
  }
  await keysRef(uid).set({ [engine]: encryptWith(vault, key, uid), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await statusRef(uid, engine).set({
    engine, label: ENGINES[engine].label, linked: true, keyEnd: key.slice(-4), linkedAt: FieldValue.serverTimestamp(),
  });
}

export async function unlinkProvider(uid: string, engine: EngineId): Promise<void> {
  await keysRef(uid).set({ [engine]: FieldValue.delete() }, { merge: true });
  await statusRef(uid, engine).delete();
}

/** The seller's own engine if linked, else Oneova's, else null (generation off). */
export async function engineFor(uid: string): Promise<Engine | null> {
  const blob = (await keysRef(uid).get()).get('meshy') as string | undefined;
  if (blob) {
    try {
      return { id: 'meshy', key: decryptWith(await vaultKey(), blob, uid), owner: 'user' };
    } catch {
      /* unreadable key: fall through to the built-in engine */
    }
  }
  const platform = await optionalSecret('MESHY_API_KEY');
  return platform ? { id: 'meshy', key: platform, owner: 'oneova' } : null;
}

/** The same engine a job started with (jobs outlive one function call). */
export async function engineOf(uid: string, owner: 'user' | 'oneova'): Promise<Engine | null> {
  const e = await engineFor(uid);
  if (e && e.owner === owner) return e;
  if (owner === 'oneova') {
    const platform = await optionalSecret('MESHY_API_KEY');
    return platform ? { id: 'meshy', key: platform, owner: 'oneova' } : null;
  }
  return null;
}

export interface EngineTask { taskId: string; multi: boolean }

/**
 * Starts a generation. One photo uses image-to-3D; two to four (front first)
 * use multi-image, which is what keeps the sides and the texture true.
 */
export async function submitGeneration(engine: Engine, imageUrls: string[]): Promise<EngineTask> {
  const common = { should_texture: true, enable_pbr: true, should_remesh: true, topology: 'triangle', target_polycount: 100_000, target_formats: ['glb'] };
  if (imageUrls.length > 1) {
    const r = await meshy(engine.key, 'POST', '/openapi/v1/multi-image-to-3d', { ...common, image_urls: imageUrls.slice(0, 4) });
    return { taskId: String(r.result), multi: true };
  }
  const r = await meshy(engine.key, 'POST', '/openapi/v1/image-to-3d', { ...common, image_url: imageUrls[0] });
  return { taskId: String(r.result), multi: false };
}

export interface EngineStatus {
  state: 'working' | 'done' | 'failed';
  /** 0..1 */
  progress: number;
  glbUrl?: string;
  thumbnailUrl?: string;
  error?: string;
}

export async function pollGeneration(engine: Engine, task: EngineTask): Promise<EngineStatus> {
  const t = await meshy(engine.key, 'GET', `/openapi/v1/${task.multi ? 'multi-image-to-3d' : 'image-to-3d'}/${encodeURIComponent(task.taskId)}`);
  const progress = Math.min(1, Math.max(0, Number(t?.progress ?? 0) / 100));
  switch (String(t?.status)) {
    case 'SUCCEEDED': {
      const glbUrl = t?.model_urls?.glb;
      if (typeof glbUrl !== 'string' || !glbUrl.startsWith('https://')) return { state: 'failed', progress, error: 'The engine finished without a model.' };
      return { state: 'done', progress: 1, glbUrl, thumbnailUrl: typeof t.thumbnail_url === 'string' ? t.thumbnail_url : undefined };
    }
    case 'FAILED':
    case 'CANCELED':
      return { state: 'failed', progress, error: String(t?.task_error?.message || 'The engine could not build this model.').slice(0, 200) };
    default:
      return { state: 'working', progress };
  }
}
