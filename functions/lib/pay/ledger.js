"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.balanceRefOf = exports.businessBalanceRef = exports.balanceRef = exports.ledgerRef = void 0;
exports.writeLedger = writeLedger;
exports.bucketOf = bucketOf;
/**
 * Oneova Pay double-entry ledger.
 *
 *   pay_ledger/{txnId}     one posting: lines that sum to zero per currency.
 *                          The id is the idempotency key: a posting is written
 *                          once, so a retried webhook can't move money twice.
 *   pay_balances/{uid}     a user's balances per currency:
 *                          { KES: { available, pending, locked }, ... }
 *                          Only the server writes either collection.
 *
 * Firestore transactions need every read before any write, so callers read
 * `ledgerRef(txnId)` first and pass `exists` to `writeLedger`.
 */
const firestore_1 = require("firebase-admin/firestore");
const payLogic_1 = require("./payLogic");
const outbox_1 = require("../ledger/outbox");
const db = () => (0, firestore_1.getFirestore)();
const ledgerRef = (txnId) => db().doc(`pay_ledger/${txnId}`);
exports.ledgerRef = ledgerRef;
const balanceRef = (uid) => db().doc(`pay_balances/${uid}`);
exports.balanceRef = balanceRef;
/** A business owner's business balance (shop sales, scan to pay). */
const businessBalanceRef = (uid) => db().doc(`pay_business_balances/${uid}`);
exports.businessBalanceRef = businessBalanceRef;
const balanceRefOf = (kind, uid) => (kind === 'business' ? (0, exports.businessBalanceRef)(uid) : (0, exports.balanceRef)(uid));
exports.balanceRefOf = balanceRefOf;
/**
 * Writes the posting (when it isn't there yet) and moves user balances.
 * Returns false when it already existed (nothing written).
 */
function writeLedger(tx, txnId, exists, kind, lines, meta = {}) {
    var _a;
    if (exists)
        return false;
    if (!(0, payLogic_1.ledgerBalanced)(lines))
        throw new Error(`unbalanced ledger posting ${txnId}`);
    tx.set((0, exports.ledgerRef)(txnId), Object.assign(Object.assign({ kind, lines: lines.map((l) => { var _a; return ({ account: l.account, currency: l.currency, amountMinor: l.amountMinor, bucket: (_a = l.bucket) !== null && _a !== void 0 ? _a : null }); }) }, meta), { createdAt: firestore_1.FieldValue.serverTimestamp() }));
    // Mirror to the Postgres ledger (the source of truth) in the same transaction.
    (0, outbox_1.ledgerOutbox)(tx, `pay_${txnId}`, 'pay_posting', {
        kind, lines: lines.map((l) => { var _a; return ({ account: l.account, currency: l.currency, amountMinor: l.amountMinor, bucket: (_a = l.bucket) !== null && _a !== void 0 ? _a : null }); }),
    });
    for (const l of lines) {
        const uid = (0, payLogic_1.userOf)(l.account);
        const biz = (0, payLogic_1.businessOf)(l.account);
        if ((!uid && !biz) || l.amountMinor === 0)
            continue;
        tx.set(uid ? (0, exports.balanceRef)(uid) : (0, exports.businessBalanceRef)(biz), {
            [l.currency]: { [(_a = l.bucket) !== null && _a !== void 0 ? _a : 'available']: firestore_1.FieldValue.increment(l.amountMinor) },
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    return true;
}
/** A user's bucket balance from a `pay_balances` snapshot (0 when absent). */
function bucketOf(data, currency, bucket) {
    var _a;
    const v = (_a = data === null || data === void 0 ? void 0 : data[currency]) === null || _a === void 0 ? void 0 : _a[bucket];
    return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}
//# sourceMappingURL=ledger.js.map