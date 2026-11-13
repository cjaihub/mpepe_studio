/**
 * Withdrawals from the Oneova balance (`pay_balances`) — what sellers and
 * riders earn from orders — to the payout methods saved in the creator
 * payout flow (`payout_methods/{uid}/methods`, verified name from KYC).
 *
 *   app → payWithdraw     locks the amount (available → locked), sends it
 *   partner webhooks      → settlePayPayout (references start with "pp_")
 *   payBalanceReconcile   asks the partner about payouts with no answer yet
 *
 * Same safety rule as every payout: on an unclear reply nothing is returned
 * or re-sent until the partner's status says what happened.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { PaymentProvider, PayoutRequest, ProviderStatus, toMajor } from '../payments/provider';
import { POLICY } from '../payments/adapters';
import { MockProvider } from '../payments/mockProvider';
import { reconcileAction, routePayout } from '../payments/router';
import { adapterFor, payoutsConfigured } from '../creator/payouts';
import { balanceKind, balancePayoutFee, ownerAccount } from './payLogic';
import { balanceRefOf, bucketOf, ledgerRef, writeLedger } from './ledger';
import { payRuntime } from './payConfig';

const db = () => getFirestore();
const payoutRef = (id: string) => db().doc(`pay_payouts/${id}`);
export const isPayPayoutReference = (ref: string) => /^pp_[0-9a-f]{32}$/.test(ref);

function me(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

async function notify(uid: string, id: string, title: string, body: string) {
  await db().collection('notifications').doc(id).set({
    userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
    title, body, deepLink: '/biz/payouts', isRead: false, createdAt: FieldValue.serverTimestamp(),
  }).catch(() => undefined);
}

/** The adapter for a payout; the sandbox uses the mock (no money moves). */
async function adapterForPayout(p: FirebaseFirestore.DocumentData): Promise<PaymentProvider | null> {
  if (p.sandbox === true) return new MockProvider({ id: 'mock' });
  const secretRef = db().doc(`payout_method_secrets/${p.uid}_${p.methodId}`);
  return adapterFor(p.provider, await payoutsConfigured(), secretRef);
}

function payoutRequest(id: string, p: FirebaseFirestore.DocumentData, s: FirebaseFirestore.DocumentData): PayoutRequest {
  const momo = p.rail === 'mobile_money';
  return {
    reference: id, country: p.country, rail: p.rail, currency: p.currency, amountMinor: Number(p.netMinor),
    holderName: p.holderName, account: momo ? s.msisdn : s.accountNumber,
    bankCode: p.provider === 'paystack' ? (momo ? s.paystackBank : s.bankCode) : (momo ? s.flwBank : s.bankCode),
    narration: 'Oneova earnings',
  };
}

/** Finishes a balance payout once: paid (locked → out) or failed (locked → available). */
export async function settlePayPayout(id: string, to: 'paid' | 'failed', info: Record<string, unknown> = {}): Promise<boolean> {
  const ref = payoutRef(id);
  const done = await db().runTransaction(async (tx) => {
    const [snap, posted] = await Promise.all([tx.get(ref), tx.get(ledgerRef(`ppdone_${id}`))]);
    const p = snap.data();
    if (!p || !['pending', 'processing'].includes(p.status) || posted.exists) return null;
    const lines = to === 'paid'
      ? [
          { account: ownerAccount(balanceKind(p.balance), p.uid), currency: p.currency, amountMinor: -p.amountMinor, bucket: 'locked' as const },
          { account: `payout:${p.provider}`, currency: p.currency, amountMinor: p.netMinor },
          ...(p.feeMinor > 0 ? [{ account: 'platform:revenue', currency: p.currency, amountMinor: p.feeMinor }] : []),
        ]
      : [
          { account: ownerAccount(balanceKind(p.balance), p.uid), currency: p.currency, amountMinor: -p.amountMinor, bucket: 'locked' as const },
          { account: ownerAccount(balanceKind(p.balance), p.uid), currency: p.currency, amountMinor: p.amountMinor, bucket: 'available' as const },
        ];
    writeLedger(tx, `ppdone_${id}`, false, to === 'paid' ? 'balance_payout' : 'balance_payout_returned', lines, { payoutId: id });
    tx.update(ref, { status: to, needsCheck: false, ...info, updatedAt: FieldValue.serverTimestamp() });
    return p;
  });
  if (!done) return false;
  const money = `${done.currency} ${toMajor(Number(done.netMinor), done.currency).toLocaleString('en-US')}`;
  if (to === 'paid') await notify(done.uid, `pp_paid_${id}`, 'Money sent 🎉', `${money} is on its way to your ${done.methodLabel}.`);
  else await notify(done.uid, `pp_failed_${id}`, 'Withdrawal didn’t go through', `The money is back in your Oneova balance. ${info.failureReason ?? ''}`.trim());
  return true;
}

async function dispatch(id: string): Promise<void> {
  const ref = payoutRef(id);
  const p = await db().runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data();
    if (!d || d.status !== 'pending') return null;
    tx.update(ref, { status: 'processing', updatedAt: FieldValue.serverTimestamp() });
    return d;
  });
  if (!p) return;
  const s = (await db().doc(`payout_method_secrets/${p.uid}_${p.methodId}`).get()).data();
  if (!s && p.sandbox !== true) {
    await settlePayPayout(id, 'failed', { failureReason: 'The payout method was removed.' });
    return;
  }
  const adapter = await adapterForPayout(p);
  if (!adapter) {
    await settlePayPayout(id, 'failed', { failureReason: 'Payouts are paused for this method.' });
    return;
  }
  const { outcome } = await routePayout([adapter], payoutRequest(id, p, s ?? {}));
  if (outcome.kind === 'accepted') {
    if (p.sandbox === true) {
      await settlePayPayout(id, 'paid', { providerRef: outcome.providerRef, paidAt: FieldValue.serverTimestamp() });
      return;
    }
    await ref.update({ providerRef: outcome.providerRef, sentAt: FieldValue.serverTimestamp(), needsCheck: true, checkAfter: Timestamp.fromMillis(Date.now() + 6 * 3600_000) });
  } else if (outcome.kind === 'rejected') {
    await settlePayPayout(id, 'failed', { failureReason: outcome.reason.slice(0, 200) });
  } else {
    logger.error('balance payout unknown; will reconcile', id, outcome.reason);
    await ref.update({ sentAt: FieldValue.serverTimestamp(), needsCheck: true, checkAfter: Timestamp.fromMillis(Date.now() + 10 * 60_000), lastCheckNote: outcome.reason.slice(0, 200) });
  }
}

export const payWithdraw = onCall({ timeoutSeconds: 60 }, async (req) => {
  const uid = me(req);
  const key = String(req.data?.idempotencyKey ?? '');
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(key)) throw new HttpsError('invalid-argument', 'Missing request id.');
  const id = `pp_${crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 32)}`;
  const existing = (await payoutRef(id).get()).data();
  if (existing) return { id, status: existing.status };

  const rt = await payRuntime();
  const kyc = (await db().doc(`kyc/${uid}`).get()).data();
  if (kyc?.status !== 'verified' && !rt.cfg.sandbox) throw new HttpsError('failed-precondition', 'Verify your identity first. It keeps your money safe.');
  const methodId = String(req.data?.methodId ?? '');
  const method = methodId && !methodId.includes('/') ? (await db().doc(`payout_methods/${uid}/methods/${methodId}`).get()).data() : null;
  if (!method) throw new HttpsError('failed-precondition', 'Add a payout method first.');
  const currency = String(req.data?.currency ?? method.currency ?? '').toUpperCase();
  if (currency !== String(method.currency).toUpperCase()) {
    throw new HttpsError('failed-precondition', `This payout method pays in ${method.currency}. Choose a ${currency} method.`);
  }
  const amountMinor = Math.floor(Number(req.data?.amountMinor));
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) throw new HttpsError('invalid-argument', 'Enter an amount.');
  const feeMinor = balancePayoutFee(method.rail, amountMinor);
  const netMinor = amountMinor - feeMinor;
  if (netMinor <= 0) throw new HttpsError('failed-precondition', 'The amount is smaller than the payout fee.');
  const hold = (await db().doc(`payout_holds/${uid}`).get()).get('reasons') as string[] | undefined;
  // Withdraw from the personal balance (default) or the business one (shop sales, scan to pay).
  const balance = balanceKind(req.data?.balance);
  const acct = ownerAccount(balance, uid);

  await db().runTransaction(async (tx) => {
    const [bal, cur, posted] = await Promise.all([tx.get(balanceRefOf(balance, uid)), tx.get(payoutRef(id)), tx.get(ledgerRef(`ppreq_${id}`))]);
    if (cur.exists) return;
    if (bucketOf(bal.data(), currency, 'available') < amountMinor) {
      throw new HttpsError('failed-precondition', `Not enough in your ${balance === 'business' ? 'business' : 'Oneova'} balance.`);
    }
    writeLedger(tx, `ppreq_${id}`, posted.exists, 'balance_payout_lock', [
      { account: acct, currency, amountMinor: -amountMinor, bucket: 'available' },
      { account: acct, currency, amountMinor, bucket: 'locked' },
    ], { payoutId: id, balance });
    tx.set(payoutRef(id), {
      uid, balance, methodId, methodLabel: method.label ?? 'payout method', rail: method.rail, provider: method.provider,
      country: method.country, currency, holderName: method.holderName ?? kyc?.verifiedName ?? '',
      amountMinor, feeMinor, netMinor, status: 'pending', sandbox: rt.cfg.sandbox && kyc?.status !== 'verified',
      review: !!hold?.length, reviewReasons: hold ?? [],
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  });
  if (!hold?.length) await dispatch(id);
  const p = (await payoutRef(id).get()).data()!;
  return { id, status: p.status, netMinor, feeMinor, currency, review: !!hold?.length };
});

export const payBalanceReconcile = onSchedule('every 15 minutes', async () => {
  const due = (await db().collection('pay_payouts').where('needsCheck', '==', true).limit(200).get())
    .docs.filter((d) => ((d.get('checkAfter') as Timestamp | undefined)?.toMillis() ?? 0) <= Date.now()).slice(0, 50);
  for (const d of due) {
    try {
      const p = d.data();
      const adapter = await adapterForPayout(p);
      if (!adapter) continue;
      const policy = POLICY[p.provider] ?? { notFoundIsFinalAfterMs: null, idempotentRetry: false };
      const status: ProviderStatus = (await adapter.status(d.id)).status;
      const age = Date.now() - ((p.sentAt as Timestamp | undefined)?.toMillis() ?? Date.now());
      const action = reconcileAction(status, age, { notFoundIsFinalAfterMs: policy.notFoundIsFinalAfterMs });
      if (action === 'settle_paid') await settlePayPayout(d.id, 'paid', { paidAt: FieldValue.serverTimestamp() });
      else if (action === 'settle_failed') await settlePayPayout(d.id, 'failed', { failureReason: 'The network didn’t complete it.' });
      else if (action === 'review') await d.ref.update({ needsCheck: false, review: true, reviewReasons: FieldValue.arrayUnion('provider_status_unknown') });
      else await d.ref.update({ checkAfter: Timestamp.fromMillis(Date.now() + 30 * 60_000), checks: FieldValue.increment(1), lastCheckNote: status });
    } catch (e: any) {
      logger.error('balance payout reconcile failed', d.id, e?.message ?? e);
    }
  }
});
