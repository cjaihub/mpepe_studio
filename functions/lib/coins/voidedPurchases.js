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
exports.coinVoidSweep = exports.tokenHash = void 0;
exports.applyVoidedCoinPurchase = applyVoidedCoinPurchase;
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
const crypto = __importStar(require("crypto"));
const googleapis_1 = require("googleapis");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const clawbackLogic_1 = require("./clawbackLogic");
const outbox_1 = require("../ledger/outbox");
const db = () => (0, firestore_1.getFirestore)();
const PACKAGE = 'com.oneova.app';
const tokenHash = (token) => crypto.createHash('sha256').update(token).digest('hex');
exports.tokenHash = tokenHash;
/** Applies one voided coin purchase. Returns false when it isn't a coin pack or was already applied. */
async function applyVoidedCoinPurchase(purchaseToken, info) {
    const id = (0, exports.tokenHash)(purchaseToken);
    const receiptRef = db().doc(`coin_purchases/${id}`);
    const voidRef = db().doc(`coin_voids/${id}`);
    const applied = await db().runTransaction(async (tx) => {
        var _a;
        var _b, _c, _d, _e, _f, _g, _h, _j, _k;
        const [receipt, done] = await Promise.all([tx.get(receiptRef), tx.get(voidRef)]);
        if (done.exists || !receipt.exists)
            return null;
        const uid = String(receipt.get('uid'));
        const coins = Number((_b = receipt.get('coins')) !== null && _b !== void 0 ? _b : 0);
        const wallet = db().doc(`wallets/${uid}`);
        const w = await tx.get(wallet);
        const plan = (0, clawbackLogic_1.clawbackPlan)(Number((_c = w.get('balanceCoins')) !== null && _c !== void 0 ? _c : 0), coins);
        tx.set(wallet, Object.assign(Object.assign({ balanceCoins: firestore_1.FieldValue.increment(-plan.takeFromBalance) }, (plan.addDebt > 0 ? { coinDebt: firestore_1.FieldValue.increment(plan.addDebt) } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
        tx.set(wallet.collection('ledger').doc(`void_${id.slice(0, 24)}`), {
            amount: -plan.takeFromBalance, type: 'coin_purchase_voided', debt: plan.addDebt, coins,
            referenceId: (_e = (_d = info.orderId) !== null && _d !== void 0 ? _d : receipt.get('orderId')) !== null && _e !== void 0 ? _e : id, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        if (plan.takeFromBalance + plan.addDebt > 0) {
            (0, outbox_1.ledgerOutbox)(tx, `void_${id}`, 'coin_void', { uid, take_from_balance: plan.takeFromBalance, add_debt: plan.addDebt, order_id: (_f = info.orderId) !== null && _f !== void 0 ? _f : null });
        }
        tx.update(receiptRef, { voided: true, voidedAt: firestore_1.FieldValue.serverTimestamp() });
        tx.set(voidRef, Object.assign(Object.assign({ uid, coins }, plan), { orderId: (_g = info.orderId) !== null && _g !== void 0 ? _g : null, reason: (_h = info.reason) !== null && _h !== void 0 ? _h : null, source: (_j = info.source) !== null && _j !== void 0 ? _j : null, voidedTimeMillis: info.voidedTimeMillis != null ? Number(info.voidedTimeMillis) : null, createdAt: firestore_1.FieldValue.serverTimestamp() }));
        return { uid, debt: plan.addDebt, purchasedAt: (_k = (_a = receipt.get('createdAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _k !== void 0 ? _k : 0 };
    });
    if (!applied)
        return false;
    logger.warn('coin purchase voided', { uid: applied.uid, debt: applied.debt });
    if (applied.debt <= 0)
        return true;
    // The coins were already spent: hold payouts for the buyer and everyone they gifted since.
    const sent = await db().collection(`wallets/${applied.uid}/ledger`)
        .where('createdAt', '>=', firestore_1.Timestamp.fromMillis(applied.purchasedAt)).orderBy('createdAt').limit(500).get();
    const recipients = (0, clawbackLogic_1.giftRecipients)(sent.docs.map((d) => { var _a; var _b; return ({
        type: d.get('type'), toUid: d.get('toUid'), amount: d.get('amount'),
        createdAtMs: (_b = (_a = d.get('createdAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : null,
    }); }), applied.purchasedAt);
    const batch = db().batch();
    for (const uid of [applied.uid, ...recipients.keys()]) {
        batch.set(db().doc(`payout_holds/${uid}`), {
            uid, reasons: firestore_1.FieldValue.arrayUnion(uid === applied.uid ? 'own_coin_purchase_refunded' : 'gift_source_refunded'),
            sources: firestore_1.FieldValue.arrayUnion(applied.uid), updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    await batch.commit();
    return true;
}
/** Backstop for missed notifications: reads Play's voided list since the last run. */
exports.coinVoidSweep = (0, scheduler_1.onSchedule)('every 6 hours', async () => {
    var _a;
    var _b, _c, _d, _e;
    const stateRef = db().doc('ops_state/play_voided');
    const since = Number((_b = (await stateRef.get()).get('lastVoidedTimeMillis')) !== null && _b !== void 0 ? _b : Date.now() - 30 * 86400000);
    const auth = new googleapis_1.google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
    const api = googleapis_1.google.androidpublisher({ version: 'v3', auth });
    let token;
    let newest = since;
    let applied = 0;
    do {
        const res = await api.purchases.voidedpurchases.list({ packageName: PACKAGE, startTime: String(since), type: 0, maxResults: 1000, token });
        for (const v of (_c = res.data.voidedPurchases) !== null && _c !== void 0 ? _c : []) {
            if (!v.purchaseToken)
                continue;
            if (await applyVoidedCoinPurchase(v.purchaseToken, {
                orderId: v.orderId, voidedTimeMillis: v.voidedTimeMillis, reason: v.voidedReason, source: v.voidedSource,
            }))
                applied++;
            newest = Math.max(newest, Number((_d = v.voidedTimeMillis) !== null && _d !== void 0 ? _d : 0));
        }
        token = (_e = (_a = res.data.tokenPagination) === null || _a === void 0 ? void 0 : _a.nextPageToken) !== null && _e !== void 0 ? _e : undefined;
    } while (token);
    await stateRef.set({ lastVoidedTimeMillis: newest, ranAt: firestore_1.FieldValue.serverTimestamp(), applied }, { merge: true });
});
//# sourceMappingURL=voidedPurchases.js.map