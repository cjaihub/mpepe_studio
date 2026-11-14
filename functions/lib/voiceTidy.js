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
exports.voiceTidy = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const vertexAi_1 = require("./vertexAi");
const MAX_CHARS = 2000;
const SYSTEM = `You clean up dictated text. Rules:
- Keep the speaker's words, meaning, tone and language. Never add new content or answer questions in it.
- Add punctuation and capitalisation. Split run-on sentences.
- Remove filler words and false starts (um, uh, like, you know, repeated words).
- Fix obvious speech-to-text mistakes only when the intended word is clear.
- Keep names, numbers, emojis, @handles, #tags and URLs exactly.
- Output only the cleaned text, nothing else.`;
exports.voiceTidy = (0, https_1.onCall)({ memory: '512MiB', timeoutSeconds: 20 }, async (request) => {
    var _a;
    var _b, _c;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const text = String((_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.text) !== null && _b !== void 0 ? _b : '').trim();
    if (!text)
        return { text: '' };
    if (text.length > MAX_CHARS)
        throw new https_1.HttpsError('invalid-argument', 'That dictation is too long to clean up.');
    // Very short dictations rarely need more than a capital letter.
    if (text.split(/\s+/).length < 3)
        return { text: text.charAt(0).toUpperCase() + text.slice(1) };
    try {
        const res = await (0, vertexAi_1.generateVertexContent)({
            contents: [{ role: 'user', parts: [{ text }] }],
            config: { systemInstruction: SYSTEM, temperature: 0.1, maxOutputTokens: 1024 },
        });
        const out = ((_c = res.text) !== null && _c !== void 0 ? _c : '').trim();
        // Guard against a model that answers instead of cleaning: lengths must stay close.
        if (!out || out.length > text.length * 1.4 + 20 || out.length < text.length * 0.4)
            return { text };
        return { text: out };
    }
    catch (e) {
        logger.warn('[voiceTidy] failed', { error: String(e) });
        return { text };
    }
});
//# sourceMappingURL=voiceTidy.js.map