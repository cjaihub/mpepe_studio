"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsGift = void 0;
/**
 * LIVE STUDIO v2 — `lsGift({streamId, giftId, qty})`.
 * One transaction: debit the sender's `wallets/{uid}.balanceCoins`, credit the
 * host's `pendingCoins` (HOST_SHARE), write both ledger entries, bump the
 * stream's gift totals and the sender's top-gifter row, and push the gift to
 * `studio/gifts` (recent list every viewer animates). Pure rules: gift_logic.ts.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const social_logic_1 = require("./social_logic");
const gift_logic_1 = require("./gift_logic");
exports.lsGift = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const data = (req.data && typeof req.data === 'object' ? req.data : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    let gift;
    try {
        gift = (0, gift_logic_1.parseGift)(data);
    }
    catch (e) {
        if (e instanceof gift_logic_1.GiftError)
            throw new https_1.HttpsError('invalid-argument', e.message);
        throw e;
    }
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    if (uid === state.hostId)
        throw new https_1.HttpsError('failed-precondition', 'You cannot send gifts to your own live.');
    if (await (0, shared_1.isBlocked)(streamId, uid))
        throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
    await (0, shared_1.rateLimit)(streamId, uid, 'gift', 10, 10000);
    const { total, hostCoins } = (0, gift_logic_1.giftPrice)(gift.giftId, gift.qty);
    const [member, user] = await Promise.all([
        (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`).get(),
        (0, shared_1.db)().doc(`users/${uid}`).get(),
    ]);
    const m = member.data();
    const u = user.exists ? user.data() : undefined;
    const name = (m === null || m === void 0 ? void 0 : m.displayName) || (0, social_logic_1.displayNameOf)(u);
    const avatarUrl = (m === null || m === void 0 ? void 0 : m.avatarUrl) || (0, social_logic_1.avatarOf)(u);
    const now = Date.now();
    const giftDocId = (0, gift_logic_1.giftId)(uid, data.requestId, now);
    const senderWallet = (0, shared_1.db)().doc(`wallets/${uid}`);
    const hostWallet = (0, shared_1.db)().doc(`wallets/${state.hostId}`);
    const feed = (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}/studio/gifts`);
    let duplicate = false;
    const balance = await (0, shared_1.db)().runTransaction(async (tx) => {
        var _a;
        duplicate = false;
        const [w, f, dup] = await Promise.all([tx.get(senderWallet), tx.get(feed), tx.get(senderWallet.collection('ledger').doc(`gift_${giftDocId}`))]);
        const have = Number((_a = w.get('balanceCoins')) !== null && _a !== void 0 ? _a : 0);
        // Same requestId again (a retry): it was already sent, charge nothing.
        if (dup.exists) {
            duplicate = true;
            return have;
        }
        if (!Number.isFinite(have) || have < total) {
            throw new https_1.HttpsError('failed-precondition', `Not enough coins. This gift costs ${total}.`);
        }
        const recent = { id: giftDocId, uid, name, avatarUrl, giftId: gift.giftId, qty: gift.qty, coins: total, atMs: now };
        tx.set(senderWallet, { balanceCoins: have - total, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(senderWallet.collection('ledger').doc(`gift_${giftDocId}`), {
            amount: -total,
            type: 'live_gift_sent',
            referenceId: streamId,
            giftId: gift.giftId,
            qty: gift.qty,
            toUid: state.hostId,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(hostWallet, { pendingCoins: firestore_1.FieldValue.increment(hostCoins), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(hostWallet.collection('ledger').doc(`gift_${giftDocId}`), {
            amount: hostCoins,
            type: 'live_gift_received',
            status: 'pending',
            referenceId: streamId,
            giftId: gift.giftId,
            qty: gift.qty,
            fromUid: uid,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(feed, { recent: (0, gift_logic_1.pushRecent)(f.get('recent'), recent), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set((0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}/studio_gift_totals/${uid}`), { uid, name, avatarUrl, coins: firestore_1.FieldValue.increment(total), lastAtMs: now }, { merge: true });
        tx.set((0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`), { giftCoins: firestore_1.FieldValue.increment(total), giftCount: firestore_1.FieldValue.increment(gift.qty) }, { merge: true });
        // Gifter level (coins/coinEconomy.ts GIFTER_LEVELS).
        tx.set((0, shared_1.db)().doc(`gifter_stats/${uid}`), { uid, lifetimeCoins: firestore_1.FieldValue.increment(total), giftsSent: firestore_1.FieldValue.increment(gift.qty), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        return have - total;
    });
    if (!duplicate)
        await (0, shared_1.broadcast)(streamId, 'studio.gift', { v: 1, type: 'gift', uid, name, giftId: gift.giftId, qty: gift.qty, ts: now }, { lossy: true });
    return { ok: true, balanceCoins: balance, giftId: gift.giftId, label: gift_logic_1.GIFT_CATALOG[gift.giftId].label, coins: total };
});
//# sourceMappingURL=gifts.js.map