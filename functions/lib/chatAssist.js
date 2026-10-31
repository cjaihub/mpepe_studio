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
const vertexAi_1 = require("./vertexAi");
const protect_1 = require("./guard/protect");
const MODEL = 'gemini-2.5-flash';
const MAX_TEXT = 4000;
const MAX_LINES = 60;
const MAX_BATCH = 25;
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
    const res = await (0, vertexAi_1.vertexAi)().models.generateContent({
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
exports.chatAssist = (0, https_1.onCall)({ timeoutSeconds: 60, memory: '256MiB' }, async (request) => {
    var _a, _b;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to use AI in chat.');
    await (0, protect_1.limit)(request.auth.uid, 'chat_assist', 120, 10 * 60000);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const op = data.op;
    const target = cleanLang(data.target);
    try {
        switch (op) {
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
        console.error('chatAssist failed', op, (_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : e);
        throw new https_1.HttpsError('internal', 'Oneova AI could not help with that right now.');
    }
});
//# sourceMappingURL=chatAssist.js.map