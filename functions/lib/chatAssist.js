"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.chatAssist = void 0;
/**
 * In-chat AI assist (translate, summarize, smart replies) on Gemini through
 * Vertex AI, as the function's service account. The app only calls this for a
 * single message the user chose to translate, or for a chat where the user
 * turned AI on. Chats can be end-to-end encrypted, so the app sends the
 * decrypted text it wants help with; nothing is read from or written to
 * Firestore here, and message text is never logged.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const genai_1 = require("@google/genai");
const vertexAi_1 = require("./vertexAi");
const protect_1 = require("./guard/protect");
const MODEL = 'gemini-2.5-flash';
const TTS_MODEL = process.env.GEMINI_TTS_MODEL || 'gemini-2.5-flash-preview-tts';
const MAX_TEXT = 4000;
const MAX_LINES = 60;
const MAX_BATCH = 25;
const MAX_AUDIO_B64 = 6000000;
const MAX_VOICE_SAMPLE_BYTES = 1800000;
const PREBUILT_VOICES = new Set(['Puck', 'Charon', 'Fenrir', 'Aoede', 'Kore', 'Zephyr']);
function normalizeAudioMime(v) {
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
function pcm16MonoToWavBase64(pcm, sampleRate = 24000) {
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
async function loadEnrolledVoiceSampleBase64(senderUid) {
    var _a, _b;
    var _c;
    if (!/^[A-Za-z0-9_-]{4,128}$/.test(senderUid))
        return null;
    try {
        const snap = await (0, firestore_1.getFirestore)().collection('users').doc(senderUid).get();
        if (((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.aiVoicePersonalization) === null || _b === void 0 ? void 0 : _b.enabled) !== true)
            return null;
        const file = (0, storage_1.getStorage)().bucket().file(`voice_samples/${senderUid}.m4a`);
        const [meta] = await file.getMetadata();
        const size = Number((_c = meta === null || meta === void 0 ? void 0 : meta.size) !== null && _c !== void 0 ? _c : 0);
        if (!size || size > MAX_VOICE_SAMPLE_BYTES)
            return null;
        const [bytes] = await file.download();
        return bytes.toString('base64');
    }
    catch (_d) {
        return null;
    }
}
function cleanText(v, max = MAX_TEXT) {
    return typeof v === 'string' ? v.slice(0, max).trim() : '';
}
function cleanLang(v) {
    const s = typeof v === 'string' ? v.trim() : '';
    return /^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})?$/.test(s) ? s : 'en';
}
function transcript(lines) {
    if (!Array.isArray(lines))
        return '';
    return lines
        .slice(-MAX_LINES)
        .map((l) => {
        const text = cleanText(l === null || l === void 0 ? void 0 : l.text, 800);
        if (!text)
            return '';
        const who = (l === null || l === void 0 ? void 0 : l.me) ? 'Me' : (cleanText(l === null || l === void 0 ? void 0 : l.name, 40) || 'Them');
        return `${who}: ${text}`;
    })
        .filter(Boolean)
        .join('\n');
}
async function generateJson(system, user, maxTokens) {
    var _a;
    const res = await (0, vertexAi_1.generateVertexContent)({
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
    const raw = (_a = res.text) !== null && _a !== void 0 ? _a : '';
    try {
        return JSON.parse(raw);
    }
    catch (_b) {
        const m = raw.match(/\{[\s\S]*\}/);
        if (!m)
            throw new Error('bad_json');
        return JSON.parse(m[0]);
    }
}
exports.chatAssist = (0, https_1.onCall)({ timeoutSeconds: 60, memory: '512MiB' }, async (request) => {
    var _a, _b, _c, _d, _e;
    var _f, _g, _h, _j, _k, _l;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to use AI in chat.');
    await (0, protect_1.limit)(request.auth.uid, 'chat_assist', 120, 10 * 60000);
    const data = ((_f = request.data) !== null && _f !== void 0 ? _f : {});
    const op = data.op;
    const target = cleanLang(data.target);
    try {
        switch (op) {
            case 'translateVoice': {
                const audioBase64 = typeof data.audioBase64 === 'string' ? data.audioBase64.trim() : '';
                if (!audioBase64 || audioBase64.length > MAX_AUDIO_B64) {
                    throw new https_1.HttpsError('invalid-argument', 'Voice note is empty or exceeds the maximum supported size.');
                }
                const mimeType = normalizeAudioMime(data.mimeType);
                const senderUid = typeof data.senderUid === 'string' ? data.senderUid.trim() : '';
                const enrolledSampleB64 = senderUid ? await loadEnrolledVoiceSampleBase64(senderUid) : null;
                const parts = [];
                if (enrolledSampleB64) {
                    parts.push({
                        text: 'Reference sample of the speaker enrolled voice (use ONLY to match vocal timbre, pitch, and pace):',
                    });
                    parts.push({ inlineData: { mimeType: 'audio/mp4', data: enrolledSampleB64 } });
                }
                parts.push({
                    text: `Primary voice note to transcribe and translate into language "${target}":`,
                });
                parts.push({ inlineData: { mimeType, data: audioBase64 } });
                const analysisRes = await (0, vertexAi_1.generateVertexContent)({
                    model: MODEL,
                    contents: [{ role: 'user', parts }],
                    config: {
                        systemInstruction: 'You transcribe, translate, and acoustically profile chat voice notes. Reply ONLY with valid JSON: ' +
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
                const rawJson = (_g = analysisRes.text) !== null && _g !== void 0 ? _g : '{}';
                let parsed = {};
                try {
                    parsed = JSON.parse(rawJson);
                }
                catch (_m) {
                    const m = rawJson.match(/\{[\s\S]*\}/);
                    if (m)
                        parsed = JSON.parse(m[0]);
                }
                const transcriptText = cleanText(parsed === null || parsed === void 0 ? void 0 : parsed.transcript, 3000);
                const translatedText = cleanText(parsed === null || parsed === void 0 ? void 0 : parsed.translated, 3000) || transcriptText;
                const sourceLang = typeof (parsed === null || parsed === void 0 ? void 0 : parsed.source) === 'string' ? parsed.source.slice(0, 16) : '';
                const targetBase = target.split(/[-_]/)[0].toLowerCase();
                const sourceBase = sourceLang.split(/[-_]/)[0].toLowerCase();
                const same = (parsed === null || parsed === void 0 ? void 0 : parsed.same) === true || (Boolean(sourceBase) && sourceBase === targetBase) || !translatedText;
                const vp = (_h = parsed === null || parsed === void 0 ? void 0 : parsed.voiceProfile) !== null && _h !== void 0 ? _h : {};
                const voiceName = PREBUILT_VOICES.has(vp === null || vp === void 0 ? void 0 : vp.prebuiltVoice) ? String(vp.prebuiltVoice) : 'Aoede';
                const pitch = Math.min(1.18, Math.max(0.85, Number(vp === null || vp === void 0 ? void 0 : vp.pitch) || 1.0));
                const rate = Math.min(1.15, Math.max(0.85, Number(vp === null || vp === void 0 ? void 0 : vp.rate) || 1.0));
                const style = cleanText(vp === null || vp === void 0 ? void 0 : vp.style, 80) || 'natural conversational tone';
                let synthBase64 = '';
                let synthMime = '';
                if (translatedText && !same) {
                    try {
                        const ttsRes = await (0, vertexAi_1.vertexAi)().models.generateContent({
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
                                responseModalities: [genai_1.Modality.AUDIO],
                                speechConfig: {
                                    voiceConfig: {
                                        prebuiltVoiceConfig: { voiceName },
                                    },
                                },
                            },
                        });
                        const inline = (_e = (_d = (_c = (_b = (_a = ttsRes.candidates) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d.find((p) => { var _a; return (_a = p === null || p === void 0 ? void 0 : p.inlineData) === null || _a === void 0 ? void 0 : _a.data; })) === null || _e === void 0 ? void 0 : _e.inlineData;
                        if (inline === null || inline === void 0 ? void 0 : inline.data) {
                            const outMime = String((_j = inline.mimeType) !== null && _j !== void 0 ? _j : '').toLowerCase();
                            if (!outMime || outMime.includes('l16') || outMime.includes('pcm')) {
                                const rateMatch = outMime.match(/rate=(\d+)/);
                                const sr = rateMatch ? Math.max(8000, Math.min(48000, Number(rateMatch[1]))) : 24000;
                                synthBase64 = pcm16MonoToWavBase64(Buffer.from(inline.data, 'base64'), sr);
                                synthMime = 'audio/wav';
                            }
                            else {
                                synthBase64 = inline.data;
                                synthMime = outMime.split(';')[0];
                            }
                        }
                    }
                    catch (ttsErr) {
                        console.warn('chatAssist translateVoice TTS fallback to client:', (_k = ttsErr === null || ttsErr === void 0 ? void 0 : ttsErr.message) !== null && _k !== void 0 ? _k : ttsErr);
                    }
                }
                return Object.assign({ transcript: transcriptText, translated: translatedText, source: sourceLang, same,
                    voiceName,
                    pitch,
                    rate }, (synthBase64 ? { audioBase64: synthBase64, audioMimeType: synthMime } : {}));
            }
            case 'translate': {
                const texts = (Array.isArray(data.texts) ? data.texts : [data.text])
                    .slice(0, MAX_BATCH)
                    .map((t) => cleanText(t));
                if (texts.every((t) => !t))
                    throw new https_1.HttpsError('invalid-argument', 'Nothing to translate.');
                const out = await generateJson('You translate chat messages. Reply ONLY with JSON: ' +
                    '{"items":[{"translated":"...","source":"<BCP-47 code>","same":true|false}]}, one item per input, in order. ' +
                    `Translate each message into language "${target}". Keep tone, emoji, names and links. ` +
                    'If a message is already in that language, set "same": true and repeat it unchanged.', JSON.stringify({ messages: texts }), Math.min(8192, 200 + texts.join('').length * 3));
                const items = Array.isArray(out === null || out === void 0 ? void 0 : out.items) ? out.items : [];
                return {
                    items: texts.map((t, i) => { var _a, _b, _c; return ({
                        translated: typeof ((_a = items[i]) === null || _a === void 0 ? void 0 : _a.translated) === 'string' ? items[i].translated : t,
                        source: typeof ((_b = items[i]) === null || _b === void 0 ? void 0 : _b.source) === 'string' ? items[i].source : '',
                        same: ((_c = items[i]) === null || _c === void 0 ? void 0 : _c.same) === true || !t,
                    }); }),
                };
            }
            case 'summarize': {
                const convo = transcript(data.lines);
                if (!convo)
                    throw new https_1.HttpsError('invalid-argument', 'Nothing to summarize.');
                const out = await generateJson('You summarize a chat for one of its members ("Me"). Reply ONLY with JSON: ' +
                    '{"summary":"2-4 sentence overview","points":["key point", "..."],"todos":["open question or thing Me should do", "..."]}. ' +
                    `Write in language "${target}". At most 5 points and 4 todos. Be factual; do not invent details.`, `Conversation (oldest first):\n${convo}`, 700);
                return {
                    summary: typeof (out === null || out === void 0 ? void 0 : out.summary) === 'string' ? out.summary : '',
                    points: Array.isArray(out === null || out === void 0 ? void 0 : out.points) ? out.points.filter((p) => typeof p === 'string').slice(0, 5) : [],
                    todos: Array.isArray(out === null || out === void 0 ? void 0 : out.todos) ? out.todos.filter((p) => typeof p === 'string').slice(0, 4) : [],
                };
            }
            case 'replies': {
                const convo = transcript(data.lines);
                if (!convo)
                    return { replies: [] };
                const out = await generateJson('You suggest quick replies for "Me" in a chat app. Reply ONLY with JSON: {"replies":["...","...","..."]}. ' +
                    'Three short replies (max 10 words each), natural, in the language of the last message, ' +
                    'ranging from casual to more formal. Use emoji only if the chat does. Never agree to send money or share passwords.', `Conversation (oldest first):\n${convo}`, 200);
                const replies = Array.isArray(out === null || out === void 0 ? void 0 : out.replies) ? out.replies : [];
                return {
                    replies: replies
                        .filter((r) => typeof r === 'string' && r.trim())
                        .map((r) => r.trim().slice(0, 120))
                        .slice(0, 3),
                };
            }
            default:
                throw new https_1.HttpsError('invalid-argument', 'Unknown chat assist operation.');
        }
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        console.error('chatAssist failed', op, (_l = e === null || e === void 0 ? void 0 : e.message) !== null && _l !== void 0 ? _l : e);
        throw new https_1.HttpsError('internal', 'Oneova AI could not help with that right now.');
    }
});
//# sourceMappingURL=chatAssist.js.map