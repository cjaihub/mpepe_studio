/**
 * Business balance (`pay_business_balances/{uid}`, ledger account `biz:{uid}`):
 * shop sales and scan-to-pay land here, apart from the owner's personal
 * balance. The owner withdraws from it (payWithdraw with balance: 'business')
 * or moves money to their personal balance with payMoveToPersonal.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { limit } from '../guard/protect';
import { toMajor } from '../payments/provider';
import { bucketOf, businessBalanceRef, ledgerRef, writeLedger } from './ledger';

const db = () => getFirestore();

export const payMoveToPersonal = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  await limit(uid, 'pay_move_personal', 20, 3600_000);
  const key = String(req.data?.idempotencyKey ?? '');
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(key)) throw new HttpsError('invalid-argument', 'Missing request id.');
  const currency = String(req.data?.currency ?? '').toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new HttpsError('invalid-argument', 'Choose a currency.');
  const amountMinor = Math.floor(Number(req.data?.amountMinor));
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) throw new HttpsError('invalid-argument', 'Enter an amount.');
  const txnId = `move_${crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 32)}`;

  await db().runTransaction(async (tx) => {
    const [bal, posted] = await Promise.all([tx.get(businessBalanceRef(uid)), tx.get(ledgerRef(txnId))]);
    if (posted.exists) return;
    if (bucketOf(bal.data(), currency, 'available') < amountMinor) throw new HttpsError('failed-precondition', 'Not enough in your business balance.');
    writeLedger(tx, txnId, false, 'business_to_personal', [
      { account: `biz:${uid}`, currency, amountMinor: -amountMinor, bucket: 'available' },
      { account: `user:${uid}`, currency, amountMinor, bucket: 'available' },
    ], { uid });
    tx.set(db().collection('notifications').doc(txnId), {
      userId: uid, recipientId: uid, category: 'system', priority: 'normal', type: 'payment',
      title: 'Moved to personal', body: `${currency} ${toMajor(amountMinor, currency).toLocaleString('en-US')} moved from your business to your personal balance.`,
      deepLink: '/pay', isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true, id: txnId };
});
