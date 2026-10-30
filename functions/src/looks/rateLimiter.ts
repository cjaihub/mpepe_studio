import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

export interface TierLimits {
  ratePerMinute: number;
  dailyGenerations: number;
  dailyCloudRenders: number;
}

export const defaultTierQuotas: Record<'free' | 'pro' | 'biz', TierLimits> = {
  free: {
    ratePerMinute: 10,
    dailyGenerations: 10,
    dailyCloudRenders: 1,
  },
  pro: {
    ratePerMinute: 30,
    dailyGenerations: 100,
    dailyCloudRenders: 20,
  },
  biz: {
    ratePerMinute: 60,
    dailyGenerations: 500,
    dailyCloudRenders: 100,
  },
};

/**
 * Enforces Firebase App Check verification to block unauthorized bot traffic and DDoS attacks.
 */
export function enforceAppCheck(
  request: CallableRequest<any>,
  allowUnverifiedInDev: boolean = false,
): void {
  // If in emulator or explicit dev bypass flag is set
  if (allowUnverifiedInDev && process.env.FUNCTIONS_EMULATOR === 'true') {
    return;
  }

  if (!request.app) {
    throw new HttpsError(
      'failed-precondition',
      'The function must be called from an App Check verified app instance.',
    );
  }
}

/**
 * Token-bucket rate limiter stored in `rateLimits/{uid}_{action}`.
 * Prevents rapid-fire API flooding.
 */
export async function checkTokenBucketRateLimit(
  uid: string,
  action: string,
  tier: 'free' | 'pro' | 'biz' = 'free',
  quotas: Record<'free' | 'pro' | 'biz', TierLimits> = defaultTierQuotas,
): Promise<{ allowed: boolean; remainingTokens: number; retryAfterSec?: number }> {
  const db = getFirestore();
  const docRef = db.collection('rateLimits').doc(`${uid}_${action}`);

  const limits = quotas[tier] || defaultTierQuotas.free;
  const capacity = limits.ratePerMinute;
  const refillRatePerSec = capacity / 60.0;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const nowMillis = Date.now();
    const expiresAt = Timestamp.fromMillis(nowMillis + 24 * 60 * 60 * 1000); // 24hr TTL

    let tokens = capacity;
    let lastRefillMillis = nowMillis;

    if (snap.exists) {
      const data = snap.data();
      const storedTokens = typeof data?.tokens === 'number' ? data.tokens : capacity;
      lastRefillMillis = data?.lastRefillMillis || nowMillis;

      const elapsedSec = Math.max(0, (nowMillis - lastRefillMillis) / 1000.0);
      tokens = Math.min(capacity, storedTokens + elapsedSec * refillRatePerSec);
    }

    if (tokens >= 1.0) {
      tokens -= 1.0;
      tx.set(
        docRef,
        {
          tokens,
          lastRefillMillis: nowMillis,
          capacity,
          refillRatePerSec,
          updatedAt: Timestamp.now(),
          expiresAt,
        },
        { merge: true },
      );
      return { allowed: true, remainingTokens: Math.floor(tokens) };
    } else {
      const missingTokens = 1.0 - tokens;
      const retryAfterSec = Math.ceil(missingTokens / refillRatePerSec);
      return { allowed: false, remainingTokens: 0, retryAfterSec };
    }
  });
}

/**
 * Checks and increments per-user daily quota for AI generation or Cloud Renders.
 */
export async function checkAndIncrementDailyQuota(
  uid: string,
  actionType: 'dailyGenerations' | 'dailyCloudRenders',
  tier: 'free' | 'pro' | 'biz' = 'free',
  quotas: Record<'free' | 'pro' | 'biz', TierLimits> = defaultTierQuotas,
): Promise<{ allowed: boolean; currentCount: number; limit: number }> {
  const db = getFirestore();
  const todayKey = new Date().toISOString().substring(0, 10).replace(/-/g, ''); // yyyyMMdd
  const quotaRef = db.collection('users').doc(uid).collection('quotas').doc(todayKey);

  const limits = quotas[tier] || defaultTierQuotas.free;
  const limit = actionType === 'dailyGenerations' ? limits.dailyGenerations : limits.dailyCloudRenders;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(quotaRef);
    let currentCount = 0;

    if (snap.exists) {
      currentCount = (snap.data()?.[actionType] as number) || 0;
    }

    if (currentCount >= limit) {
      return { allowed: false, currentCount, limit };
    }

    tx.set(
      quotaRef,
      {
        [actionType]: currentCount + 1,
        tier,
        date: todayKey,
        updatedAt: Timestamp.now(),
      },
      { merge: true },
    );

    return { allowed: true, currentCount: currentCount + 1, limit };
  });
}
