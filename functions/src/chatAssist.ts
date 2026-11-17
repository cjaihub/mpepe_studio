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
import { ownVoicePcm } from './voice/voice';

const MODEL = 'gemini-2.5-flash';
const FAST_MODEL = 'gemini-2.5-flash-lite';
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

async function generateJson(
  system: string,
  user: string,
  maxTokens: number,
  model: string = MODEL,
): Promise<any> {
  const res = await generateVertexContent({
    model,
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

export const chatAssist = onCall({ timeoutSeconds: 180, memory: '512MiB' }, async (request) => {
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
        let presetPcm: { pcm: Buffer; sr: number } | null = null;
        let ownVoice = false;
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
                presetPcm = { pcm: Buffer.from(inline.data, 'base64'), sr };
                synthBase64 = pcm16MonoToWavBase64(presetPcm.pcm, sr);
                synthMime = 'audio/wav';
              } else {
                synthBase64 = inline.data;
                synthMime = outMime.split(';')[0];
              }
            }
          } catch (ttsErr: any) {
            console.warn('chatAssist translateVoice TTS fallback to client:', ttsErr?.message ?? ttsErr);
          }
          // My own note: say it in MY OWN voice (never someone else's).
          if (senderUid && senderUid === request.auth.uid) {
            const own = await ownVoicePcm(senderUid, translatedText, target, presetPcm);
            if (own && own.length > 0) {
              synthBase64 = pcm16MonoToWavBase64(own, 24000);
              synthMime = 'audio/wav';
              ownVoice = true;
            }
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
          ownVoice,
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
      case 'speakText': {
        const text = cleanText(data.text, 2400);
        if (!text) throw new HttpsError('invalid-argument', 'Nothing to speak.');
        const requestedVoice = typeof data.voiceName === 'string' ? data.voiceName.trim() : 'Aoede';
        const voiceName = PREBUILT_VOICES.has(requestedVoice) ? requestedVoice : 'Aoede';
        const style = cleanText(data.style, 80) || 'warm natural conversational human voice';
        const useOwnVoice = data.useOwnVoice === true;

        let synthBase64 = '';
        let synthMime = 'audio/wav';
        let presetPcm: { pcm: Buffer; sr: number } | null = null;
        let ownVoice = false;

        try {
          const ttsRes = await vertexAi().models.generateContent({
            model: TTS_MODEL,
            contents: [
              {
                role: 'user',
                parts: [
                  {
                    text: `Speak naturally in language "${target}" with ${style}. Say only this text cleanly with human inflection:\n${text}`,
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
              presetPcm = { pcm: Buffer.from(inline.data, 'base64'), sr };
              synthBase64 = pcm16MonoToWavBase64(presetPcm.pcm, sr);
              synthMime = 'audio/wav';
            } else {
              synthBase64 = inline.data;
              synthMime = outMime.split(';')[0];
            }
          }
        } catch (ttsErr: any) {
          console.warn('chatAssist speakText error:', ttsErr?.message ?? ttsErr);
        }

        if (useOwnVoice && request.auth.uid) {
          const own = await ownVoicePcm(request.auth.uid, text, target, presetPcm);
          if (own && own.length > 0) {
            synthBase64 = pcm16MonoToWavBase64(own, 24000);
            synthMime = 'audio/wav';
            ownVoice = true;
          }
        }

        if (!synthBase64) {
          throw new HttpsError('unavailable', 'Vertex voice audio could not be generated right now.');
        }

        return {
          audioBase64: synthBase64,
          audioMimeType: synthMime,
          voiceName,
          ownVoice,
        };
      }
      case 'translateScreenBlocks': {
        const rawBlocks = Array.isArray(data.blocks) ? data.blocks.slice(0, 60) : [];
        const blocks = rawBlocks
          .map((b: any, i: number) => ({
            id: typeof b?.id === 'string' && b.id ? b.id : String(i),
            text: cleanText(b?.text, 1000),
          }))
          .filter((b: { id: string; text: string }) => b.text.length > 0);
        if (blocks.length === 0) {
          return { target, translations: [] };
        }
        const out = await generateJson(
          'You perform ultra-fast on-screen UI translation so translated pills fit cleanly over the original text boxes. ' +
            'Reply ONLY with valid JSON: {"translations":[{"id":"...","translated":"...","source":"<BCP-47>","same":true|false}]}. ' +
            `Translate each block naturally into "${target}". Keep proper nouns, handles (@name), numbers, prices, and short UI labels concise so they fit the box. ` +
            'If a block is already in that language or is purely numeric/symbolic, set "same": true and repeat it unchanged.',
          JSON.stringify({ target, blocks }),
          Math.min(8192, 240 + blocks.map((b: { text: string }) => b.text.length).reduce((a: number, b: number) => a + b, 0) * 3),
          FAST_MODEL,
        );
        const list = Array.isArray(out?.translations) ? out.translations : [];
        return {
          target,
          translations: blocks.map((b: { id: string; text: string }, i: number) => {
            const match = list.find((item: any) => item?.id === b.id) ?? list[i];
            return {
              id: b.id,
              translated: typeof match?.translated === 'string' && match.translated.trim() ? match.translated : b.text,
              source: typeof match?.source === 'string' ? match.source : '',
              same: match?.same === true,
            };
          }),
        };
      }
      case 'highlightAnalyze': {
        const imageBase64 = typeof data.imageBase64 === 'string' ? data.imageBase64.trim() : '';
        const selectedText = cleanText(data.selectedText, 2400);
        const surroundingText = cleanText(data.surroundingText, 2400);
        const question = cleanText(data.question, 600);
        const mode = typeof data.mode === 'string' ? data.mode.trim() : 'explain';
        if (!imageBase64 && !selectedText && !question) {
          throw new HttpsError('invalid-argument', 'Highlight a part of the screen first.');
        }

        const parts: Array<{ text: string } | { inlineData: { mimeType: string; data: string } }> = [];
        if (imageBase64 && imageBase64.length < MAX_AUDIO_B64) {
          parts.push({ inlineData: { mimeType: 'image/jpeg', data: imageBase64 } });
        }
        parts.push({
          text: JSON.stringify({
            mode,
            targetLanguage: target,
            selectedText,
            surroundingText,
            question,
          }),
        });

        const sys =
          'You are Ova on Oneova, answering about a highlighted region on the user phone screen without leaving their app. ' +
          'Speak like a warm, helpful friend in plain everyday words (2-4 short sentences). ' +
          'Reply ONLY with JSON: {"title":"2-5 word heading","answer":"clear human answer","translated":"if mode=translate or foreign text detected, translation in targetLanguage else empty","extractedText":"clean recognized text in selection","suggestedActions":["Copy","Translate","Ask more"]}. ' +
          `Translate or reply in "${target}".`;

        const res = await generateVertexContent({
          model: imageBase64 ? MODEL : FAST_MODEL,
          contents: [{ role: 'user', parts }],
          config: {
            systemInstruction: sys,
            responseMimeType: 'application/json',
            temperature: 0.3,
            maxOutputTokens: 900,
            thinkingConfig: { thinkingBudget: 0 },
          },
        });
        const raw = res.text ?? '{}';
        let parsed: any = {};
        try {
          parsed = JSON.parse(raw);
        } catch {
          const m = raw.match(/\{[\s\S]*\}/);
          if (m) parsed = JSON.parse(m[0]);
        }
        return {
          title: cleanText(parsed?.title, 80) || 'Ova Screen Insight',
          answer: cleanText(parsed?.answer, 2000) || selectedText || 'Highlighted region analyzed.',
          translated: cleanText(parsed?.translated, 2000),
          extractedText: cleanText(parsed?.extractedText, 2000) || selectedText,
          suggestedActions: Array.isArray(parsed?.suggestedActions)
            ? parsed.suggestedActions.filter((a: unknown) => typeof a === 'string').slice(0, 4)
            : ['Translate', 'Copy', 'Ask Ova'],
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
