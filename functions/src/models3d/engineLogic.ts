/**
 * Pure parts of the photo → 3D engine call (no Firebase, unit-tested).
 *
 * The engine is Oneova's own GPU model server (packages/three_d_model_server
 * on the AI 3D branch: TRELLIS or TripoSR, MIT licensed, on Cloud Run GPU in
 * Oneova's own project). No third-party 3D SaaS is called.
 *
 * Wire contract (same as the model server):
 *   POST {url}/v1/tasks {"task": "image_to_3d", "inputs": [gs://...],
 *                        "output_uri": gs://..., "params": {...}}
 *   → {"outputs": {"glb": "model.glb"}, "gpu_seconds": n, "metrics": {...}}
 */

export interface EngineTaskRequest {
  task: 'image_to_3d';
  inputs: string[];
  output_uri: string;
  params: Record<string, number | string>;
}

/** Only an https Cloud Run URL in Oneova's project (no plain http, no credentials, no query). */
export function validEngineUrl(raw: string | null | undefined): string | null {
  const s = String(raw ?? '').trim().replace(/\/+$/, '');
  if (!s) return null;
  let u: URL;
  try {
    u = new URL(s);
  } catch {
    return null;
  }
  if (u.protocol !== 'https:' || u.username || u.password || u.search || u.hash) return null;
  const host = u.hostname.toLowerCase();
  return host.endsWith('.run.app') ? s : null;
}

/** Builds the model-server request for one to four photos (front first). */
export function buildEngineRequest(bucket: string, photoPaths: string[], outputPrefix: string): EngineTaskRequest {
  if (!/^[a-z0-9][a-z0-9._-]{1,220}$/.test(bucket)) throw new Error('bad bucket');
  if (photoPaths.length < 1 || photoPaths.length > 4) throw new Error('one to four photos');
  for (const p of [...photoPaths, outputPrefix]) {
    if (!/^users\/[A-Za-z0-9_-]+\/models3d\/[A-Za-z0-9_-]+\//.test(p) || p.includes('..')) throw new Error('bad path');
  }
  return {
    task: 'image_to_3d',
    inputs: photoPaths.map((p) => `gs://${bucket}/${p}`),
    output_uri: `gs://${bucket}/${outputPrefix.replace(/\/+$/, '')}`,
    // 2048 px textures keep the real print of the product; the optimizer makes phone copies.
    params: { seed: 1, texture_size: 2048 },
  };
}

/**
 * Reads the server's answer. Returns the storage path of the GLB it wrote, or
 * throws with a plain message the seller can act on.
 */
export function readEngineResult(body: unknown, outputPrefix: string): string {
  const outputs = (body as { outputs?: Record<string, unknown> } | null)?.outputs;
  const name = outputs?.glb;
  if (typeof name !== 'string' || !/^[A-Za-z0-9_.-]{1,80}\.glb$/.test(name)) {
    throw new Error('The 3D builder finished without a model. Try clearer photos.');
  }
  return `${outputPrefix.replace(/\/+$/, '')}/${name}`;
}

/** A plain message for an engine HTTP failure. */
export function engineErrorMessage(status: number | undefined): string {
  if (status === 400 || status === 422) return 'The 3D builder could not read these photos. Try clearer photos on a plain background.';
  if (status === 401 || status === 403) return 'The 3D builder is not set up correctly yet. We’re on it; try again later.';
  if (status === 429 || status === 503) return 'The 3D builder is busy. Your photos are saved; try again in a few minutes.';
  if (status === 504 || status === undefined) return 'The 3D builder took too long. Try again; fewer photos are faster.';
  return 'The 3D builder could not build this model. Try again.';
}

/** Progress shown while the GPU works (it gives no live progress of its own). */
export function estimatedProgress(elapsedMs: number, expectedMs = 150_000): { progress: number; stage: string } {
  const t = Math.max(0, elapsedMs) / expectedMs;
  // Eases toward 0.68 without ever reaching it; the optimizer takes over from 0.72.
  const progress = 0.1 + 0.58 * (1 - Math.exp(-2.2 * t));
  const stage = t < 0.3 ? 'Building the shape from your photos'
    : t < 0.7 ? 'Refining edges and details'
    : t < 1.2 ? 'Painting the texture from your photos'
    : 'Finishing the model';
  return { progress: Math.round(progress * 1000) / 1000, stage };
}
