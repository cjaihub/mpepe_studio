"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendUserGift = exports.verifyCoinPurchase = exports.GIFTER_LEVELS = exports.COIN_PACKS = void 0;
exports.gifterLevel = gifterLevel;
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
const crypto = __importStar(require("crypto"));
const googleapis_1 = require("googleapis");
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const gift_logic_1 = require("../liveStudio/gift_logic");
const db = () => (0, firestore_1.getFirestore)();
const PACKAGE = 'com.oneova.app';
/** Play product id → coins credited (bonus included). */
exports.COIN_PACKS = {
    coins_70: 70,
    coins_350: 350,
    coins_700: 720,
    coins_1400: 1470,
    coins_3500: 3750,
    coins_7000: 7700,
    coins_17500: 19600,
};
/** Lifetime coins gifted needed for each level (index = level). */
exports.GIFTER_LEVELS = [0, 50, 200, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000];
function gifterLevel(lifetimeCoins) {
    let level = 0;
    for (let i = 0; i < exports.GIFTER_LEVELS.length; i++)
        if (lifetimeCoins >= exports.GIFTER_LEVELS[i])
            level = i;
    return level;
}
function publisher() {
    const auth = new googleapis_1.google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
    return googleapis_1.google.androidpublisher({ version: 'v3', auth });
}
exports.verifyCoinPurchase = (0, https_1.onCall)({ timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c;
    var _d, _e, _f, _g;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const productId = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.productId) !== null && _d !== void 0 ? _d : '');
    const token = String((_e = (_c = req.data) === null || _c === void 0 ? void 0 : _c.purchaseToken) !== null && _e !== void 0 ? _e : '');
    const coins = exports.COIN_PACKS[productId];
    if (!coins || !token || token.length > 4096)
        throw new https_1.HttpsError('invalid-argument', 'Unknown coin pack.');
    const tokenId = crypto.createHash('sha256').update(token).digest('hex');
    const receiptRef = db().collection('coin_purchases').doc(tokenId);
    const existing = await receiptRef.get();
    if (existing.exists) {
        if (existing.get('uid') !== uid)
            throw new https_1.HttpsError('permission-denied', 'This purchase belongs to another account.');
        const w = await db().doc(`wallets/${uid}`).get();
        return { ok: true, alreadyCredited: true, coins, balanceCoins: Number((_f = w.get('balanceCoins')) !== null && _f !== void 0 ? _f : 0) };
    }
    let purchase;
    try {
        purchase = (await publisher().purchases.products.get({ packageName: PACKAGE, productId, token })).data;
    }
    catch (e) {
        logger.error('play purchase lookup failed', productId, (_g = e === null || e === void 0 ? void 0 : e.message) !== null && _g !== void 0 ? _g : e);
        throw new https_1.HttpsError('unavailable', 'We couldn’t confirm this purchase with Google Play yet. It will be added as soon as it’s confirmed.');
    }
    // purchaseState: 0 purchased, 1 cancelled, 2 pending.
    if (purchase.purchaseState === 2)
        throw new https_1.HttpsError('failed-precondition', 'Your payment is still pending. Coins will be added when it completes.');
    if (purchase.purchaseState !== 0)
        throw new https_1.HttpsError('failed-precondition', 'This purchase was cancelled.');
    if (purchase.obfuscatedExternalAccountId && purchase.obfuscatedExternalAccountId !== uid) {
        throw new https_1.HttpsError('permission-denied', 'This purchase belongs to another account.');
    }
    const wallet = db().doc(`wallets/${uid}`);
    const balance = await db().runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f;
        const [r, w] = await Promise.all([tx.get(receiptRef), tx.get(wallet)]);
        if (r.exists)
            return Number((_a = w.get('balanceCoins')) !== null && _a !== void 0 ? _a : 0);
        const now = Number((_b = w.get('balanceCoins')) !== null && _b !== void 0 ? _b : 0) + coins;
        tx.set(receiptRef, {
            uid, productId, coins, orderId: (_c = purchase.orderId) !== null && _c !== void 0 ? _c : null, regionCode: (_d = purchase.regionCode) !== null && _d !== void 0 ? _d : null,
            purchaseTimeMillis: (_e = purchase.purchaseTimeMillis) !== null && _e !== void 0 ? _e : null, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(wallet, { balanceCoins: now, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(wallet.collection('ledger').doc(`play_${tokenId.slice(0, 24)}`), {
            amount: coins, type: 'coin_purchase', provider: 'google_play', productId,
            referenceId: (_f = purchase.orderId) !== null && _f !== void 0 ? _f : tokenId, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return now;
    });
    // Consumable: lets the person buy the same pack again.
    if (purchase.consumptionState !== 1) {
        await publisher().purchases.products.consume({ packageName: PACKAGE, productId, token }).catch((e) => { var _a; return logger.warn('play consume failed (client will retry)', (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e); });
    }
    return { ok: true, coins, balanceCoins: balance };
});
/**
 * Send a gift to someone outside a live (profile, chat). The receiver gets
 * HOST_SHARE of the coins as pendingCoins, like live gifts.
 */
exports.sendUserGift = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d, _e, _f, _g;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const toUid = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.toUid) !== null && _d !== void 0 ? _d : '');
    if (!toUid || toUid === uid || toUid.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Choose who to gift.');
    let gift;
    try {
        gift = (0, gift_logic_1.parseGift)(req.data);
    }
    catch (e) {
        if (e instanceof gift_logic_1.GiftError)
            throw new https_1.HttpsError('invalid-argument', e.message);
        throw e;
    }
    const [blocked, receiver] = await Promise.all([
        db().doc(`relationships/${toUid}_${uid}`).get(),
        db().doc(`users/${toUid}`).get(),
    ]);
    if (!receiver.exists)
        throw new https_1.HttpsError('not-found', 'This account no longer exists.');
    if (blocked.get('status') === 'blocked')
        throw new https_1.HttpsError('permission-denied', 'You can’t send gifts to this person.');
    const { total } = (0, gift_logic_1.giftPrice)(gift.giftId, gift.qty);
    // Person-to-person gifts round up, so even a 1-coin gift reaches them.
    const hostCoins = Math.ceil(total * gift_logic_1.HOST_SHARE);
    const message = typeof ((_c = req.data) === null || _c === void 0 ? void 0 : _c.message) === 'string' ? req.data.message.trim().slice(0, 120) : '';
    const me = (_e = (await db().doc(`users/${uid}`).get()).data()) !== null && _e !== void 0 ? _e : {};
    const myAvatar = (_f = [me.avatarUrl, me.photoUrl, me.photoURL].find((v) => typeof v === 'string' && v.startsWith('http'))) !== null && _f !== void 0 ? _f : '';
    const myName = String(me.fullName || me.displayName || me.username || 'Someone');
    const id = `${uid}_${Date.now().toString(36)}`;
    const senderWallet = db().doc(`wallets/${uid}`);
    const receiverWallet = db().doc(`wallets/${toUid}`);
    const balance = await db().runTransaction(async (tx) => {
        var _a;
        const w = await tx.get(senderWallet);
        const have = Number((_a = w.get('balanceCoins')) !== null && _a !== void 0 ? _a : 0);
        if (have < total)
            throw new https_1.HttpsError('failed-precondition', `Not enough coins. This gift costs ${total}.`);
        tx.set(senderWallet, { balanceCoins: have - total, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(senderWallet.collection('ledger').doc(`ugift_${id}`), {
            amount: -total, type: 'user_gift_sent', giftId: gift.giftId, qty: gift.qty, toUid, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(receiverWallet, { pendingCoins: firestore_1.FieldValue.increment(hostCoins), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(receiverWallet.collection('ledger').doc(`ugift_${id}`), {
            amount: hostCoins, type: 'user_gift_received', status: 'pending', giftId: gift.giftId, qty: gift.qty, fromUid: uid, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(db().doc(`gifter_stats/${uid}`), { uid, lifetimeCoins: firestore_1.FieldValue.increment(total), giftsSent: firestore_1.FieldValue.increment(gift.qty), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        tx.set(db().doc(`gifter_stats/${toUid}`), { uid: toUid, receivedCoins: firestore_1.FieldValue.increment(total), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        // Live gift drop: the receiver's app animates it the moment it lands.
        tx.set(db().doc(`users/${toUid}/gift_inbox/${id}`), {
            fromUid: uid, fromName: myName, fromAvatar: myAvatar, giftId: gift.giftId,
            label: gift_logic_1.GIFT_CATALOG[gift.giftId].label, qty: gift.qty, coins: total, received: hostCoins,
            message, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(db().collection('notifications').doc(`ugift_${id}`), {
            userId: toUid, recipientId: toUid, actorId: uid, category: 'reaction', priority: 'normal', type: 'gift',
            title: `${myName} sent you ${gift.qty > 1 ? `${gift.qty} × ` : 'a '}${gift_logic_1.GIFT_CATALOG[gift.giftId].label}`,
            body: message ? `“${message}” · +${hostCoins} coins` : `+${hostCoins} coins for you. Say thanks!`, deepLink: `/profile/${uid}`, isRead: false,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return have - total;
    });
    const stats = await db().doc(`gifter_stats/${uid}`).get();
    const level = gifterLevel(Number((_g = stats.get('lifetimeCoins')) !== null && _g !== void 0 ? _g : 0));
    if (stats.get('level') !== level)
        await stats.ref.set({ level }, { merge: true });
    return { ok: true, balanceCoins: balance, coins: total, received: hostCoins, gifterLevel: level, share: gift_logic_1.HOST_SHARE };
});
//# sourceMappingURL=coinEconomy.js.map