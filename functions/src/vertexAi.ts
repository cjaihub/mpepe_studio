/**
 * Gemini through Vertex AI, authenticated as the function's own service
 * account (no API key to store or leak). Needs the Vertex AI API
 * (aiplatform.googleapis.com) enabled and roles/aiplatform.user on the
 * runtime service account; tools/play/backend_setup.sh does both.
 */
import { GoogleGenAI, GenerateContentParameters, GenerateContentResponse } from '@google/genai';

const LOCATION = process.env.VERTEX_LOCATION || 'us-central1';

export const GEMINI_FLASH_MODELS: readonly string[] = [
  process.env.GEMINI_MODEL || 'gemini-1.5-flash',
  'gemini-2.0-flash',
  'gemini-2.5-flash',
];

let client: GoogleGenAI | null = null;

export function vertexAi(): GoogleGenAI {
  client ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
    location: LOCATION,
  });
  return client;
}

/**
 * Calls `ai.models.generateContent` across [GEMINI_FLASH_MODELS] so a retired
 * model ID (HTTP 404 NOT_FOUND) automatically upgrades to `gemini-3.8-flash`.
 */
export async function generateVertexContent(
  params: Omit<GenerateContentParameters, 'model'> & { model?: string },
): Promise<GenerateContentResponse> {
  const ai = vertexAi();
  const candidates = params.model
    ? Array.from(new Set([params.model, ...GEMINI_FLASH_MODELS]))
    : Array.from(new Set(GEMINI_FLASH_MODELS));

  let lastErr: unknown;
  for (const model of candidates) {
    try {
      return await ai.models.generateContent({ ...params, model });
    } catch (err: any) {
      lastErr = err;
      const jsonStr = (() => {
        try {
          return JSON.stringify(err);
        } catch {
          return '';
        }
      })();
      const msg = `${err?.message ?? ''} ${jsonStr}`.toLowerCase();
      const isNotFound =
        err?.status === 404 ||
        err?.code === 404 ||
        err?.status === 'NOT_FOUND' ||
        err?.error?.code === 404 ||
        err?.error?.status === 'NOT_FOUND' ||
        msg.includes('404') ||
        msg.includes('not_found') ||
        msg.includes('not found') ||
        msg.includes('no longer available') ||
        msg.includes('does not have access');
      if (!isNotFound) throw err;
    }
  }
  throw lastErr;
}
