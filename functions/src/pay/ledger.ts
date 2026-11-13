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
import { getFirestore, FieldValue, Transaction } from 'firebase-admin/firestore';
import { LedgerLine, ledgerBalanced, userOf } from './payLogic';

const db = () => getFirestore();

export const ledgerRef = (txnId: string) => db().doc(`pay_ledger/${txnId}`);
export const balanceRef = (uid: string) => db().doc(`pay_balances/${uid}`);

/**
 * Writes the posting (when it isn't there yet) and moves user balances.
 * Returns false when it already existed (nothing written).
 */
export function writeLedger(
  tx: Transaction,
  txnId: string,
  exists: boolean,
  kind: string,
  lines: LedgerLine[],
  meta: Record<string, unknown> = {},
): boolean {
  if (exists) return false;
  if (!ledgerBalanced(lines)) throw new Error(`unbalanced ledger posting ${txnId}`);
  tx.set(ledgerRef(txnId), {
    kind,
    lines: lines.map((l) => ({ account: l.account, currency: l.currency, amountMinor: l.amountMinor, bucket: l.bucket ?? null })),
    ...meta,
    createdAt: FieldValue.serverTimestamp(),
  });
  for (const l of lines) {
    const uid = userOf(l.account);
    if (!uid || l.amountMinor === 0) continue;
    tx.set(balanceRef(uid), {
      [l.currency]: { [l.bucket ?? 'available']: FieldValue.increment(l.amountMinor) },
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return true;
}

/** A user's bucket balance from a `pay_balances` snapshot (0 when absent). */
export function bucketOf(data: FirebaseFirestore.DocumentData | undefined, currency: string, bucket: 'available' | 'pending' | 'locked'): number {
  const v = data?.[currency]?.[bucket];
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}
