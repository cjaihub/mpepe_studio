"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getComputeJobStatusCallable = exports.enqueueComputeJobCallable = exports.createLookOptimized = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const firestore_1 = require("firebase-admin/firestore");
const genai_1 = require("@google/genai");
const rateLimiter_1 = require("./rateLimiter");
const aiCostOptimizer_1 = require("./aiCostOptimizer");
const computeJobSystem_1 = require("./computeJobSystem");
const geminiSecret = (0, params_1.defineSecret)('GEMINI_API_KEY');
/**
 * Cost-optimized AI Look creation and conversational grading callable.
 * Integrates:
 * 1. App Check enforcement
 * 2. Token-bucket rate limiting (prevents API flooding)
 * 3. Daily tier quotas (Free: 10, Pro: 100, Biz: 500)
 * 4. Result caching (key = skillVersion + normalized prompt + image stats bucket) -> 0 LLM cost on cache hit
 * 5. Model tiering (Flash-Lite by default or during Amber/Red spend, Flash for Pro creative)
 */
exports.createLookOptimized = (0, https_1.onCall)({ secrets: [geminiSecret] }, async (request) => {
    var _a;
    // 1. Authentication Check
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated to use AI Looks.');
    }
    const uid = request.auth.uid;
    const userTier = request.auth.token.tier || 'free';
    // 2. App Check Enforcement
    (0, rateLimiter_1.enforceAppCheck)(request, true);
    // 3. Token-bucket Rate Limiter Check
    const rateCheck = await (0, rateLimiter_1.checkTokenBucketRateLimit)(uid, 'createLook', userTier);
    if (!rateCheck.allowed) {
        throw new https_1.HttpsError('resource-exhausted', `Rate limit exceeded. Please wait ${rateCheck.retryAfterSec} seconds.`);
    }
    // 4. Daily Quota Check
    const quotaCheck = await (0, rateLimiter_1.checkAndIncrementDailyQuota)(uid, 'dailyGenerations', userTier);
    if (!quotaCheck.allowed) {
        throw new https_1.HttpsError('resource-exhausted', `Daily AI generation quota reached (${quotaCheck.currentCount}/${quotaCheck.limit}). Upgrade to Pro for more.`);
    }
    const { prompt, skillId = 'look_from_prompt', skillVersion = '1.0.0', imageStats, taskType = 'standard', } = request.data;
    if (!prompt || typeof prompt !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'Missing or invalid "prompt" parameter.');
    }
    // 5. Cloud Spend State Check
    const db = (0, firestore_1.getFirestore)();
    const spendDoc = await db.collection('opsConfig').doc('cloudSpend').get();
    const spendLevel = ((_a = spendDoc.data()) === null || _a === void 0 ? void 0 : _a.level) || 'green';
    // In RED spend level, non-biz requests are paused
    if (spendLevel === 'red' && userTier !== 'biz') {
        throw new https_1.HttpsError('failed-precondition', 'Cloud AI is temporarily paused by Budget Guard. Please use offline on-device AI.');
    }
    // 6. Result Cache Lookup
    const cacheKey = (0, aiCostOptimizer_1.generateAiResultCacheKey)(skillId, skillVersion, prompt, imageStats);
    const cachedResult = await (0, aiCostOptimizer_1.getCachedAiResult)(cacheKey);
    if (cachedResult) {
        return {
            success: true,
            cacheHit: true,
            cacheKey,
            data: cachedResult,
        };
    }
    // 7. Model Tier Selection (Flash-Lite vs Flash)
    const selectedModel = (0, aiCostOptimizer_1.selectAiModel)(userTier, taskType, undefined, spendLevel);
    const apiKey = geminiSecret.value();
    if (!apiKey) {
        throw new https_1.HttpsError('internal', 'AI service credentials not configured.');
    }
    const ai = new genai_1.GoogleGenAI({ apiKey });
    const systemInstruction = `You are the Oneova Look AI Colorist. Output valid JSON representing look adjustment parameters (exposure, contrast, saturation, temperature, tint, vibrance).`;
    try {
        const response = await ai.models.generateContent({
            model: selectedModel,
            contents: [
                {
                    role: 'user',
                    parts: [{ text: `System: ${systemInstruction}\n\nUser Command: ${prompt}` }],
                },
            ],
        });
        const replyText = response.text || '{}';
        let parsedLook;
        try {
            const cleanJson = replyText.replace(/```json/g, '').replace(/```/g, '').trim();
            parsedLook = JSON.parse(cleanJson);
        }
        catch (_b) {
            parsedLook = {
                name: prompt.substring(0, 30),
                primary: { exposure: 0.1, contrast: 1.1 },
                color: { saturation: 1.05 },
            };
        }
        // 8. Cache result for subsequent identical requests
        await (0, aiCostOptimizer_1.setCachedAiResult)(cacheKey, skillId, skillVersion, prompt, parsedLook, imageStats, 7);
        return {
            success: true,
            cacheHit: false,
            cacheKey,
            modelUsed: selectedModel,
            data: parsedLook,
        };
    }
    catch (err) {
        console.error('[LooksCallables] Gemini invocation error:', (err === null || err === void 0 ? void 0 : err.message) || err);
        throw new https_1.HttpsError('internal', 'AI generation failed. Please try again.');
    }
});
/**
 * Callable to enqueue a GPU compute job (cloud render, rotoscope, AI enhance).
 * Enforces Budget Guard, Rate Limiting, and Priority Lanes.
 */
exports.enqueueComputeJobCallable = (0, https_1.onCall)(async (request) => {
    var _a;
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = request.auth.uid;
    const userTier = request.auth.token.tier || 'free';
    // 1. App Check
    (0, rateLimiter_1.enforceAppCheck)(request, true);
    // 2. Rate Limiting
    const rateCheck = await (0, rateLimiter_1.checkTokenBucketRateLimit)(uid, 'enqueueComputeJob', userTier);
    if (!rateCheck.allowed) {
        throw new https_1.HttpsError('resource-exhausted', `Rate limit exceeded. Retry in ${rateCheck.retryAfterSec}s.`);
    }
    // 3. Cloud Spend Kill-Switch Enforcement
    const db = (0, firestore_1.getFirestore)();
    const spendDoc = await db.collection('opsConfig').doc('cloudSpend').get();
    const spendLevel = ((_a = spendDoc.data()) === null || _a === void 0 ? void 0 : _a.level) || 'green';
    if (spendLevel === 'red' && userTier !== 'biz') {
        throw new https_1.HttpsError('failed-precondition', 'Cloud compute paused by Budget Guard (RED level). Please process export on-device.');
    }
    if (spendLevel === 'amber' && userTier === 'free') {
        throw new https_1.HttpsError('failed-precondition', 'Free-tier cloud capacity is restricted under Budget Guard (AMBER level). Please render on device.');
    }
    // 4. Daily Cloud Render Quota
    const quotaCheck = await (0, rateLimiter_1.checkAndIncrementDailyQuota)(uid, 'dailyCloudRenders', userTier);
    if (!quotaCheck.allowed) {
        throw new https_1.HttpsError('resource-exhausted', `Daily Cloud Render quota reached (${quotaCheck.currentCount}/${quotaCheck.limit}).`);
    }
    const { taskType, inputPayload } = request.data;
    if (!taskType || !inputPayload) {
        throw new https_1.HttpsError('invalid-argument', 'Missing taskType or inputPayload.');
    }
    const job = await (0, computeJobSystem_1.enqueueComputeJob)(uid, userTier, taskType, inputPayload);
    return {
        success: true,
        jobId: job.id,
        priorityLane: job.priorityLane,
        status: job.status,
        expiresAt: job.expiresAt.toDate().toISOString(),
    };
});
/**
 * Callable to check status of a compute job.
 */
exports.getComputeJobStatusCallable = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e, _f;
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const { jobId } = request.data;
    if (!jobId) {
        throw new https_1.HttpsError('invalid-argument', 'Missing jobId.');
    }
    const db = (0, firestore_1.getFirestore)();
    const jobDoc = await db.collection('computeJobs').doc(jobId).get();
    if (!jobDoc.exists) {
        throw new https_1.HttpsError('not-found', 'Job not found.');
    }
    const data = jobDoc.data();
    if (data.userId !== request.auth.uid) {
        throw new https_1.HttpsError('permission-denied', 'Access denied to this job.');
    }
    return {
        jobId: data.id,
        status: data.status,
        progress: data.progress,
        priorityLane: data.priorityLane,
        resultPayload: data.resultPayload || null,
        error: data.error || null,
        createdAt: (_c = (_b = (_a = data.createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString(),
        updatedAt: (_f = (_e = (_d = data.updatedAt) === null || _d === void 0 ? void 0 : _d.toDate) === null || _e === void 0 ? void 0 : _e.call(_d)) === null || _f === void 0 ? void 0 : _f.toISOString(),
    };
});
//# sourceMappingURL=looksCallables.js.map