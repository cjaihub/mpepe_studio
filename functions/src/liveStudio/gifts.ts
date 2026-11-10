/**
 * LIVE STUDIO v2 — `lsGift({streamId, giftId, qty})`.
 * One transaction: debit the sender's `wallets/{uid}.balanceCoins`, credit the
 * host's `pendingCoins` (HOST_SHARE), write both ledger entries, bump the
 * stream's gift totals and the sender's top-gifter row, and push the gift to
 * `studio/gifts` (recent list every viewer animates). Pure rules: gift_logic.ts.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { Paths, StageMember } from './contracts';
import { LIVEKIT_SECRETS, broadcast, db, isBlocked, loadState, rateLimit, requireLive, requireString, requireUid } from './shared';
import { displayNameOf, avatarOf } from './social_logic';
import { GIFT_CATALOG, GiftError, RecentGift, giftId, giftPrice, parseGift, pushRecent } from './gift_logic';

export const lsGift = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = (req.data && typeof req.data === 'object' ? req.data : {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  let gift;
  try {
    gift = parseGift(data);
  } catch (e) {
    if (e instanceof GiftError) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }
  const state = await loadState(streamId);
  requireLive(state);
  if (uid === state.hostId) throw new HttpsError('failed-precondition', 'You cannot send gifts to your own live.');
  if (await isBlocked(streamId, uid)) throw new HttpsError('permission-denied', 'You are blocked from this live.');
  await rateLimit(streamId, uid, 'gift', 10, 10_000);

  const { total, hostCoins } = giftPrice(gift.giftId, gift.qty);
  const [member, user] = await Promise.all([
    db().doc(`${Paths.members(streamId)}/${uid}`).get(),
    db().doc(`users/${uid}`).get(),
  ]);
  const m = member.data() as Partial<StageMember> | undefined;
  const u = user.exists ? (user.data() as Record<string, unknown>) : undefined;
  const name = m?.displayName || displayNameOf(u);
  const avatarUrl = m?.avatarUrl || avatarOf(u);
  const now = Date.now();
  const giftDocId = giftId(uid, data.requestId, now);

  const senderWallet = db().doc(`wallets/${uid}`);
  const hostWallet = db().doc(`wallets/${state.hostId}`);
  const feed = db().doc(`${Paths.streams}/${streamId}/studio/gifts`);
  let duplicate = false;
  const balance = await db().runTransaction(async (tx) => {
    duplicate = false;
    const [w, f, dup] = await Promise.all([tx.get(senderWallet), tx.get(feed), tx.get(senderWallet.collection('ledger').doc(`gift_${giftDocId}`))]);
    const have = Number(w.get('balanceCoins') ?? 0);
    // Same requestId again (a retry): it was already sent, charge nothing.
    if (dup.exists) {
      duplicate = true;
      return have;
    }
    if (!Number.isFinite(have) || have < total) {
      throw new HttpsError('failed-precondition', `Not enough coins. This gift costs ${total}.`);
    }
    const recent: RecentGift = { id: giftDocId, uid, name, avatarUrl, giftId: gift.giftId, qty: gift.qty, coins: total, atMs: now };
    tx.set(senderWallet, { balanceCoins: have - total, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(senderWallet.collection('ledger').doc(`gift_${giftDocId}`), {
      amount: -total,
      type: 'live_gift_sent',
      referenceId: streamId,
      giftId: gift.giftId,
      qty: gift.qty,
      toUid: state.hostId,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(hostWallet, { pendingCoins: FieldValue.increment(hostCoins), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(hostWallet.collection('ledger').doc(`gift_${giftDocId}`), {
      amount: hostCoins,
      type: 'live_gift_received',
      status: 'pending',
      referenceId: streamId,
      giftId: gift.giftId,
      qty: gift.qty,
      fromUid: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(feed, { recent: pushRecent(f.get('recent'), recent), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(
      db().doc(`${Paths.streams}/${streamId}/studio_gift_totals/${uid}`),
      { uid, name, avatarUrl, coins: FieldValue.increment(total), lastAtMs: now },
      { merge: true },
    );
    tx.set(
      db().doc(`${Paths.streams}/${streamId}`),
      { giftCoins: FieldValue.increment(total), giftCount: FieldValue.increment(gift.qty) },
      { merge: true },
    );
    // Gifter level (coins/coinEconomy.ts GIFTER_LEVELS).
    tx.set(
      db().doc(`gifter_stats/${uid}`),
      { uid, lifetimeCoins: FieldValue.increment(total), giftsSent: FieldValue.increment(gift.qty), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return have - total;
  });

  if (!duplicate) await broadcast(
    streamId,
    'studio.gift',
    { v: 1, type: 'gift', uid, name, giftId: gift.giftId, qty: gift.qty, ts: now } as never,
    { lossy: true },
  );
  return { ok: true, balanceCoins: balance, giftId: gift.giftId, label: GIFT_CATALOG[gift.giftId].label, coins: total };
});
