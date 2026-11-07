/**
 * Studio AI: auto captions and translation for the video editor.
 *
 *   studioCaptions({ audio, mimeType?, language?, offsetMs?, durationMs? })
 *     → { language, languageName, support, segments: [{ startMs, endMs, text, confidence, words: [{ w, s, e }] }] }
 *   studioTranslate({ texts: string[], target, source? })
 *     → { target, support, translations: string[] }
 *
 * Any world language, including local and regional ones. `support` is the
 * model's own honest rating ('good' | 'limited' | 'unsupported') so the app
 * can say when a language isn't handled well instead of showing wrong text.
 *
 * `audio` is base64 mono speech audio the app renders from the timeline
 * (trims and speed already applied), so returned times are on the output
 * timeline. Speech recognition and translation run on Gemini through Vertex
 * AI as the function's service account (vertexAi.ts); translation falls back
 * to OpenRouter (OPENROUTER_API_KEY secret) when Vertex is unavailable. No AI
 * key ever reaches the app.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { Type } from '@google/genai';
import { generateVertexContent } from './vertexAi';

const openRouterSecret = defineSecret('OPENROUTER_API_KEY');

/** Base64 of ~6 MB audio (≈ 25 min of 16 kHz mono AAC). */
const MAX_AUDIO_B64 = 8_500_000;
const MAX_TRANSLATE_ITEMS = 400;
const MAX_TRANSLATE_CHARS = 24_000;
const DAILY_CAPTION_CALLS = 60;
const DAILY_TRANSLATE_CALLS = 120;

/** Server-only usage counter (no client rules on this collection). */
async function underDailyCap(uid: string, kind: string, limit: number): Promise<boolean> {
  const day = new Date().toISOString().substring(0, 10).replace(/-/g, '');
  const ref = getFirestore().collection('studio_ai_usage').doc(`${uid}_${kind}_${day}`);
  return getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = (snap.get('count') as number | undefined) ?? 0;
    if (count >= limit) return false;
    tx.set(ref, { uid, kind, day, count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

const CAPTION_PROMPT = (language: string) => `You are a professional subtitler for creators worldwide. Transcribe the speech in this audio.
Rules:
- ${language === 'auto' ? 'Detect the spoken language yourself. It can be any world language, including local and regional ones (for example Kikuyu, Luo, Luganda, Kinyarwanda, Twi, Wolof, Tigrinya, Quechua), and speakers may code-switch between languages.' : `The speech is expected to be in "${language}" (it may be mixed with other languages).`} Transcribe in the language actually spoken, in its usual writing system; never translate.
- Be honest about quality. Set "support" to "good" when you transcribe this language reliably, "limited" when you can follow it but spelling or words may be off, and "unsupported" when you cannot transcribe it reliably. If "unsupported", return an empty segments list instead of guessing or substituting another language.
- Give each segment a "confidence" from 0 to 1.
- Write exactly what is said, with natural punctuation and casing. Skip music, noises and silence. Do not invent words.
- Split into caption segments of at most 7 words or 42 characters, breaking at natural pauses.
- For every word give its start and end time in seconds from the beginning of the audio, as precisely as you can hear it.
- Segment start = first word start, segment end = last word end. Times must increase.
- If there is no speech, return an empty segments list.
- "language" is the BCP-47 / ISO 639 code of the main spoken language (e.g. en, sw, ki, luo, lg, rw, am, yo, ha, zu, pt-BR, ar, hi, zh) and "languageName" its English name.`;

const CAPTION_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    language: { type: Type.STRING },
    languageName: { type: Type.STRING },
    support: { type: Type.STRING, enum: ['good', 'limited', 'unsupported'] },
    segments: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          start: { type: Type.NUMBER },
          end: { type: Type.NUMBER },
          text: { type: Type.STRING },
          confidence: { type: Type.NUMBER },
          words: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: { word: { type: Type.STRING }, start: { type: Type.NUMBER }, end: { type: Type.NUMBER } },
              required: ['word', 'start', 'end'],
            },
          },
        },
        required: ['start', 'end', 'text', 'words'],
      },
    },
  },
  required: ['language', 'languageName', 'support', 'segments'],
};

interface RawWord { word?: unknown; start?: unknown; end?: unknown }
interface RawSegment { start?: unknown; end?: unknown; text?: unknown; confidence?: unknown; words?: RawWord[] }

function num(v: unknown): number {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Cleans model output: clamps to the audio, keeps times increasing. */
function normalizeSegments(raw: RawSegment[], durationMs: number, offsetMs: number) {
  const limit = durationMs > 0 ? durationMs : Number.MAX_SAFE_INTEGER;
  const out: { startMs: number; endMs: number; text: string; confidence: number; words: { w: string; s: number; e: number }[] }[] = [];
  let cursor = 0;
  for (const seg of raw ?? []) {
    const text = String(seg?.text ?? '').trim();
    if (!text) continue;
    const words: { w: string; s: number; e: number }[] = [];
    for (const w of seg.words ?? []) {
      const word = String(w?.word ?? '').trim();
      if (!word) continue;
      let s = Math.round(num(w.start) * 1000);
      let e = Math.round(num(w.end) * 1000);
      s = Math.min(Math.max(s, cursor), limit);
      e = Math.min(Math.max(e, s + 60), limit);
      words.push({ w: word, s, e });
      cursor = s;
    }
    let startMs = Math.round(num(seg.start) * 1000);
    let endMs = Math.round(num(seg.end) * 1000);
    if (words.length) {
      startMs = words[0].s;
      endMs = Math.max(endMs, words[words.length - 1].e);
    }
    startMs = Math.min(Math.max(startMs, out.length ? out[out.length - 1].startMs : 0), limit);
    endMs = Math.min(Math.max(endMs, startMs + 300), limit);
    if (endMs <= startMs) continue;
    out.push({
      startMs: startMs + offsetMs,
      endMs: endMs + offsetMs,
      text,
      confidence: seg.confidence === undefined ? 1 : Math.min(1, Math.max(0, num(seg.confidence))),
      words: words.map((w) => ({ w: w.w, s: w.s + offsetMs, e: w.e + offsetMs })),
    });
  }
  // No overlaps: a caption ends when the next one starts.
  for (let i = 0; i < out.length - 1; i++) {
    if (out[i].endMs > out[i + 1].startMs) out[i].endMs = Math.max(out[i].startMs + 200, out[i + 1].startMs);
  }
  return out;
}

export const studioCaptions = onCall({ memory: '512MiB', timeoutSeconds: 300 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to use auto captions.');
  const data = (request.data ?? {}) as Record<string, unknown>;
  const audio = String(data.audio ?? '');
  const mimeType = String(data.mimeType ?? 'audio/mp4');
  const language = String(data.language ?? 'auto').trim() || 'auto';
  const offsetMs = Math.max(0, Math.round(num(data.offsetMs)));
  const durationMs = Math.max(0, Math.round(num(data.durationMs)));
  if (!audio) throw new HttpsError('invalid-argument', 'No audio was sent.');
  if (audio.length > MAX_AUDIO_B64) throw new HttpsError('invalid-argument', 'That audio is too long for one request.');
  if (!/^audio\//.test(mimeType)) throw new HttpsError('invalid-argument', 'Unsupported audio type.');
  if (!(await underDailyCap(request.auth.uid, 'captions', DAILY_CAPTION_CALLS))) {
    throw new HttpsError('resource-exhausted', 'You reached today\'s auto-caption limit. Try again tomorrow.');
  }
  try {
    const res = await generateVertexContent({
      model: 'gemini-2.5-flash',
      contents: [{ role: 'user', parts: [{ inlineData: { mimeType, data: audio } }, { text: CAPTION_PROMPT(language) }] }],
      config: {
        temperature: 0,
        responseMimeType: 'application/json',
        responseSchema: CAPTION_SCHEMA,
        maxOutputTokens: 32768,
      },
    });
    const parsed = JSON.parse(res.text ?? '{}') as { language?: string; languageName?: string; support?: string; segments?: RawSegment[] };
    const support = ['good', 'limited', 'unsupported'].includes(String(parsed.support)) ? String(parsed.support) : 'limited';
    const segments = support === 'unsupported' ? [] : normalizeSegments(parsed.segments ?? [], durationMs, offsetMs);
    return {
      language: String(parsed.language ?? (language === 'auto' ? 'und' : language)),
      languageName: String(parsed.languageName ?? ''),
      support,
      segments,
    };
  } catch (e) {
    logger.error('[studioCaptions] failed', { error: String(e) });
    throw new HttpsError('unavailable', 'Auto captions are not available right now. Try again in a moment.');
  }
});

const TRANSLATE_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    support: { type: Type.STRING, enum: ['good', 'limited', 'unsupported'] },
    translations: { type: Type.ARRAY, items: { type: Type.STRING } },
  },
  required: ['support', 'translations'],
};

function translatePrompt(texts: string[], target: string, source?: string): string {
  return `Translate each item of this JSON array ${source ? `from "${source}" ` : ''}into the language "${target}" (a language code or name; it may be a local or regional language).
Rules: rate yourself honestly in "support": "good" if you write this language fluently, "limited" if your translation may contain mistakes, "unsupported" if you cannot write it (then return the items unchanged). Use the language's usual writing system. Keep the meaning, tone and slang level of short-video captions; keep emojis, @handles, #tags, numbers and URLs; keep line breaks; never merge, split, drop or reorder items; output exactly ${texts.length} translations in order as {"support": "...", "translations": [...]}.
Items:
${JSON.stringify(texts)}`;
}

async function translateWithOpenRouter(texts: string[], target: string, source?: string): Promise<{ support: string; translations: string[] }> {
  const key = openRouterSecret.value();
  if (!key) throw new Error('OpenRouter key missing');
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'X-Title': 'Oneova Studio' },
    body: JSON.stringify({
      model: 'google/gemini-2.5-flash',
      temperature: 0.1,
      response_format: { type: 'json_object' },
      messages: [{ role: 'user', content: translatePrompt(texts, target, source) }],
    }),
  });
  if (!res.ok) throw new Error(`OpenRouter ${res.status}`);
  const body = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const content = body.choices?.[0]?.message?.content ?? '{}';
  const parsed = JSON.parse(content.replace(/^```(json)?|```$/g, '').trim()) as { support?: string; translations?: string[] };
  return { support: parsed.support ?? 'limited', translations: parsed.translations ?? [] };
}

export const studioTranslate = onCall({ memory: '256MiB', timeoutSeconds: 120, secrets: [openRouterSecret] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to translate.');
  const data = (request.data ?? {}) as Record<string, unknown>;
  const texts = Array.isArray(data.texts) ? (data.texts as unknown[]).map((t) => String(t ?? '')) : [];
  const target = String(data.target ?? '').trim();
  const source = data.source ? String(data.source).trim() : undefined;
  if (!texts.length) return { target, translations: [] };
  // A code (sw, luo, pt-BR) or a language name typed by the user ("Kikuyu").
  if (!/^[\p{L}][\p{L}\p{M} ()'-]{1,40}$/u.test(target) && !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(target)) {
    throw new HttpsError('invalid-argument', 'Pick a language to translate into.');
  }
  if (texts.length > MAX_TRANSLATE_ITEMS || texts.join('').length > MAX_TRANSLATE_CHARS) {
    throw new HttpsError('invalid-argument', 'Too much text to translate at once.');
  }
  if (!(await underDailyCap(request.auth.uid, 'translate', DAILY_TRANSLATE_CALLS))) {
    throw new HttpsError('resource-exhausted', 'You reached today\'s translation limit. Try again tomorrow.');
  }
  let translations: string[] = [];
  let support = 'limited';
  try {
    const res = await generateVertexContent({
      model: 'gemini-2.5-flash',
      contents: [{ role: 'user', parts: [{ text: translatePrompt(texts, target, source) }] }],
      config: { temperature: 0.1, responseMimeType: 'application/json', responseSchema: TRANSLATE_SCHEMA, maxOutputTokens: 16384 },
    });
    const parsed = JSON.parse(res.text ?? '{}') as { support?: string; translations?: string[] };
    translations = parsed.translations ?? [];
    support = parsed.support ?? 'limited';
  } catch (e) {
    logger.warn('[studioTranslate] Vertex failed, trying OpenRouter', { error: String(e) });
    try {
      ({ translations, support } = await translateWithOpenRouter(texts, target, source));
    } catch (e2) {
      logger.error('[studioTranslate] failed', { error: String(e2) });
      throw new HttpsError('unavailable', 'Translation is not available right now. Try again in a moment.');
    }
  }
  if (translations.length !== texts.length) {
    throw new HttpsError('internal', 'The translation came back incomplete. Try again.');
  }
  if (!['good', 'limited', 'unsupported'].includes(support)) support = 'limited';
  if (support === 'unsupported') return { target, support, translations: texts };
  return { target, support, translations: translations.map((t, i) => String(t ?? texts[i])) };
});
