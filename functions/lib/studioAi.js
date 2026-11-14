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
exports.studioTranslate = exports.studioCaptions = exports.openRouterSecret = void 0;
exports.translateWithOpenRouter = translateWithOpenRouter;
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
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const genai_1 = require("@google/genai");
const vertexAi_1 = require("./vertexAi");
exports.openRouterSecret = (0, params_1.defineSecret)('OPENROUTER_API_KEY');
/** Base64 of ~6 MB audio (≈ 25 min of 16 kHz mono AAC). */
const MAX_AUDIO_B64 = 8500000;
const MAX_TRANSLATE_ITEMS = 400;
const MAX_TRANSLATE_CHARS = 24000;
const DAILY_CAPTION_CALLS = 60;
const DAILY_TRANSLATE_CALLS = 120;
/** Server-only usage counter (no client rules on this collection). */
async function underDailyCap(uid, kind, limit) {
    const day = new Date().toISOString().substring(0, 10).replace(/-/g, '');
    const ref = (0, firestore_1.getFirestore)().collection('studio_ai_usage').doc(`${uid}_${kind}_${day}`);
    return (0, firestore_1.getFirestore)().runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(ref);
        const count = (_a = snap.get('count')) !== null && _a !== void 0 ? _a : 0;
        if (count >= limit)
            return false;
        tx.set(ref, { uid, kind, day, count: firestore_1.FieldValue.increment(1), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    });
}
const CAPTION_PROMPT = (language) => `You are a professional subtitler for creators worldwide. Transcribe the speech in this audio.
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
    type: genai_1.Type.OBJECT,
    properties: {
        language: { type: genai_1.Type.STRING },
        languageName: { type: genai_1.Type.STRING },
        support: { type: genai_1.Type.STRING, enum: ['good', 'limited', 'unsupported'] },
        segments: {
            type: genai_1.Type.ARRAY,
            items: {
                type: genai_1.Type.OBJECT,
                properties: {
                    start: { type: genai_1.Type.NUMBER },
                    end: { type: genai_1.Type.NUMBER },
                    text: { type: genai_1.Type.STRING },
                    confidence: { type: genai_1.Type.NUMBER },
                    words: {
                        type: genai_1.Type.ARRAY,
                        items: {
                            type: genai_1.Type.OBJECT,
                            properties: { word: { type: genai_1.Type.STRING }, start: { type: genai_1.Type.NUMBER }, end: { type: genai_1.Type.NUMBER } },
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
function num(v) {
    const n = typeof v === 'number' ? v : Number(v);
    return Number.isFinite(n) ? n : 0;
}
/** Cleans model output: clamps to the audio, keeps times increasing. */
function normalizeSegments(raw, durationMs, offsetMs) {
    var _a, _b, _c;
    const limit = durationMs > 0 ? durationMs : Number.MAX_SAFE_INTEGER;
    const out = [];
    let cursor = 0;
    for (const seg of raw !== null && raw !== void 0 ? raw : []) {
        const text = String((_a = seg === null || seg === void 0 ? void 0 : seg.text) !== null && _a !== void 0 ? _a : '').trim();
        if (!text)
            continue;
        const words = [];
        for (const w of (_b = seg.words) !== null && _b !== void 0 ? _b : []) {
            const word = String((_c = w === null || w === void 0 ? void 0 : w.word) !== null && _c !== void 0 ? _c : '').trim();
            if (!word)
                continue;
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
        if (endMs <= startMs)
            continue;
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
        if (out[i].endMs > out[i + 1].startMs)
            out[i].endMs = Math.max(out[i].startMs + 200, out[i + 1].startMs);
    }
    return out;
}
exports.studioCaptions = (0, https_1.onCall)({ memory: '512MiB', timeoutSeconds: 300 }, async (request) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to use auto captions.');
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const audio = String((_b = data.audio) !== null && _b !== void 0 ? _b : '');
    const mimeType = String((_c = data.mimeType) !== null && _c !== void 0 ? _c : 'audio/mp4');
    const language = String((_d = data.language) !== null && _d !== void 0 ? _d : 'auto').trim() || 'auto';
    const offsetMs = Math.max(0, Math.round(num(data.offsetMs)));
    const durationMs = Math.max(0, Math.round(num(data.durationMs)));
    if (!audio)
        throw new https_1.HttpsError('invalid-argument', 'No audio was sent.');
    if (audio.length > MAX_AUDIO_B64)
        throw new https_1.HttpsError('invalid-argument', 'That audio is too long for one request.');
    if (!/^audio\//.test(mimeType))
        throw new https_1.HttpsError('invalid-argument', 'Unsupported audio type.');
    if (!(await underDailyCap(request.auth.uid, 'captions', DAILY_CAPTION_CALLS))) {
        throw new https_1.HttpsError('resource-exhausted', 'You reached today\'s auto-caption limit. Try again tomorrow.');
    }
    try {
        const res = await (0, vertexAi_1.generateVertexContent)({
            model: 'gemini-2.5-flash',
            contents: [{ role: 'user', parts: [{ inlineData: { mimeType, data: audio } }, { text: CAPTION_PROMPT(language) }] }],
            config: {
                temperature: 0,
                responseMimeType: 'application/json',
                responseSchema: CAPTION_SCHEMA,
                maxOutputTokens: 32768,
            },
        });
        const parsed = JSON.parse((_e = res.text) !== null && _e !== void 0 ? _e : '{}');
        const support = ['good', 'limited', 'unsupported'].includes(String(parsed.support)) ? String(parsed.support) : 'limited';
        const segments = support === 'unsupported' ? [] : normalizeSegments((_f = parsed.segments) !== null && _f !== void 0 ? _f : [], durationMs, offsetMs);
        return {
            language: String((_g = parsed.language) !== null && _g !== void 0 ? _g : (language === 'auto' ? 'und' : language)),
            languageName: String((_h = parsed.languageName) !== null && _h !== void 0 ? _h : ''),
            support,
            segments,
        };
    }
    catch (e) {
        logger.error('[studioCaptions] failed', { error: String(e) });
        throw new https_1.HttpsError('unavailable', 'Auto captions are not available right now. Try again in a moment.');
    }
});
const TRANSLATE_SCHEMA = {
    type: genai_1.Type.OBJECT,
    properties: {
        support: { type: genai_1.Type.STRING, enum: ['good', 'limited', 'unsupported'] },
        translations: { type: genai_1.Type.ARRAY, items: { type: genai_1.Type.STRING } },
    },
    required: ['support', 'translations'],
};
function translatePrompt(texts, target, source, detectSource = false) {
    return `${detectSource ? 'First detect the original language of the items and put its BCP-47 / ISO 639 code (e.g. en, sw, yo, ha, ig, zu, am, so, ar, fr, pt) in "source". Then t' : 'T'}ranslate each item of this JSON array ${source ? `from "${source}" ` : ''}into the language "${target}" (a language code or name; it may be a local or regional language).
Rules: rate yourself honestly in "support": "good" if you write this language fluently, "limited" if your translation may contain mistakes, "unsupported" if you cannot write it (then return the items unchanged). Use the language's usual writing system. Keep the meaning, tone and slang level of short-video captions; keep emojis, @handles, #tags, numbers and URLs; keep line breaks; never merge, split, drop or reorder items; output exactly ${texts.length} translations in order as {${detectSource ? '"source": "...", ' : ''}"support": "...", "translations": [...]}.
Items:
${JSON.stringify(texts)}`;
}
/** Also used by reelTranslate (reelTranslate.ts); `detectSource` asks for the original language too. */
async function translateWithOpenRouter(texts, target, source, detectSource = false) {
    var _a, _b, _c;
    var _d, _e, _f;
    const key = exports.openRouterSecret.value();
    if (!key)
        throw new Error('OpenRouter key missing');
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'X-Title': 'Oneova Studio' },
        body: JSON.stringify({
            model: 'google/gemini-2.5-flash',
            temperature: 0.1,
            response_format: { type: 'json_object' },
            messages: [{ role: 'user', content: translatePrompt(texts, target, source, detectSource) }],
        }),
    });
    if (!res.ok)
        throw new Error(`OpenRouter ${res.status}`);
    const body = (await res.json());
    const content = (_d = (_c = (_b = (_a = body.choices) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.message) === null || _c === void 0 ? void 0 : _c.content) !== null && _d !== void 0 ? _d : '{}';
    const parsed = JSON.parse(content.replace(/^```(json)?|```$/g, '').trim());
    return Object.assign({ support: (_e = parsed.support) !== null && _e !== void 0 ? _e : 'limited', translations: (_f = parsed.translations) !== null && _f !== void 0 ? _f : [] }, (typeof parsed.source === 'string' ? { source: parsed.source } : {}));
}
exports.studioTranslate = (0, https_1.onCall)({ memory: '512MiB', timeoutSeconds: 120, secrets: [exports.openRouterSecret] }, async (request) => {
    var _a, _b, _c, _d, _e;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to translate.');
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const texts = Array.isArray(data.texts) ? data.texts.map((t) => String(t !== null && t !== void 0 ? t : '')) : [];
    const target = String((_b = data.target) !== null && _b !== void 0 ? _b : '').trim();
    const source = data.source ? String(data.source).trim() : undefined;
    if (!texts.length)
        return { target, translations: [] };
    // A code (sw, luo, pt-BR) or a language name typed by the user ("Kikuyu").
    if (!/^[\p{L}][\p{L}\p{M} ()'-]{1,40}$/u.test(target) && !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(target)) {
        throw new https_1.HttpsError('invalid-argument', 'Pick a language to translate into.');
    }
    if (texts.length > MAX_TRANSLATE_ITEMS || texts.join('').length > MAX_TRANSLATE_CHARS) {
        throw new https_1.HttpsError('invalid-argument', 'Too much text to translate at once.');
    }
    if (!(await underDailyCap(request.auth.uid, 'translate', DAILY_TRANSLATE_CALLS))) {
        throw new https_1.HttpsError('resource-exhausted', 'You reached today\'s translation limit. Try again tomorrow.');
    }
    let translations = [];
    let support = 'limited';
    try {
        const res = await (0, vertexAi_1.generateVertexContent)({
            model: 'gemini-2.5-flash',
            contents: [{ role: 'user', parts: [{ text: translatePrompt(texts, target, source) }] }],
            config: { temperature: 0.1, responseMimeType: 'application/json', responseSchema: TRANSLATE_SCHEMA, maxOutputTokens: 16384 },
        });
        const parsed = JSON.parse((_c = res.text) !== null && _c !== void 0 ? _c : '{}');
        translations = (_d = parsed.translations) !== null && _d !== void 0 ? _d : [];
        support = (_e = parsed.support) !== null && _e !== void 0 ? _e : 'limited';
    }
    catch (e) {
        logger.warn('[studioTranslate] Vertex failed, trying OpenRouter', { error: String(e) });
        try {
            ({ translations, support } = await translateWithOpenRouter(texts, target, source));
        }
        catch (e2) {
            logger.error('[studioTranslate] failed', { error: String(e2) });
            throw new https_1.HttpsError('unavailable', 'Translation is not available right now. Try again in a moment.');
        }
    }
    if (translations.length !== texts.length) {
        throw new https_1.HttpsError('internal', 'The translation came back incomplete. Try again.');
    }
    if (!['good', 'limited', 'unsupported'].includes(support))
        support = 'limited';
    if (support === 'unsupported')
        return { target, support, translations: texts };
    return { target, support, translations: translations.map((t, i) => String(t !== null && t !== void 0 ? t : texts[i])) };
});
//# sourceMappingURL=studioAi.js.map