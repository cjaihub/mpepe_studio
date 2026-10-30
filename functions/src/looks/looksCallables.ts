import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { getFirestore } from 'firebase-admin/firestore';
import { GoogleGenAI } from '@google/genai';
import { enforceAppCheck, checkTokenBucketRateLimit, checkAndIncrementDailyQuota } from './rateLimiter';
import {
  generateAiResultCacheKey,
  getCachedAiResult,
  setCachedAiResult,
  selectAiModel,
  ImageStatsBucket,
} from './aiCostOptimizer';
import { enqueueComputeJob, ComputeTaskType } from './computeJobSystem';

const geminiSecret = defineSecret('GEMINI_API_KEY');

/**
 * Cost-optimized AI Look creation and conversational grading callable.
 * Integrates:
 * 1. App Check enforcement
 * 2. Token-bucket rate limiting (prevents API flooding)
 * 3. Daily tier quotas (Free: 10, Pro: 100, Biz: 500)
 * 4. Result caching (key = skillVersion + normalized prompt + image stats bucket) -> 0 LLM cost on cache hit
 * 5. Model tiering (Flash-Lite by default or during Amber/Red spend, Flash for Pro creative)
 */
export const createLookOptimized = onCall(
  { secrets: [geminiSecret] },
  async (request) => {
    // 1. Authentication Check
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated to use AI Looks.');
    }
    const uid = request.auth.uid;
    const userTier: 'free' | 'pro' | 'biz' = (request.auth.token.tier as any) || 'free';

    // 2. App Check Enforcement
    enforceAppCheck(request, true);

    // 3. Token-bucket Rate Limiter Check
    const rateCheck = await checkTokenBucketRateLimit(uid, 'createLook', userTier);
    if (!rateCheck.allowed) {
      throw new HttpsError(
        'resource-exhausted',
        `Rate limit exceeded. Please wait ${rateCheck.retryAfterSec} seconds.`,
      );
    }

    // 4. Daily Quota Check
    const quotaCheck = await checkAndIncrementDailyQuota(uid, 'dailyGenerations', userTier);
    if (!quotaCheck.allowed) {
      throw new HttpsError(
        'resource-exhausted',
        `Daily AI generation quota reached (${quotaCheck.currentCount}/${quotaCheck.limit}). Upgrade to Pro for more.`,
      );
    }

    const {
      prompt,
      skillId = 'look_from_prompt',
      skillVersion = '1.0.0',
      imageStats,
      taskType = 'standard',
    } = request.data as {
      prompt: string;
      skillId?: string;
      skillVersion?: string;
      imageStats?: ImageStatsBucket;
      taskType?: 'light' | 'standard' | 'creative' | 'eval';
    };

    if (!prompt || typeof prompt !== 'string') {
      throw new HttpsError('invalid-argument', 'Missing or invalid "prompt" parameter.');
    }

    // 5. Cloud Spend State Check
    const db = getFirestore();
    const spendDoc = await db.collection('opsConfig').doc('cloudSpend').get();
    const spendLevel = spendDoc.data()?.level || 'green';

    // In RED spend level, non-biz requests are paused
    if (spendLevel === 'red' && userTier !== 'biz') {
      throw new HttpsError(
        'failed-precondition',
        'Cloud AI is temporarily paused by Budget Guard. Please use offline on-device AI.',
      );
    }

    // 6. Result Cache Lookup
    const cacheKey = generateAiResultCacheKey(skillId, skillVersion, prompt, imageStats);
    const cachedResult = await getCachedAiResult(cacheKey);

    if (cachedResult) {
      return {
        success: true,
        cacheHit: true,
        cacheKey,
        data: cachedResult,
      };
    }

    // 7. Model Tier Selection (Flash-Lite vs Flash)
    const selectedModel = selectAiModel(userTier, taskType, undefined, spendLevel);
    const apiKey = geminiSecret.value();

    if (!apiKey) {
      throw new HttpsError('internal', 'AI service credentials not configured.');
    }

    const ai = new GoogleGenAI({ apiKey });
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
      let parsedLook: any;
      try {
        const cleanJson = replyText.replace(/```json/g, '').replace(/```/g, '').trim();
        parsedLook = JSON.parse(cleanJson);
      } catch {
        parsedLook = {
          name: prompt.substring(0, 30),
          primary: { exposure: 0.1, contrast: 1.1 },
          color: { saturation: 1.05 },
        };
      }

      // 8. Cache result for subsequent identical requests
      await setCachedAiResult(cacheKey, skillId, skillVersion, prompt, parsedLook, imageStats, 7);

      return {
        success: true,
        cacheHit: false,
        cacheKey,
        modelUsed: selectedModel,
        data: parsedLook,
      };
    } catch (err: any) {
      console.error('[LooksCallables] Gemini invocation error:', err?.message || err);
      throw new HttpsError('internal', 'AI generation failed. Please try again.');
    }
  },
);

/**
 * Callable to enqueue a GPU compute job (cloud render, rotoscope, AI enhance).
 * Enforces Budget Guard, Rate Limiting, and Priority Lanes.
 */
export const enqueueComputeJobCallable = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const uid = request.auth.uid;
  const userTier: 'free' | 'pro' | 'biz' = (request.auth.token.tier as any) || 'free';

  // 1. App Check
  enforceAppCheck(request, true);

  // 2. Rate Limiting
  const rateCheck = await checkTokenBucketRateLimit(uid, 'enqueueComputeJob', userTier);
  if (!rateCheck.allowed) {
    throw new HttpsError('resource-exhausted', `Rate limit exceeded. Retry in ${rateCheck.retryAfterSec}s.`);
  }

  // 3. Cloud Spend Kill-Switch Enforcement
  const db = getFirestore();
  const spendDoc = await db.collection('opsConfig').doc('cloudSpend').get();
  const spendLevel = spendDoc.data()?.level || 'green';

  if (spendLevel === 'red' && userTier !== 'biz') {
    throw new HttpsError(
      'failed-precondition',
      'Cloud compute paused by Budget Guard (RED level). Please process export on-device.',
    );
  }

  if (spendLevel === 'amber' && userTier === 'free') {
    throw new HttpsError(
      'failed-precondition',
      'Free-tier cloud capacity is restricted under Budget Guard (AMBER level). Please render on device.',
    );
  }

  // 4. Daily Cloud Render Quota
  const quotaCheck = await checkAndIncrementDailyQuota(uid, 'dailyCloudRenders', userTier);
  if (!quotaCheck.allowed) {
    throw new HttpsError(
      'resource-exhausted',
      `Daily Cloud Render quota reached (${quotaCheck.currentCount}/${quotaCheck.limit}).`,
    );
  }

  const { taskType, inputPayload } = request.data as {
    taskType: ComputeTaskType;
    inputPayload: Record<string, any>;
  };

  if (!taskType || !inputPayload) {
    throw new HttpsError('invalid-argument', 'Missing taskType or inputPayload.');
  }

  const job = await enqueueComputeJob(uid, userTier, taskType, inputPayload);

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
export const getComputeJobStatusCallable = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { jobId } = request.data as { jobId: string };
  if (!jobId) {
    throw new HttpsError('invalid-argument', 'Missing jobId.');
  }

  const db = getFirestore();
  const jobDoc = await db.collection('computeJobs').doc(jobId).get();

  if (!jobDoc.exists) {
    throw new HttpsError('not-found', 'Job not found.');
  }

  const data = jobDoc.data()!;
  if (data.userId !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'Access denied to this job.');
  }

  return {
    jobId: data.id,
    status: data.status,
    progress: data.progress,
    priorityLane: data.priorityLane,
    resultPayload: data.resultPayload || null,
    error: data.error || null,
    createdAt: data.createdAt?.toDate?.()?.toISOString(),
    updatedAt: data.updatedAt?.toDate?.()?.toISOString(),
  };
});
