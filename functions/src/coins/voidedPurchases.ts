/**
 * Refunded / charged-back coin packs (Google Play voided purchases).
 *
 *   Play RTDN `voidedPurchaseNotification` → applyVoidedCoinPurchase (fast path)
 *   coinVoidSweep, every 6 h → Voided Purchases API since the last run (backstop)
 *
 * Each void is applied once (`coin_voids/{tokenHash}`). Rules: clawbackLogic.ts.
 * Holds go to `payout_holds/{uid}` (server-only, no client rule); requestWithdrawal
 * sends a held creator's withdrawal to review instead of paying it.
 */
import * as crypto from 'crypto';
import { google } from 'googleapis';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { clawbackPlan, giftRecipients } from './clawbackLogic';
import { ledgerOutbox } from '../ledger/outbox';

const db = () => getFirestore();
const PACKAGE = 'com.oneova.app';

export const tokenHash = (token: string) => crypto.createHash('sha256').update(token).digest('hex');

/** Applies one voided coin purchase. Returns false when it isn't a coin pack or was already applied. */
export async function applyVoidedCoinPurchase(purchaseToken: string, info: { orderId?: string | null; voidedTimeMillis?: string | number | null; reason?: number | null; source?: number | null }): Promise<boolean> {
  const id = tokenHash(purchaseToken);
  const receiptRef = db().doc(`coin_purchases/${id}`);
  const voidRef = db().doc(`coin_voids/${id}`);

  const applied = await db().runTransaction(async (tx) => {
    const [receipt, done] = await Promise.all([tx.get(receiptRef), tx.get(voidRef)]);
    if (done.exists || !receipt.exists) return null;
    const uid = String(receipt.get('uid'));
    const coins = Number(receipt.get('coins') ?? 0);
    const wallet = db().doc(`wallets/${uid}`);
    const w = await tx.get(wallet);
    const plan = clawbackPlan(Number(w.get('balanceCoins') ?? 0), coins);
    tx.set(wallet, {
      balanceCoins: FieldValue.increment(-plan.takeFromBalance),
      ...(plan.addDebt > 0 ? { coinDebt: FieldValue.increment(plan.addDebt) } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(wallet.collection('ledger').doc(`void_${id.slice(0, 24)}`), {
      amount: -plan.takeFromBalance, type: 'coin_purchase_voided', debt: plan.addDebt, coins,
      referenceId: info.orderId ?? receipt.get('orderId') ?? id, createdAt: FieldValue.serverTimestamp(),
    });
    if (plan.takeFromBalance + plan.addDebt > 0) {
      ledgerOutbox(tx, `void_${id}`, 'coin_void', { uid, take_from_balance: plan.takeFromBalance, add_debt: plan.addDebt, order_id: info.orderId ?? null });
    }
    tx.update(receiptRef, { voided: true, voidedAt: FieldValue.serverTimestamp() });
    tx.set(voidRef, {
      uid, coins, ...plan, orderId: info.orderId ?? null, reason: info.reason ?? null, source: info.source ?? null,
      voidedTimeMillis: info.voidedTimeMillis != null ? Number(info.voidedTimeMillis) : null, createdAt: FieldValue.serverTimestamp(),
    });
    return { uid, debt: plan.addDebt, purchasedAt: (receipt.get('createdAt') as Timestamp | undefined)?.toMillis() ?? 0 };
  });
  if (!applied) return false;
  logger.warn('coin purchase voided', { uid: applied.uid, debt: applied.debt });
  if (applied.debt <= 0) return true;

  // The coins were already spent: hold payouts for the buyer and everyone they gifted since.
  const sent = await db().collection(`wallets/${applied.uid}/ledger`)
    .where('createdAt', '>=', Timestamp.fromMillis(applied.purchasedAt)).orderBy('createdAt').limit(500).get();
  const recipients = giftRecipients(sent.docs.map((d) => ({
    type: d.get('type'), toUid: d.get('toUid'), amount: d.get('amount'),
    createdAtMs: (d.get('createdAt') as Timestamp | undefined)?.toMillis() ?? null,
  })), applied.purchasedAt);
  const batch = db().batch();
  for (const uid of [applied.uid, ...recipients.keys()]) {
    batch.set(db().doc(`payout_holds/${uid}`), {
      uid, reasons: FieldValue.arrayUnion(uid === applied.uid ? 'own_coin_purchase_refunded' : 'gift_source_refunded'),
      sources: FieldValue.arrayUnion(applied.uid), updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await batch.commit();
  return true;
}

/** Backstop for missed notifications: reads Play's voided list since the last run. */
export const coinVoidSweep = onSchedule('every 6 hours', async () => {
  const stateRef = db().doc('ops_state/play_voided');
  const since = Number((await stateRef.get()).get('lastVoidedTimeMillis') ?? Date.now() - 30 * 86400_000);
  const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  const api = google.androidpublisher({ version: 'v3', auth });
  let token: string | undefined;
  let newest = since;
  let applied = 0;
  do {
    const res = await api.purchases.voidedpurchases.list({ packageName: PACKAGE, startTime: String(since), type: 0, maxResults: 1000, token });
    for (const v of res.data.voidedPurchases ?? []) {
      if (!v.purchaseToken) continue;
      if (await applyVoidedCoinPurchase(v.purchaseToken, {
        orderId: v.orderId, voidedTimeMillis: v.voidedTimeMillis, reason: v.voidedReason, source: v.voidedSource,
      })) applied++;
      newest = Math.max(newest, Number(v.voidedTimeMillis ?? 0));
    }
    token = res.data.tokenPagination?.nextPageToken ?? undefined;
  } while (token);
  await stateRef.set({ lastVoidedTimeMillis: newest, ranAt: FieldValue.serverTimestamp(), applied }, { merge: true });
});
