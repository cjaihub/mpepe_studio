import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

export type CloudSpendLevel = 'green' | 'amber' | 'red';

export interface BudgetAlertPayload {
  budgetDisplayName?: string;
  costAmount: number;
  costIntervalStart?: string;
  budgetAmount: number;
  currencyCode?: string;
}

export interface SpendThresholds {
  amberThreshold: number; // e.g. 0.80 (80%)
  redThreshold: number;   // e.g. 1.00 (100%)
}

export const defaultSpendThresholds: SpendThresholds = {
  amberThreshold: 0.80,
  redThreshold: 1.00,
};

/**
 * Pure evaluation function computing spend level from current cost, budget, and thresholds.
 */
export function evaluateSpendLevel(
  costAmount: number,
  budgetAmount: number,
  thresholds: SpendThresholds = defaultSpendThresholds,
): { level: CloudSpendLevel; ratio: number; reason: string } {
  if (budgetAmount <= 0) {
    return {
      level: 'green',
      ratio: 0.0,
      reason: 'No budget ceiling configured; green status maintained.',
    };
  }

  const ratio = costAmount / budgetAmount;

  if (ratio >= thresholds.redThreshold) {
    return {
      level: 'red',
      ratio,
      reason: `Cloud spend ($${costAmount.toFixed(2)}) reached or exceeded 100% of budget ($${budgetAmount.toFixed(2)}). Cloud compute restricted to paid/critical only.`,
    };
  }

  if (ratio >= thresholds.amberThreshold) {
    return {
      level: 'amber',
      ratio,
      reason: `Cloud spend ($${costAmount.toFixed(2)}) reached ${(ratio * 100).toFixed(1)}% of budget ($${budgetAmount.toFixed(2)}). Free-tier cloud jobs routed to on-device.`,
    };
  }

  return {
    level: 'green',
    ratio,
    reason: `Cloud spend ($${costAmount.toFixed(2)}) is normal (${(ratio * 100).toFixed(1)}% of budget).`,
  };
}

/**
 * Writes the evaluated spend level to `opsConfig/cloudSpend`.
 */
export async function updateCloudSpendConfig(
  level: CloudSpendLevel,
  costAmount: number,
  budgetAmount: number,
  currency: string = 'USD',
  reason?: string,
): Promise<void> {
  const db = getFirestore();
  const now = Timestamp.now();

  await db.collection('opsConfig').doc('cloudSpend').set(
    {
      level,
      costAmount,
      budgetAmount,
      currency,
      ratio: budgetAmount > 0 ? costAmount / budgetAmount : 0,
      reason: reason || `Updated at ${now.toDate().toISOString()}`,
      updatedAt: now,
    },
    { merge: true },
  );

  console.log(`[BudgetGuard] opsConfig/cloudSpend set to ${level.toUpperCase()}: ${reason}`);
}

/**
 * Cloud Function triggered by Cloud Billing Budget alerts published to `billing-budget-alerts` Pub/Sub topic.
 */
export const onBillingBudgetNotification = onMessagePublished(
  { topic: 'billing-budget-alerts' },
  async (event) => {
    try {
      const messageData = event.data.message.json as BudgetAlertPayload;
      if (!messageData || typeof messageData.costAmount !== 'number' || typeof messageData.budgetAmount !== 'number') {
        console.warn('[BudgetGuard] Received invalid budget notification payload:', event.data.message);
        return;
      }

      const { costAmount, budgetAmount, currencyCode = 'USD' } = messageData;
      const evaluation = evaluateSpendLevel(costAmount, budgetAmount);

      await updateCloudSpendConfig(
        evaluation.level,
        costAmount,
        budgetAmount,
        currencyCode,
        evaluation.reason,
      );
    } catch (err) {
      console.error('[BudgetGuard] Error processing billing notification:', err);
    }
  },
);
