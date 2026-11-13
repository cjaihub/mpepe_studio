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
exports.payMoveToPersonal = void 0;
/**
 * Business balance (`pay_business_balances/{uid}`, ledger account `biz:{uid}`):
 * shop sales and scan-to-pay land here, apart from the owner's personal
 * balance. The owner withdraws from it (payWithdraw with balance: 'business')
 * or moves money to their personal balance with payMoveToPersonal.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("../guard/protect");
const provider_1 = require("../payments/provider");
const ledger_1 = require("./ledger");
const db = () => (0, firestore_1.getFirestore)();
exports.payMoveToPersonal = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    var _e, _f;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    await (0, protect_1.limit)(uid, 'pay_move_personal', 20, 3600000);
    const key = String((_e = (_b = req.data) === null || _b === void 0 ? void 0 : _b.idempotencyKey) !== null && _e !== void 0 ? _e : '');
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(key))
        throw new https_1.HttpsError('invalid-argument', 'Missing request id.');
    const currency = String((_f = (_c = req.data) === null || _c === void 0 ? void 0 : _c.currency) !== null && _f !== void 0 ? _f : '').toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency))
        throw new https_1.HttpsError('invalid-argument', 'Choose a currency.');
    const amountMinor = Math.floor(Number((_d = req.data) === null || _d === void 0 ? void 0 : _d.amountMinor));
    if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0)
        throw new https_1.HttpsError('invalid-argument', 'Enter an amount.');
    const txnId = `move_${crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 32)}`;
    await db().runTransaction(async (tx) => {
        const [bal, posted] = await Promise.all([tx.get((0, ledger_1.businessBalanceRef)(uid)), tx.get((0, ledger_1.ledgerRef)(txnId))]);
        if (posted.exists)
            return;
        if ((0, ledger_1.bucketOf)(bal.data(), currency, 'available') < amountMinor)
            throw new https_1.HttpsError('failed-precondition', 'Not enough in your business balance.');
        (0, ledger_1.writeLedger)(tx, txnId, false, 'business_to_personal', [
            { account: `biz:${uid}`, currency, amountMinor: -amountMinor, bucket: 'available' },
            { account: `user:${uid}`, currency, amountMinor, bucket: 'available' },
        ], { uid });
        tx.set(db().collection('notifications').doc(txnId), {
            userId: uid, recipientId: uid, category: 'system', priority: 'normal', type: 'payment',
            title: 'Moved to personal', body: `${currency} ${(0, provider_1.toMajor)(amountMinor, currency).toLocaleString('en-US')} moved from your business to your personal balance.`,
            deepLink: '/pay', isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return { ok: true, id: txnId };
});
//# sourceMappingURL=businessBalance.js.map