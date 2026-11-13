/**
 * Oneova plans (Plus / Pro / Biz) sold as Google Play subscriptions.
 *
 *   app → verifySubscriptionPurchase  checks the token with the Play Developer
 *         API (subscriptionsv2), acknowledges it and writes `subscriptions/{uid}`
 *   Play → playBillingNotifications   Real-time developer notifications on the
 *         Pub/Sub topic `play-billing` (renewals, cancels, holds, expiry,
 *         and voided coin packs → coins/voidedPurchases.ts)
 *
 * Setup: Play Console → Monetize → Subscriptions: create `oneova_plus`,
 * `oneova_pro`, `oneova_biz`, each with base plans `monthly` and `yearly`.
 * Monetization setup → Real-time developer notifications → topic
 * projects/mpepe-2b4bd/topics/play-billing (grant
 * google-play-developer-notifications@system.gserviceaccount.com Publisher).
 */
import * as crypto from 'crypto';
import { google } from 'googleapis';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { applyVoidedCoinPurchase } from '../coins/voidedPurchases';

const db = () => getFirestore();
const PACKAGE = 'com.oneova.app';

export const PLAN_PRODUCTS: Record<string, 'plus' | 'pro' | 'biz'> = {
  oneova_plus: 'plus',
  oneova_pro: 'pro',
  oneova_biz: 'biz',
};

/** Play states that still give the person their plan. */
const ENTITLED = new Set(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED']);

function publisher() {
  const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  return google.androidpublisher({ version: 'v3', auth });
}

const tokenId = (t: string) => crypto.createHash('sha256').update(t).digest('hex');

/** Re-reads a token from Play and writes the owner's plan. Returns the plan doc. */
async function sync(token: string, claimedUid: string | null) {
  const map = db().doc(`play_sub_tokens/${tokenId(token)}`);
  const known = (await map.get()).data();
  const sub = (await publisher().purchases.subscriptionsv2.get({ packageName: PACKAGE, token })).data;
  const line = sub.lineItems?.[0];
  const productId = line?.productId ?? '';
  const plan = PLAN_PRODUCTS[productId];
  if (!plan) throw new HttpsError('invalid-argument', 'Unknown plan.');
  const owner = sub.externalAccountIdentifiers?.obfuscatedExternalAccountId || known?.uid || claimedUid;
  if (!owner) throw new HttpsError('failed-precondition', 'This purchase is not linked to an account.');
  if (claimedUid && owner !== claimedUid) throw new HttpsError('permission-denied', 'This subscription belongs to another account.');

  const expiry = line?.expiryTime ? Date.parse(line.expiryTime) : 0;
  const state = sub.subscriptionState ?? 'SUBSCRIPTION_STATE_UNSPECIFIED';
  const active = ENTITLED.has(state) && expiry > Date.now();
  const doc = {
    uid: owner,
    plan: active ? plan : 'free',
    productId,
    basePlanId: line?.offerDetails?.basePlanId ?? null,
    state,
    active,
    autoRenewing: line?.autoRenewingPlan?.autoRenewEnabled === true,
    expiresAt: expiry ? Timestamp.fromMillis(expiry) : null,
    tokenHash: tokenId(token),
    updatedAt: FieldValue.serverTimestamp(),
  };
  const batch = db().batch();
  batch.set(map, { uid: owner, token, productId, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  // A newer token (upgrade / resubscribe) wins; an old one only writes while it is the current one.
  const cur = (await db().doc(`subscriptions/${owner}`).get()).data();
  if (!cur || cur.tokenHash === doc.tokenHash || active || !cur.active) {
    batch.set(db().doc(`subscriptions/${owner}`), doc, { merge: true });
    batch.set(db().doc(`users/${owner}`), { oneovaPlan: doc.plan, oneovaPlanUpdatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  await batch.commit();

  if (sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && active) {
    await publisher().purchases.subscriptions.acknowledge({ packageName: PACKAGE, subscriptionId: productId, token, requestBody: {} })
      .catch((e) => logger.warn('play subscription acknowledge failed (will retry)', e?.message ?? e));
  }
  return doc;
}

export const verifySubscriptionPurchase = onCall({ timeoutSeconds: 60 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const token = String(req.data?.purchaseToken ?? '');
  if (!token || token.length > 4096) throw new HttpsError('invalid-argument', 'Missing purchase.');
  try {
    const d = await sync(token, uid);
    return { plan: d.plan, active: d.active, expiresAt: d.expiresAt?.toMillis() ?? null, autoRenewing: d.autoRenewing };
  } catch (e: any) {
    if (e instanceof HttpsError) throw e;
    logger.error('play subscription lookup failed', e?.message ?? e);
    throw new HttpsError('unavailable', 'We couldn’t confirm this with Google Play yet. Your plan turns on as soon as it does.');
  }
});

export const playBillingNotifications = onMessagePublished('play-billing', async (event) => {
  const msg = event.data.message.json as any;
  if (msg?.packageName !== PACKAGE) return;
  // A refunded or charged-back coin pack: take the coins back (coins/voidedPurchases.ts).
  const voided = msg?.voidedPurchaseNotification;
  if (voided?.purchaseToken) {
    await applyVoidedCoinPurchase(String(voided.purchaseToken), { orderId: voided.orderId ?? null })
      .catch((e) => logger.error('voided coin purchase failed', e?.message ?? e));
    return;
  }
  const token = msg?.subscriptionNotification?.purchaseToken;
  if (!token) return;
  try {
    await sync(String(token), null);
  } catch (e: any) {
    logger.warn('rtdn sync failed', e?.message ?? e);
  }
});
