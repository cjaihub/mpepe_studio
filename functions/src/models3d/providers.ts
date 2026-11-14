/**
 * Photo → 3D engine: Oneova's own GPU model server only.
 *
 * Oneova does not use third-party 3D services (Meshy-style SaaS) and sellers
 * don't link outside accounts. Generation runs on open-source models (TRELLIS,
 * TripoSR; MIT) that Oneova hosts on Cloud Run GPU in its own project — see
 * packages/three_d_model_server on the AI 3D branch. Until that server is
 * deployed, generation is off: photos are kept and the model starts with
 * "Build now" once it is on. Uploads and the private library keep working.
 *
 * Configuration (either one; neither means "off"):
 *   env MODEL3D_SERVER_URL or optional secret MODEL3D_SERVER_URL
 *     https://ova3d-model-trellis-….run.app
 * The server must allow only the functions' service account to invoke it
 * (Cloud Run IAM) and set OVA3D_ALLOWED_BUCKET to the app's bucket.
 */
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { GoogleAuth } from 'google-auth-library';
import { optionalSecret } from '../optionalSecrets';
import { buildEngineRequest, engineErrorMessage, readEngineResult, validEngineUrl } from './engineLogic';

export type EngineId = 'oneova';
export const ENGINE_LABEL = 'Oneova 3D builder';

export interface Engine { id: EngineId; url: string; owner: 'oneova' }

/** Thrown with a message that is safe to show to the seller. */
export class EngineError extends Error {}

/** Oneova's own engine when it is configured, else null (generation off). */
export async function engineFor(_uid?: string): Promise<Engine | null> {
  const raw = process.env.MODEL3D_SERVER_URL || (await optionalSecret('MODEL3D_SERVER_URL'));
  const url = validEngineUrl(raw);
  return url ? { id: 'oneova', url, owner: 'oneova' } : null;
}

const auth = new GoogleAuth();

/**
 * Runs image → 3D on the GPU server and waits for it (the model server
 * answers when the GLB is written). Returns the storage path of the GLB.
 */
export async function runGeneration(engine: Engine, bucket: string, photoPaths: string[], outputPrefix: string, timeoutMs: number): Promise<string> {
  const body = buildEngineRequest(bucket, photoPaths, outputPrefix);
  let data: unknown;
  try {
    // Cloud Run IAM: an ID token for the service URL, minted for the functions' service account.
    const client = await auth.getIdTokenClient(engine.url);
    const res = await client.request({ url: `${engine.url}/v1/tasks`, method: 'POST', data: body, timeout: timeoutMs });
    data = res.data;
  } catch (e: any) {
    const status = Number(e?.response?.status ?? e?.status) || undefined;
    throw new EngineError(engineErrorMessage(status));
  }
  try {
    return readEngineResult(data, outputPrefix);
  } catch (e: any) {
    throw new EngineError(String(e?.message ?? 'The 3D builder finished without a model.'));
  }
}

// ── Old seller-linked provider keys (removed) ───────────────────────────

/** Linking outside 3D accounts is no longer offered. */
export async function linkProvider(): Promise<never> {
  throw new HttpsError('failed-precondition', 'Oneova builds 3D models on its own servers, so there is nothing to link.');
}

/** Removes any key a seller linked in an earlier version (kept so they can clear it). */
export async function unlinkProvider(uid: string): Promise<void> {
  const db = getFirestore();
  await db.collection('model3d_keys').doc(uid).delete();
  const links = await db.collection(`users/${uid}/model_providers`).get();
  await Promise.all(links.docs.map((d) => d.ref.delete()));
}
