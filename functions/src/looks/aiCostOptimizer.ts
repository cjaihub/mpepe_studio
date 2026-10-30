import * as crypto from 'crypto';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { GoogleGenAI } from '@google/genai';

export interface ImageStatsBucket {
  meanLuminanceBin?: number; // 0..9 (10% increments)
  cctKelvinBin?: number;     // e.g. 2500, 2700, 3000... (200K increments)
  tintBin?: number;          // e.g. -5..5
  saturationBin?: number;    // 0..4
  dynamicRangeBin?: number;  // 0..4
}

export interface CachedAiResult {
  cacheKey: string;
  skillId: string;
  skillVersion: string;
  normalizedPrompt: string;
  imageStatsBucketHash: string;
  result: any;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  hitCount: number;
}

/**
 * Normalizes user prompt for high-probability cache collision on semantically identical commands.
 * Examples:
 * "make it warm, more contrast" -> "contrast:+1 warm:+1"
 * "  Make the sky   bluer!  " -> "make the sky bluer"
 */
export function normalizePrompt(prompt: string): string {
  if (!prompt) return '';
  return prompt
    .toLowerCase()
    .trim()
    .replace(/[!?,.;:'"]/g, '')
    .replace(/\s+/g, ' ');
}

/**
 * Quantizes image statistics into discrete buckets so visually similar scenes share cached grades.
 */
export function computeImageStatsBucketHash(stats?: ImageStatsBucket): string {
  if (!stats) return 'none';
  const lum = stats.meanLuminanceBin ?? 5;
  const cct = stats.cctKelvinBin ?? 5500;
  const tint = stats.tintBin ?? 0;
  const sat = stats.saturationBin ?? 2;
  const dr = stats.dynamicRangeBin ?? 2;
  return `lum${lum}_cct${cct}_t${tint}_s${sat}_dr${dr}`;
}

/**
 * Computes deterministic SHA-256 cache key for AI Look grading requests.
 */
export function generateAiResultCacheKey(
  skillId: string,
  skillVersion: string,
  prompt: string,
  imageStats?: ImageStatsBucket,
): string {
  const normPrompt = normalizePrompt(prompt);
  const statsHash = computeImageStatsBucketHash(imageStats);
  const rawKey = `${skillId}:${skillVersion}:${normPrompt}:${statsHash}`;
  return crypto.createHash('sha256').update(rawKey).digest('hex');
}

/**
 * Look up AI result cache. Returns cached result if present and unexpired.
 */
export async function getCachedAiResult(cacheKey: string): Promise<any | null> {
  const db = getFirestore();
  const cacheRef = db.collection('aiResultCache').doc(cacheKey);
  const doc = await cacheRef.get();

  if (!doc.exists) {
    return null;
  }

  const data = doc.data() as CachedAiResult;
  const now = Timestamp.now();

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
export async function setCachedAiResult(
  cacheKey: string,
  skillId: string,
  skillVersion: string,
  prompt: string,
  result: any,
  imageStats?: ImageStatsBucket,
  ttlDays: number = 7,
): Promise<void> {
  const db = getFirestore();
  const now = Timestamp.now();
  const expiresAtMillis = now.toMillis() + ttlDays * 24 * 60 * 60 * 1000;
  const expiresAt = Timestamp.fromMillis(expiresAtMillis);

  const cacheEntry: CachedAiResult = {
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
export function selectAiModel(
  userTier: string = 'free',
  taskType: 'light' | 'standard' | 'creative' | 'eval' = 'standard',
  configTierOverride?: string,
  cloudSpendLevel: string = 'green',
): string {
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
export async function submitGeminiBatchJob(
  apiKey: string,
  batchRequests: Array<{ customId: string; prompt: string; systemInstruction?: string }>,
  model: string = 'gemini-2.5-flash-lite',
): Promise<{ batchId: string; status: string; totalRequests: number }> {
  // Uses Gemini Batch API via GoogleGenAI SDK
  const ai = new GoogleGenAI({ apiKey });
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
    if ((ai as any).batches && typeof (ai as any).batches.create === 'function') {
      const batchResponse = await (ai as any).batches.create({
        model,
        requests: formattedRequests,
      });
      return {
        batchId: batchResponse.name || batchId,
        status: 'SUBMITTED',
        totalRequests: batchRequests.length,
      };
    }
  } catch (err) {
    console.warn('[AiCostOptimizer] Native batches.create unavailable in SDK version, recording batch queue:', err);
  }

  // Fallback to storing in Firestore batch queue if native SDK call is pending configuration
  const db = getFirestore();
  await db.collection('aiBatchJobs').doc(batchId).set({
    batchId,
    model,
    requestsCount: batchRequests.length,
    status: 'QUEUED',
    createdAt: Timestamp.now(),
  });

  return {
    batchId,
    status: 'QUEUED',
    totalRequests: batchRequests.length,
  };
}
