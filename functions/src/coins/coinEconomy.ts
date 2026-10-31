/**
 * Oneova Coins: buying them through Google Play Billing, and gifting them
 * person to person outside a live.
 *
 * Coins are a digital currency, so on Android they must be sold with Google
 * Play Billing (not Stripe or mobile money). The app buys a consumable
 * product; `verifyCoinPurchase` checks the purchase token with the Google Play
 * Developer API, credits `wallets/{uid}.balanceCoins` exactly once per token,
 * writes the ledger entry and consumes the purchase.
 *
 * Setup: Play Console → Users and permissions → invite the functions service
 * account (90836164478-compute@developer.gserviceaccount.com) with "View
 * financial data" and "Manage orders and subscriptions"; create the in-app
 * products listed in COIN_PACKS (consumable, active).
 *
 * Gifter level: every gift (live or person to person) adds its coins to
 * `gifter_stats/{uid}.lifetimeCoins`; the level is derived from it with
 * GIFTER_LEVELS (same table in lib/backend/coins/gifter_level.dart).
 */
import * as crypto from 'crypto';
import { google } from 'googleapis';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { GIFT_CATALOG, HOST_SHARE, parseGift, giftPrice, GiftError } from '../liveStudio/gift_logic';

const db = () => getFirestore();
const PACKAGE = 'com.oneova.app';

/** Play product id → coins credited (bonus included). */
export const COIN_PACKS: Record<string, number> = {
  coins_10: 10,
  coins_70: 70,
  coins_350: 350,
  coins_700: 720,
  coins_1400: 1470,
  coins_3500: 3750,
  coins_7000: 7700,
  coins_17500: 19600,
};

/** Lifetime coins gifted needed for each level (index = level). */
export const GIFTER_LEVELS = [0, 50, 200, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000];

export function gifterLevel(lifetimeCoins: number): number {
  let level = 0;
  for (let i = 0; i < GIFTER_LEVELS.length; i++) if (lifetimeCoins >= GIFTER_LEVELS[i]) level = i;
  return level;
}

function publisher() {
  const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  return google.androidpublisher({ version: 'v3', auth });
}

export const verifyCoinPurchase = onCall({ timeoutSeconds: 60 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const productId = String(req.data?.productId ?? '');
  const token = String(req.data?.purchaseToken ?? '');
  const coins = COIN_PACKS[productId];
  if (!coins || !token || token.length > 4096) throw new HttpsError('invalid-argument', 'Unknown coin pack.');

  const tokenId = crypto.createHash('sha256').update(token).digest('hex');
  const receiptRef = db().collection('coin_purchases').doc(tokenId);
  const existing = await receiptRef.get();
  if (existing.exists) {
    if (existing.get('uid') !== uid) throw new HttpsError('permission-denied', 'This purchase belongs to another account.');
    const w = await db().doc(`wallets/${uid}`).get();
    return { ok: true, alreadyCredited: true, coins, balanceCoins: Number(w.get('balanceCoins') ?? 0) };
  }

  let purchase;
  try {
    purchase = (await publisher().purchases.products.get({ packageName: PACKAGE, productId, token })).data;
  } catch (e: any) {
    logger.error('play purchase lookup failed', productId, e?.message ?? e);
    throw new HttpsError('unavailable', 'We couldn’t confirm this purchase with Google Play yet. It will be added as soon as it’s confirmed.');
  }
  // purchaseState: 0 purchased, 1 cancelled, 2 pending.
  if (purchase.purchaseState === 2) throw new HttpsError('failed-precondition', 'Your payment is still pending. Coins will be added when it completes.');
  if (purchase.purchaseState !== 0) throw new HttpsError('failed-precondition', 'This purchase was cancelled.');
  if (purchase.obfuscatedExternalAccountId && purchase.obfuscatedExternalAccountId !== uid) {
    throw new HttpsError('permission-denied', 'This purchase belongs to another account.');
  }

  const wallet = db().doc(`wallets/${uid}`);
  const balance = await db().runTransaction(async (tx) => {
    const [r, w] = await Promise.all([tx.get(receiptRef), tx.get(wallet)]);
    if (r.exists) return Number(w.get('balanceCoins') ?? 0);
    const now = Number(w.get('balanceCoins') ?? 0) + coins;
    tx.set(receiptRef, {
      uid, productId, coins, orderId: purchase.orderId ?? null, regionCode: purchase.regionCode ?? null,
      purchaseTimeMillis: purchase.purchaseTimeMillis ?? null, createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(wallet, { balanceCoins: now, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(wallet.collection('ledger').doc(`play_${tokenId.slice(0, 24)}`), {
      amount: coins, type: 'coin_purchase', provider: 'google_play', productId,
      referenceId: purchase.orderId ?? tokenId, createdAt: FieldValue.serverTimestamp(),
    });
    return now;
  });

  // Consumable: lets the person buy the same pack again.
  if (purchase.consumptionState !== 1) {
    await publisher().purchases.products.consume({ packageName: PACKAGE, productId, token }).catch((e) =>
      logger.warn('play consume failed (client will retry)', e?.message ?? e));
  }
  return { ok: true, coins, balanceCoins: balance };
});

/**
 * Send a gift to someone outside a live (profile, chat). The receiver gets
 * HOST_SHARE of the coins as pendingCoins, like live gifts.
 */
export const sendUserGift = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const toUid = String(req.data?.toUid ?? '');
  if (!toUid || toUid === uid || toUid.includes('/')) throw new HttpsError('invalid-argument', 'Choose who to gift.');
  let gift;
  try {
    gift = parseGift(req.data);
  } catch (e) {
    if (e instanceof GiftError) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }
  const [blocked, receiver] = await Promise.all([
    db().doc(`relationships/${toUid}_${uid}`).get(),
    db().doc(`users/${toUid}`).get(),
  ]);
  if (!receiver.exists) throw new HttpsError('not-found', 'This account no longer exists.');
  if (blocked.get('status') === 'blocked') throw new HttpsError('permission-denied', 'You can’t send gifts to this person.');

  const { total } = giftPrice(gift.giftId, gift.qty);
  // Person-to-person gifts round up, so even a 1-coin gift reaches them.
  const hostCoins = Math.ceil(total * HOST_SHARE);
  const message = typeof req.data?.message === 'string' ? req.data.message.trim().slice(0, 120) : '';
  // Gifts sent from a clip count toward that clip's insights.
  const contentId = typeof req.data?.contentId === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(req.data.contentId) ? req.data.contentId : null;
  const me = (await db().doc(`users/${uid}`).get()).data() ?? {};
  const myAvatar = [me.avatarUrl, me.photoUrl, me.photoURL].find((v) => typeof v === 'string' && v.startsWith('http')) ?? '';
  const myName = String(me.fullName || me.displayName || me.username || 'Someone');
  const id = `${uid}_${Date.now().toString(36)}`;
  const senderWallet = db().doc(`wallets/${uid}`);
  const receiverWallet = db().doc(`wallets/${toUid}`);

  const balance = await db().runTransaction(async (tx) => {
    const w = await tx.get(senderWallet);
    const have = Number(w.get('balanceCoins') ?? 0);
    if (have < total) throw new HttpsError('failed-precondition', `Not enough coins. This gift costs ${total}.`);
    tx.set(senderWallet, { balanceCoins: have - total, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(senderWallet.collection('ledger').doc(`ugift_${id}`), {
      amount: -total, type: 'user_gift_sent', giftId: gift.giftId, qty: gift.qty, toUid, createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(receiverWallet, { pendingCoins: FieldValue.increment(hostCoins), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(receiverWallet.collection('ledger').doc(`ugift_${id}`), {
      amount: hostCoins, type: 'user_gift_received', status: 'pending', giftId: gift.giftId, qty: gift.qty, fromUid: uid,
      ...(contentId ? { contentId } : {}), createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(db().doc(`gifter_stats/${uid}`), { uid, lifetimeCoins: FieldValue.increment(total), giftsSent: FieldValue.increment(gift.qty), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(db().doc(`gifter_stats/${toUid}`), { uid: toUid, receivedCoins: FieldValue.increment(total), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    // Live gift drop: the receiver's app animates it the moment it lands.
    tx.set(db().doc(`users/${toUid}/gift_inbox/${id}`), {
      fromUid: uid, fromName: myName, fromAvatar: myAvatar, giftId: gift.giftId,
      label: GIFT_CATALOG[gift.giftId].label, qty: gift.qty, coins: total, received: hostCoins,
      message, createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(db().collection('notifications').doc(`ugift_${id}`), {
      userId: toUid, recipientId: toUid, actorId: uid, category: 'reaction', priority: 'normal', type: 'gift',
      title: `${myName} sent you ${gift.qty > 1 ? `${gift.qty} × ` : 'a '}${GIFT_CATALOG[gift.giftId].label}`,
      body: message ? `“${message}” · +${hostCoins} coins` : `+${hostCoins} coins for you. Say thanks!`, deepLink: `/profile/${uid}`, isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    return have - total;
  });

  const stats = await db().doc(`gifter_stats/${uid}`).get();
  const level = gifterLevel(Number(stats.get('lifetimeCoins') ?? 0));
  if (stats.get('level') !== level) await stats.ref.set({ level }, { merge: true });
  return { ok: true, balanceCoins: balance, coins: total, received: hostCoins, gifterLevel: level, share: HOST_SHARE };
});
