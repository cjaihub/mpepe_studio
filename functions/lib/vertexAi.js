"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.vertexAi = vertexAi;
/**
 * Gemini through Vertex AI, authenticated as the function's own service
 * account (no API key to store or leak). Needs the Vertex AI API
 * (aiplatform.googleapis.com) enabled and roles/aiplatform.user on the
 * runtime service account; tools/play/backend_setup.sh does both.
 */
const genai_1 = require("@google/genai");
const LOCATION = process.env.VERTEX_LOCATION || 'us-central1';
let client = null;
function vertexAi() {
    client !== null && client !== void 0 ? client : (client = new genai_1.GoogleGenAI({
        vertexai: true,
        project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
        location: LOCATION,
    }));
    return client;
}
//# sourceMappingURL=vertexAi.js.map