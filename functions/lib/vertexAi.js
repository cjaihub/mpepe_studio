"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GEMINI_FLASH_MODELS = void 0;
exports.vertexAi = vertexAi;
exports.generateVertexContent = generateVertexContent;
/**
 * Gemini through Vertex AI, authenticated as the function's own service
 * account (no API key to store or leak). Needs the Vertex AI API
 * (aiplatform.googleapis.com) enabled and roles/aiplatform.user on the
 * runtime service account; tools/play/backend_setup.sh does both.
 */
const genai_1 = require("@google/genai");
const LOCATION = process.env.VERTEX_LOCATION || 'us-central1';
exports.GEMINI_FLASH_MODELS = [
    process.env.GEMINI_MODEL || 'gemini-1.5-flash',
    'gemini-2.0-flash',
    'gemini-2.5-flash',
];
let client = null;
function vertexAi() {
    client !== null && client !== void 0 ? client : (client = new genai_1.GoogleGenAI({
        vertexai: true,
        project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
        location: LOCATION,
    }));
    return client;
}
/**
 * Calls `ai.models.generateContent` across [GEMINI_FLASH_MODELS] so a retired
 * model ID (HTTP 404 NOT_FOUND) automatically upgrades to `gemini-3.8-flash`.
 */
async function generateVertexContent(params) {
    var _a, _b;
    var _c;
    const ai = vertexAi();
    const candidates = params.model
        ? Array.from(new Set([params.model, ...exports.GEMINI_FLASH_MODELS]))
        : Array.from(new Set(exports.GEMINI_FLASH_MODELS));
    let lastErr;
    for (const model of candidates) {
        try {
            return await ai.models.generateContent(Object.assign(Object.assign({}, params), { model }));
        }
        catch (err) {
            lastErr = err;
            const jsonStr = (() => {
                try {
                    return JSON.stringify(err);
                }
                catch (_a) {
                    return '';
                }
            })();
            const msg = `${(_c = err === null || err === void 0 ? void 0 : err.message) !== null && _c !== void 0 ? _c : ''} ${jsonStr}`.toLowerCase();
            const isNotFound = (err === null || err === void 0 ? void 0 : err.status) === 404 ||
                (err === null || err === void 0 ? void 0 : err.code) === 404 ||
                (err === null || err === void 0 ? void 0 : err.status) === 'NOT_FOUND' ||
                ((_a = err === null || err === void 0 ? void 0 : err.error) === null || _a === void 0 ? void 0 : _a.code) === 404 ||
                ((_b = err === null || err === void 0 ? void 0 : err.error) === null || _b === void 0 ? void 0 : _b.status) === 'NOT_FOUND' ||
                msg.includes('404') ||
                msg.includes('not_found') ||
                msg.includes('not found') ||
                msg.includes('no longer available') ||
                msg.includes('does not have access');
            if (!isNotFound)
                throw err;
        }
    }
    throw lastErr;
}
//# sourceMappingURL=vertexAi.js.map