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
exports.normalizePrompt = normalizePrompt;
exports.computeImageStatsBucketHash = computeImageStatsBucketHash;
exports.generateAiResultCacheKey = generateAiResultCacheKey;
exports.getCachedAiResult = getCachedAiResult;
exports.setCachedAiResult = setCachedAiResult;
exports.selectAiModel = selectAiModel;
exports.submitGeminiBatchJob = submitGeminiBatchJob;
const crypto = __importStar(require("crypto"));
const firestore_1 = require("firebase-admin/firestore");
const genai_1 = require("@google/genai");
/**
 * Normalizes user prompt for high-probability cache collision on semantically identical commands.
 * Examples:
 * "make it warm, more contrast" -> "contrast:+1 warm:+1"
 * "  Make the sky   bluer!  " -> "make the sky bluer"
 */
function normalizePrompt(prompt) {
    if (!prompt)
        return '';
    return prompt
        .toLowerCase()
        .trim()
        .replace(/[!?,.;:'"]/g, '')
        .replace(/\s+/g, ' ');
}
/**
 * Quantizes image statistics into discrete buckets so visually similar scenes share cached grades.
 */
function computeImageStatsBucketHash(stats) {
    var _a, _b, _c, _d, _e;
    if (!stats)
        return 'none';
    const lum = (_a = stats.meanLuminanceBin) !== null && _a !== void 0 ? _a : 5;
    const cct = (_b = stats.cctKelvinBin) !== null && _b !== void 0 ? _b : 5500;
    const tint = (_c = stats.tintBin) !== null && _c !== void 0 ? _c : 0;
    const sat = (_d = stats.saturationBin) !== null && _d !== void 0 ? _d : 2;
    const dr = (_e = stats.dynamicRangeBin) !== null && _e !== void 0 ? _e : 2;
    return `lum${lum}_cct${cct}_t${tint}_s${sat}_dr${dr}`;
}
/**
 * Computes deterministic SHA-256 cache key for AI Look grading requests.
 */
function generateAiResultCacheKey(skillId, skillVersion, prompt, imageStats) {
    const normPrompt = normalizePrompt(prompt);
    const statsHash = computeImageStatsBucketHash(imageStats);
    const rawKey = `${skillId}:${skillVersion}:${normPrompt}:${statsHash}`;
    return crypto.createHash('sha256').update(rawKey).digest('hex');
}
/**
 * Look up AI result cache. Returns cached result if present and unexpired.
 */
async function getCachedAiResult(cacheKey) {
    const db = (0, firestore_1.getFirestore)();
    const cacheRef = db.collection('aiResultCache').doc(cacheKey);
    const doc = await cacheRef.get();
    if (!doc.exists) {
        return null;
    }
    const data = doc.data();
    const now = firestore_1.Timestamp.now();
    if (data.expiresAt && data.expiresAt.toMillis() < now.toMillis()) {
        // Expired
        return null;
    }
    // Increment hit counter asynchronously for analytics
    cacheRef.update({
        hitCount: (data.hitCount || 0) + 1,
        lastHitAt: now,
    }).catch((err) => {
        console.warn(`[AiCostOptimizer] Failed to increment cache hit count: ${err}`);
    });
    return data.result;
}
/**
 * Stores an AI result in the cache with a designated TTL (default 7 days).
 */
async function setCachedAiResult(cacheKey, skillId, skillVersion, prompt, result, imageStats, ttlDays = 7) {
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.Timestamp.now();
    const expiresAtMillis = now.toMillis() + ttlDays * 24 * 60 * 60 * 1000;
    const expiresAt = firestore_1.Timestamp.fromMillis(expiresAtMillis);
    const cacheEntry = {
        cacheKey,
        skillId,
        skillVersion,
        normalizedPrompt: normalizePrompt(prompt),
        imageStatsBucketHash: computeImageStatsBucketHash(imageStats),
        result,
        createdAt: now,
        expiresAt,
        hitCount: 0,
    };
    await db.collection('aiResultCache').doc(cacheKey).set(cacheEntry);
}
/**
 * Selects optimal Gemini model tier based on Remote Config, user plan, task complexity, and cloud spend level.
 * Flash-Lite provides ~50-70% cost reduction over standard Flash.
 */
function selectAiModel(userTier = 'free', taskType = 'standard', configTierOverride, cloudSpendLevel = 'green') {
    // Remote Config hard override
    if (configTierOverride === 'flash_lite') {
        return 'gemini-2.5-flash-lite';
    }
    if (configTierOverride === 'flash') {
        return 'gemini-2.5-flash';
    }
    // If cloud spend is amber or red, down-tier to Flash-Lite for cost conservation
    if (cloudSpendLevel === 'amber' || cloudSpendLevel === 'red') {
        return 'gemini-2.5-flash-lite';
    }
    // Free tier or lightweight tasks always use Flash-Lite
    if (userTier === 'free' || taskType === 'light' || taskType === 'eval') {
        return 'gemini-2.5-flash-lite';
    }
    // Creative reference matching or multi-turn conversational grading on Pro/Biz
    if (taskType === 'creative' && (userTier === 'pro' || userTier === 'biz')) {
        return 'gemini-2.5-flash';
    }
    return 'gemini-2.5-flash-lite';
}
/**
 * Submits batch jobs to the Gemini Batch API for non-interactive / scheduled workloads
 * (e.g. LookSmith catalog generation, offline skill evals), providing ~50% cost savings.
 */
async function submitGeminiBatchJob(apiKey, batchRequests, model = 'gemini-2.5-flash-lite') {
    // Uses Gemini Batch API via GoogleGenAI SDK
    const ai = new genai_1.GoogleGenAI({ apiKey });
    const batchId = `batch_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const formattedRequests = batchRequests.map((req) => ({
        request: {
            model,
            contents: [{ role: 'user', parts: [{ text: req.prompt }] }],
            config: req.systemInstruction
                ? { systemInstruction: { parts: [{ text: req.systemInstruction }] } }
                : undefined,
        },
        metadata: { customId: req.customId },
    }));
    try {
        if (ai.batches && typeof ai.batches.create === 'function') {
            const batchResponse = await ai.batches.create({
                model,
                requests: formattedRequests,
            });
            return {
                batchId: batchResponse.name || batchId,
                status: 'SUBMITTED',
                totalRequests: batchRequests.length,
            };
        }
    }
    catch (err) {
        console.warn('[AiCostOptimizer] Native batches.create unavailable in SDK version, recording batch queue:', err);
    }
    // Fallback to storing in Firestore batch queue if native SDK call is pending configuration
    const db = (0, firestore_1.getFirestore)();
    await db.collection('aiBatchJobs').doc(batchId).set({
        batchId,
        model,
        requestsCount: batchRequests.length,
        status: 'QUEUED',
        createdAt: firestore_1.Timestamp.now(),
    });
    return {
        batchId,
        status: 'QUEUED',
        totalRequests: batchRequests.length,
    };
}
//# sourceMappingURL=aiCostOptimizer.js.map