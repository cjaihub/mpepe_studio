/**
 * Secrets that are read at run time instead of being bound to a function.
 *
 * A secret bound with `secrets: [defineSecret(...)]` must exist before
 * `firebase deploy` will run at all, so one missing optional secret blocks
 * every deploy in the codebase. Features that can simply switch themselves off
 * (Oneova's security-email sender, per-user Gmail) read their secrets here and
 * get `null` when the secret is missing or not readable.
 *
 * Access: the functions' runtime service account needs Secret Accessor on
 * each secret, once:
 *   gcloud secrets add-iam-policy-binding NAME --project mpepe-2b4bd \
 *     --member serviceAccount:90836164478-compute@developer.gserviceaccount.com \
 *     --role roles/secretmanager.secretAccessor
 */
import { google } from 'googleapis';
import * as logger from 'firebase-functions/logger';

const cache = new Map<string, { value: string | null; at: number }>();
const TTL_MS = 10 * 60 * 1000;

function projectId(): string {
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  try {
    return JSON.parse(process.env.FIREBASE_CONFIG ?? '{}').projectId ?? '';
  } catch {
    return '';
  }
}

/** Latest value of secret [name], or null when it's missing, "unset" or unreadable. */
export async function optionalSecret(name: string): Promise<string | null> {
  const hit = cache.get(name);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.value;
  let value: string | null = null;
  try {
    const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
    const sm = google.secretmanager({ version: 'v1', auth });
    const res = await sm.projects.secrets.versions.access({ name: `projects/${projectId()}/secrets/${name}/versions/latest` });
    const data = res.data.payload?.data;
    const text = data ? Buffer.from(data, 'base64').toString('utf8').trim() : '';
    value = text && text.toLowerCase() !== 'unset' ? text : null;
  } catch (e) {
    const code = (e as { code?: number }).code;
    logger.warn(`[optionalSecret] ${name} not available (${code ?? e}); the feature that needs it is off.`);
  }
  cache.set(name, { value, at: Date.now() });
  return value;
}
