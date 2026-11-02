/**
 * In-chat AI assist (translate, summarize, smart replies) on Gemini through
 * Vertex AI, as the function's service account. The app only calls this for a
 * single message the user chose to translate, or for a chat where the user
 * turned AI on. Chats can be end-to-end encrypted, so the app sends the
 * decrypted text it wants help with; nothing is read from or written to
 * Firestore here, and message text is never logged.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { Modality } from '@google/genai';
import { generateVertexContent, vertexAi } from './vertexAi';
import { limit } from './guard/protect';

const MODEL = 'gemini-2.5-flash';
const TTS_MODEL = process.env.GEMINI_TTS_MODEL || 'gemini-2.5-flash-preview-tts';
const MAX_TEXT = 4000;
const MAX_LINES = 60;
const MAX_BATCH = 25;
const MAX_AUDIO_B64 = 6_000_000;
const MAX_VOICE_SAMPLE_BYTES = 1_800_000;
const PREBUILT_VOICES = new Set(['Puck', 'Charon', 'Fenrir', 'Aoede', 'Kore', 'Zephyr']);

function normalizeAudioMime(v: unknown): string {
  const raw = typeof v === 'string' ? v.trim().toLowerCase().split(';')[0] : '';
  switch (raw) {
    case 'audio/m4a':
    case 'audio/x-m4a':
    case 'audio/mp4':
      return 'audio/mp4';
    case 'audio/mp3':
    case 'audio/mpeg':
      return 'audio/mpeg';
    case 'audio/x-wav':
    case 'audio/wav':
      return 'audio/wav';
    case 'audio/aac':
    case 'audio/ogg':
    case 'audio/webm':
      return raw;
    default:
      return 'audio/mp4';
  }
}

function pcm16MonoToWavBase64(pcm: Buffer, sampleRate = 24000): string {
  const channels = 1;
  const bitsPerSample = 16;
  const byteRate = (sampleRate * channels * bitsPerSample) >> 3;
  const blockAlign = (channels * bitsPerSample) >> 3;
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16); // PCM fmt chunk size
  header.writeUInt16LE(1, 20); // Linear PCM
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]).toString('base64');
}

async function loadEnrolledVoiceSampleBase64(senderUid: string): Promise<string | null> {
  if (!/^[A-Za-z0-9_-]{4,128}$/.test(senderUid)) return null;
  try {
    const snap = await getFirestore().collection('users').doc(senderUid).get();
    if (snap.data()?.aiVoicePersonalization?.enabled !== true) return null;
    const file = getStorage().bucket().file(`voice_samples/${senderUid}.m4a`);
    const [meta] = await file.getMetadata();
    const size = Number(meta?.size ?? 0);
    if (!size || size > MAX_VOICE_SAMPLE_BYTES) return null;
    const [bytes] = await file.download();
    return bytes.toString('base64');
  } catch {
    return null;
  }
}

type Line = { me?: boolean; name?: string; text?: string };

function cleanText(v: unknown, max = MAX_TEXT): string {
  return typeof v === 'string' ? v.slice(0, max).trim() : '';
}

function cleanLang(v: unknown): string {
  const s = typeof v === 'string' ? v.trim() : '';
  return /^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})?$/.test(s) ? s : 'en';
}

function transcript(lines: unknown): string {
  if (!Array.isArray(lines)) return '';
  return (lines as Line[])
    .slice(-MAX_LINES)
    .map((l) => {
      const text = cleanText(l?.text, 800);
      if (!text) return '';
      const who = l?.me ? 'Me' : (cleanText(l?.name, 40) || 'Them');
      return `${who}: ${text}`;
    })
    .filter(Boolean)
    .join('\n');
}

async function generateJson(system: string, user: string, maxTokens: number): Promise<any> {
  const res = await generateVertexContent({
    model: MODEL,
    contents: [{ role: 'user', parts: [{ text: user }] }],
    config: {
      systemInstruction: system,
      responseMimeType: 'application/json',
      temperature: 0.4,
      maxOutputTokens: maxTokens,
      thinkingConfig: { thinkingBudget: 0 },
    },
  });
  const raw = res.text ?? '';
  try {
    return JSON.parse(raw);
  } catch {
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) throw new Error('bad_json');
    return JSON.parse(m[0]);
  }
}

export const chatAssist = onCall({ timeoutSeconds: 60, memory: '512MiB' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to use AI in chat.');
  await limit(request.auth.uid, 'chat_assist', 120, 10 * 60000);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const op = data.op;
  const target = cleanLang(data.target);

  try {
    switch (op) {
      case 'translateVoice': {
        const audioBase64 = typeof data.audioBase64 === 'string' ? data.audioBase64.trim() : '';
        if (!audioBase64 || audioBase64.length > MAX_AUDIO_B64) {
          throw new HttpsError('invalid-argument', 'Voice note is empty or exceeds the maximum supported size.');
        }
        const mimeType = normalizeAudioMime(data.mimeType);
        const senderUid = typeof data.senderUid === 'string' ? data.senderUid.trim() : '';
        const enrolledSampleB64 = senderUid ? await loadEnrolledVoiceSampleBase64(senderUid) : null;

        const parts: Array<{ text: string } | { inlineData: { mimeType: string; data: string } }> = [];
        if (enrolledSampleB64) {
          parts.push({
            text: 'Reference sample of the speaker enrolled voice (use ONLY to match vocal timbre, pitch, and pace):',
          });
          parts.push({ inlineData: { mimeType: 'audio/mp4', data: enrolledSampleB64 } });
        }
        parts.push({
          text:
            `Primary voice note to transcribe and translate into language "${target}":`,
        });
        parts.push({ inlineData: { mimeType, data: audioBase64 } });

        const analysisRes = await generateVertexContent({
          model: MODEL,
          contents: [{ role: 'user', parts }],
          config: {
            systemInstruction:
              'You transcribe, translate, and acoustically profile chat voice notes. Reply ONLY with valid JSON: ' +
              '{"transcript":"exact transcript in spoken language","translated":"natural translation in target language",' +
              '"source":"<BCP-47 spoken language code>","same":true|false,' +
              '"voiceProfile":{"prebuiltVoice":"Puck|Charon|Fenrir|Aoede|Kore|Zephyr","pitch":1.0,"rate":1.0,' +
              '"style":"concise 4-8 word vocal delivery cue matching speaker timbre, warmth, and energy"}}. ' +
              `Target language is "${target}". Preserve speaker emotion, names, slang, and intent. ` +
              'Choose prebuiltVoice closest to the speaker voice: Fenrir (deep male), Charon (warm baritone male), ' +
              'Puck (bright mid male), Aoede (warm expressive female), Kore (clear mid female), Zephyr (soft bright female). ' +
              'Set pitch in [0.85, 1.18] and rate in [0.85, 1.15]. If spoken language already matches target base language, ' +
              'set "same": true and repeat transcript in "translated".',
            responseMimeType: 'application/json',
            temperature: 0.25,
            maxOutputTokens: 1500,
            thinkingConfig: { thinkingBudget: 0 },
          },
        });

        const rawJson = analysisRes.text ?? '{}';
        let parsed: any = {};
        try {
          parsed = JSON.parse(rawJson);
        } catch {
          const m = rawJson.match(/\{[\s\S]*\}/);
          if (m) parsed = JSON.parse(m[0]);
        }

        const transcriptText = cleanText(parsed?.transcript, 3000);
        const translatedText = cleanText(parsed?.translated, 3000) || transcriptText;
        const sourceLang = typeof parsed?.source === 'string' ? parsed.source.slice(0, 16) : '';
        const targetBase = target.split(/[-_]/)[0].toLowerCase();
        const sourceBase = sourceLang.split(/[-_]/)[0].toLowerCase();
        const same = parsed?.same === true || (Boolean(sourceBase) && sourceBase === targetBase) || !translatedText;

        const vp = parsed?.voiceProfile ?? {};
        const voiceName = PREBUILT_VOICES.has(vp?.prebuiltVoice) ? String(vp.prebuiltVoice) : 'Aoede';
        const pitch = Math.min(1.18, Math.max(0.85, Number(vp?.pitch) || 1.0));
        const rate = Math.min(1.15, Math.max(0.85, Number(vp?.rate) || 1.0));
        const style = cleanText(vp?.style, 80) || 'natural conversational tone';

        let synthBase64 = '';
        let synthMime = '';
        if (translatedText && !same) {
          try {
            const ttsRes = await vertexAi().models.generateContent({
              model: TTS_MODEL,
              contents: [
                {
                  role: 'user',
                  parts: [
                    {
                      text: `Speak naturally in language "${target}" with ${style}. Say only this text:\n${translatedText}`,
                    },
                  ],
                },
              ],
              config: {
                responseModalities: [Modality.AUDIO],
                speechConfig: {
                  voiceConfig: {
                    prebuiltVoiceConfig: { voiceName },
                  },
                },
              },
            });
            const inline = ttsRes.candidates?.[0]?.content?.parts?.find((p: any) => p?.inlineData?.data)?.inlineData;
            if (inline?.data) {
              const outMime = String(inline.mimeType ?? '').toLowerCase();
              if (!outMime || outMime.includes('l16') || outMime.includes('pcm')) {
                const rateMatch = outMime.match(/rate=(\d+)/);
                const sr = rateMatch ? Math.max(8000, Math.min(48000, Number(rateMatch[1]))) : 24000;
                synthBase64 = pcm16MonoToWavBase64(Buffer.from(inline.data, 'base64'), sr);
                synthMime = 'audio/wav';
              } else {
                synthBase64 = inline.data;
                synthMime = outMime.split(';')[0];
              }
            }
          } catch (ttsErr: any) {
            console.warn('chatAssist translateVoice TTS fallback to client:', ttsErr?.message ?? ttsErr);
          }
        }

        return {
          transcript: transcriptText,
          translated: translatedText,
          source: sourceLang,
          same,
          voiceName,
          pitch,
          rate,
          ...(synthBase64 ? { audioBase64: synthBase64, audioMimeType: synthMime } : {}),
        };
      }
      case 'translate': {
        const texts = (Array.isArray(data.texts) ? data.texts : [data.text])
          .slice(0, MAX_BATCH)
          .map((t) => cleanText(t));
        if (texts.every((t) => !t)) throw new HttpsError('invalid-argument', 'Nothing to translate.');
        const out = await generateJson(
          'You translate chat messages. Reply ONLY with JSON: ' +
            '{"items":[{"translated":"...","source":"<BCP-47 code>","same":true|false}]}, one item per input, in order. ' +
            `Translate each message into language "${target}". Keep tone, emoji, names and links. ` +
            'If a message is already in that language, set "same": true and repeat it unchanged.',
          JSON.stringify({ messages: texts }),
          Math.min(8192, 200 + texts.join('').length * 3),
        );
        const items = Array.isArray(out?.items) ? out.items : [];
        return {
          items: texts.map((t, i) => ({
            translated: typeof items[i]?.translated === 'string' ? items[i].translated : t,
            source: typeof items[i]?.source === 'string' ? items[i].source : '',
            same: items[i]?.same === true || !t,
          })),
        };
      }
      case 'summarize': {
        const convo = transcript(data.lines);
        if (!convo) throw new HttpsError('invalid-argument', 'Nothing to summarize.');
        const out = await generateJson(
          'You summarize a chat for one of its members ("Me"). Reply ONLY with JSON: ' +
            '{"summary":"2-4 sentence overview","points":["key point", "..."],"todos":["open question or thing Me should do", "..."]}. ' +
            `Write in language "${target}". At most 5 points and 4 todos. Be factual; do not invent details.`,
          `Conversation (oldest first):\n${convo}`,
          700,
        );
        return {
          summary: typeof out?.summary === 'string' ? out.summary : '',
          points: Array.isArray(out?.points) ? out.points.filter((p: unknown) => typeof p === 'string').slice(0, 5) : [],
          todos: Array.isArray(out?.todos) ? out.todos.filter((p: unknown) => typeof p === 'string').slice(0, 4) : [],
        };
      }
      case 'replies': {
        const convo = transcript(data.lines);
        if (!convo) return { replies: [] };
        const out = await generateJson(
          'You suggest quick replies for "Me" in a chat app. Reply ONLY with JSON: {"replies":["...","...","..."]}. ' +
            'Three short replies (max 10 words each), natural, in the language of the last message, ' +
            'ranging from casual to more formal. Use emoji only if the chat does. Never agree to send money or share passwords.',
          `Conversation (oldest first):\n${convo}`,
          200,
        );
        const replies = Array.isArray(out?.replies) ? out.replies : [];
        return {
          replies: replies
            .filter((r: unknown) => typeof r === 'string' && r.trim())
            .map((r: string) => r.trim().slice(0, 120))
            .slice(0, 3),
        };
      }
      default:
        throw new HttpsError('invalid-argument', 'Unknown chat assist operation.');
    }
  } catch (e: any) {
    if (e instanceof HttpsError) throw e;
    console.error('chatAssist failed', op, e?.message ?? e);
    throw new HttpsError('internal', 'Oneova AI could not help with that right now.');
  }
});
