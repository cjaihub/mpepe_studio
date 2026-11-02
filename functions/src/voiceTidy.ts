/**
 * Voice typing clean-up for Ova and any Oneova text field.
 *
 *   voiceTidy({ text, style? })  →  { text }
 *
 * Adds punctuation and capitals, drops filler words ("um", "like", repeated
 * starts) and fixes obvious speech-to-text slips, without changing meaning,
 * tone or language. The app keeps the raw words so the user can undo.
 * Runs on Vertex AI as the function's service account (vertexAi.ts).
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { generateVertexContent } from './vertexAi';

const MAX_CHARS = 2000;

const SYSTEM = `You clean up dictated text. Rules:
- Keep the speaker's words, meaning, tone and language. Never add new content or answer questions in it.
- Add punctuation and capitalisation. Split run-on sentences.
- Remove filler words and false starts (um, uh, like, you know, repeated words).
- Fix obvious speech-to-text mistakes only when the intended word is clear.
- Keep names, numbers, emojis, @handles, #tags and URLs exactly.
- Output only the cleaned text, nothing else.`;

export const voiceTidy = onCall({ memory: '256MiB', timeoutSeconds: 20 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const text = String((request.data as Record<string, unknown>)?.text ?? '').trim();
  if (!text) return { text: '' };
  if (text.length > MAX_CHARS) throw new HttpsError('invalid-argument', 'That dictation is too long to clean up.');
  // Very short dictations rarely need more than a capital letter.
  if (text.split(/\s+/).length < 3) return { text: text.charAt(0).toUpperCase() + text.slice(1) };
  try {
    const res = await generateVertexContent({
      contents: [{ role: 'user', parts: [{ text }] }],
      config: { systemInstruction: SYSTEM, temperature: 0.1, maxOutputTokens: 1024 },
    });
    const out = (res.text ?? '').trim();
    // Guard against a model that answers instead of cleaning: lengths must stay close.
    if (!out || out.length > text.length * 1.4 + 20 || out.length < text.length * 0.4) return { text };
    return { text: out };
  } catch (e) {
    logger.warn('[voiceTidy] failed', { error: String(e) });
    return { text };
  }
});
