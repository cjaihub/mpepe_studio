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
exports.generateKeywords = generateKeywords;
exports.generateEmbedding = generateEmbedding;
const logger = __importStar(require("firebase-functions/logger"));
// Basic tokenization for Firestore array-contains search
function generateKeywords(text) {
    if (!text)
        return [];
    // Convert to lowercase and split by non-word characters
    const words = text.toLowerCase().split(/[\s,.\-!?"'()[\]{}<>]+/).filter(w => w.length > 0);
    const keywords = new Set();
    for (const word of words) {
        keywords.add(word);
        // Simple prefixes for partial matching (e.g., typing "hell" matches "hello")
        for (let i = 2; i <= word.length; i++) {
            keywords.add(word.substring(0, i));
        }
    }
    // Limit to prevent excessive index size
    const maxKeywords = 1000;
    return Array.from(keywords).slice(0, maxKeywords);
}
/**
 * Utility to generate vector embeddings using Google Gen AI via Vertex AI.
 * This is used for Semantic Search if enabled.
 */
async function generateEmbedding(text) {
    try {
        // const auth = new GoogleAuth({
        //   scopes: 'https://www.googleapis.com/auth/cloud-platform',
        // });
        // const projectId = await auth.getProjectId();
        // const client = await auth.getClient();
        // Using Vertex AI textembedding-gecko or similar model
        // Note: If you have configured `@google/genai` or Vertex AI SDK, you can use that directly.
        // For now, this is a placeholder that returns a dummy embedding for compilation.
        // In production, implement a real call to Vertex AI `text-multilingual-embedding-002`.
        logger.info(`Generating embedding for text length: ${text.length}`);
        // Placeholder returning a 768-dimensional zero vector
        return new Array(768).fill(0);
    }
    catch (error) {
        logger.error("Failed to generate embedding", error);
        return [];
    }
}
//# sourceMappingURL=searchUtils.js.map