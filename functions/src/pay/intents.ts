/**
 * Oneova Pay pay-ins (`pay_intents/{id}`, id = UUID).
 *
 *   app → payMethods     ways to pay in the payer's country
 *   app → payCreate      server prices it (order / top-up), asks the partner:
 *                        a prompt on the payer's phone, a partner's secure page
 *                        (redirectUrl), or the Oneova balance (instant)
 *   app → payStatus      live status (the app also listens to the intent doc)
 *   app → payCancel      stop waiting (a late approval is still honoured)
 *   partners → webhooks  never trusted on their own: they only trigger a
 *                        status check against the partner's API
 *   payReconcileIntents  asks partners about intents still waiting
 *
 * Money safety:
 *   - The amount always comes from the server (order doc / validated top-up).
 *   - A pay-in is applied once: the ledger posting `payin_{id}` is the lock.
 *   - If the partner reports a different amount or currency, nothing is
 *     applied; the intent goes to review.
 *   - Money that arrives after a cancel / expiry is still recorded.
 */
import * as crypto from 'crypto';
import { onCall, onRequest, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { CollectCheck, toMajor, toMinor } from '../payments/provider';
import { AFRICA, normalizeMsisdn } from '../creator/payoutLogic';
import {
  IntentPurpose, IntentStatus, PayMethod, canMoveIntent, currencyFor, intentTtlMs, isOpenIntent, maskMsisdn, methodsFor,
  merchantFee, merchantLines, qrCodeFrom, qrProblem,
} from './payLogic';
import { balanceRef, bucketOf, ledgerRef, writeLedger } from './ledger';
import { payRuntime, returnUrl } from './payConfig';
import { applyOrderPaid, orderCurrency, orderMinor } from '../commerce/orderEscrow';

const db = () => getFirestore();
const intentRef = (id: string) => db().doc(`pay_intents/${id}`);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function me(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

const cc = (v: unknown) => (typeof v === 'string' && /^[A-Za-z]{2}$/.test(v) ? v.toUpperCase() : null);

/**
 * The account's payment country — one source of truth for currency:
 * verified ID, then the payout profile (location / SIM), then the profile,
 * then what the app sent. Exported for commerce pricing.
 */
export async function countryOf(uid: string, hint?: unknown): Promise<string> {
  const [pp, kyc, user] = await Promise.all([
    db().doc(`payout_profiles/${uid}`).get(), db().doc(`kyc/${uid}`).get(), db().doc(`users/${uid}`).get(),
  ]);
  return cc(kyc.get('status') === 'verified' ? kyc.get('country') : null)
    ?? cc(pp.get('detectedCountry')) ?? cc(user.get('country')) ?? cc(user.get('countryCode'))
    ?? cc(hint) ?? 'KE';
}

/** Public view of an intent for the app. */
function view(id: string, d: FirebaseFirestore.DocumentData) {
  return {
    intentId: id,
    status: d.status as IntentStatus,
    purpose: d.purpose,
    refId: d.refId,
    amountMinor: d.amountMinor,
    amount: toMajor(Number(d.amountMinor), String(d.currency)),
    currency: d.currency,
    method: d.method,
    redirectUrl: d.redirectUrl ?? null,
    failureReason: d.failureReason ?? null,
    sandbox: d.sandbox === true,
  };
}

// ───────────────────────────── Methods ─────────────────────────────

export const payMethods = onCall(async (req) => {
  const uid = me(req);
  const country = await countryOf(uid, req.data?.country);
  const rt = await payRuntime();
  const bal = rt.cfg.wallet ? (await balanceRef(uid).get()).data() : undefined;
  const currency = currencyFor(country);
  return {
    country,
    countryName: AFRICA[country]?.name ?? null,
    currency,
    dial: AFRICA[country]?.dial ?? null,
    methods: methodsFor(country, rt.cfg),
    sandbox: rt.cfg.sandbox,
    walletEnabled: rt.cfg.wallet,
    balanceMinor: rt.cfg.wallet ? bucketOf(bal, currency, 'available') : null,
    live: rt.cfg.mpesa || rt.cfg.momo || rt.cfg.flutterwave || rt.cfg.paystack,
  };
});

// ───────────────────────────── Create ─────────────────────────────

export const payCreate = onCall({ timeoutSeconds: 60 }, async (req) => {
  const uid = me(req);
  const purpose = String(req.data?.purpose ?? '') as IntentPurpose;
  if (purpose !== 'order' && purpose !== 'topup' && purpose !== 'merchant') throw new HttpsError('invalid-argument', 'Unknown payment.');
  const rt = await payRuntime();
  // Scan to pay: the merchant's code decides who is paid, the currency and (if set) the amount.
  let qr: FirebaseFirestore.DocumentData | undefined;
  let qrCode = '';
  if (purpose === 'merchant') {
    if (!rt.cfg.wallet) throw new HttpsError('failed-precondition', 'Scan to pay opens soon in your country.');
    qrCode = qrCodeFrom(String(req.data?.refId ?? '')) ?? '';
    qr = qrCode ? (await db().doc(`pay_qr/${qrCode}`).get()).data() : undefined;
    const problem = qrProblem(qr as never);
    if (problem) throw new HttpsError('failed-precondition', problem);
    if (qr!.merchantUid === uid) throw new HttpsError('failed-precondition', 'This is your own code.');
  }
  // A merchant code is paid with the merchant country's methods (you pay where you are).
  const country = purpose === 'merchant' ? String(qr!.country) : await countryOf(uid, req.data?.country);
  const method: PayMethod | undefined = methodsFor(country, rt.cfg).find((m) => m.id === String(req.data?.methodId ?? ''));
  if (!method) throw new HttpsError('failed-precondition', 'This way to pay isn’t open in your country yet.');

  // Too many attempts in a short time is either a bug or abuse.
  const recent = await db().collection('pay_intents').where('uid', '==', uid).where('createdAt', '>', Timestamp.fromMillis(Date.now() - 10 * 60_000)).get();
  if (recent.size >= 10) throw new HttpsError('resource-exhausted', 'Too many payment attempts. Wait a few minutes and try again.');

  let amountMinor: number;
  let currency: string;
  let refId: string;
  let narration: string;
  if (purpose === 'order') {
    refId = String(req.data?.refId ?? '');
    if (!refId || refId.includes('/')) throw new HttpsError('invalid-argument', 'Missing order.');
    const o = (await db().doc(`orders/${refId}`).get()).data();
    if (!o || o.buyerId !== uid) throw new HttpsError('not-found', 'Order not found.');
    if (!['awaiting_payment', 'payment_failed'].includes(o.status)) throw new HttpsError('failed-precondition', 'This order is already paid or closed.');
    // A second tap while a prompt is still open returns the same payment.
    if (o.payIntentId) {
      const open = (await intentRef(o.payIntentId).get()).data();
      if (open && isOpenIntent(open.status) && open.method?.id === method.id) return view(o.payIntentId, open);
    }
    const m = orderMinor(o);
    amountMinor = m.total;
    currency = orderCurrency(o);
    narration = `Oneova order ${refId.slice(0, 6)}`;
  } else if (purpose === 'merchant') {
    currency = String(qr!.currency);
    if (typeof qr!.amountMinor === 'number') amountMinor = qr!.amountMinor;
    else {
      const amount = Number(req.data?.amount);
      amountMinor = Number.isFinite(amount) ? toMinor(amount, currency) : 0;
      if (amountMinor < toMinor(1, currency) || amountMinor > toMinor(1_000_000, currency)) throw new HttpsError('invalid-argument', 'Enter the amount to pay.');
    }
    refId = qrCode;
    narration = `Oneova Pay ${String(qr!.label ?? 'merchant').slice(0, 20)}`;
  } else {
    if (!rt.cfg.wallet) throw new HttpsError('failed-precondition', 'Oneova balance top-ups open soon.');
    if (method.rail === 'balance') throw new HttpsError('invalid-argument', 'Choose how to top up.');
    currency = currencyFor(country);
    const amount = Number(req.data?.amount);
    amountMinor = Number.isFinite(amount) ? toMinor(amount, currency) : 0;
    const minMinor = toMinor(1, currency);
    if (amountMinor < minMinor || amountMinor > toMinor(1_000_000, currency)) throw new HttpsError('invalid-argument', 'Enter an amount to add.');
    refId = uid;
    narration = 'Oneova top-up';
  }
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) throw new HttpsError('failed-precondition', 'Nothing to pay.');

  let msisdn: string | null = null;
  if (method.needsPhone) {
    msisdn = normalizeMsisdn(String(req.data?.msisdn ?? ''), country);
    if (!msisdn) throw new HttpsError('invalid-argument', `Enter the phone number for ${method.label}.`);
  }

  const id = crypto.randomUUID();
  const ref = intentRef(id);
  const base = {
    uid, purpose, refId, amountMinor, currency, country,
    ...(purpose === 'merchant' ? { merchantUid: String(qr!.merchantUid) } : {}),
    method: { id: method.id, rail: method.rail, provider: method.provider, kind: method.kind, label: method.label, network: method.network ?? null },
    provider: method.provider,
    msisdnMasked: msisdn ? maskMsisdn(msisdn) : null,
    sandbox: method.sandbox === true,
    status: 'created' as IntentStatus,
    checks: 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + intentTtlMs(method.kind)),
  };
  await ref.set(base);
  if (purpose === 'order') await db().doc(`orders/${refId}`).update({ payIntentId: id, status: 'awaiting_payment', updatedAt: FieldValue.serverTimestamp() });

  // Oneova balance: settles at once, in one transaction.
  if (method.rail === 'balance') {
    if (purpose === 'merchant') await payMerchantFromBalance(id);
    else await payFromBalance(id);
    return view(id, (await ref.get()).data()!);
  }

  const collector = rt.collectors[method.provider as keyof typeof rt.collectors];
  if (!collector || !collector.supports(country, method.rail, currency, method.network)) {
    await ref.update({ status: 'failed', failureReason: `${method.label} can’t take ${currency} payments.`, updatedAt: FieldValue.serverTimestamp() });
    throw new HttpsError('failed-precondition', `${method.label} can’t take ${currency} payments.`);
  }
  const user = await getAuth().getUser(uid).catch(() => null);
  const outcome = await collector.collect({
    reference: id, country, rail: method.rail, currency, amountMinor,
    msisdn: msisdn ?? undefined, network: method.network,
    email: user?.email ?? `pay+${uid}@oneova.app`, payerName: user?.displayName ?? undefined,
    returnUrl: `${returnUrl()}?intent=${id}`, narration,
  });
  if (outcome.kind === 'accepted') {
    await ref.update({
      status: 'pending_payer', providerRef: outcome.providerRef || null, redirectUrl: outcome.redirectUrl ?? null,
      sentAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  } else if (outcome.kind === 'rejected') {
    await ref.update({ status: 'failed', failureReason: outcome.reason.slice(0, 200), updatedAt: FieldValue.serverTimestamp() });
    if (purpose === 'order') await db().doc(`orders/${refId}`).update({ status: 'payment_failed', updatedAt: FieldValue.serverTimestamp() });
  } else {
    // We can't tell if the prompt went out. Keep it open; the status check decides.
    logger.warn('pay-in outcome unknown', id, outcome.reason);
    await ref.update({ status: 'pending_payer', lastCheckNote: outcome.reason.slice(0, 200), sentAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  }
  return view(id, (await ref.get()).data()!);
});

/**
 * Credits a merchant for a confirmed scan-to-pay intent, inside the caller's
 * transaction ([qrSnap] read before any write): net to the merchant's balance,
 * the merchant fee to the platform, the code marked paid (one-time codes).
 */
function creditMerchant(
  tx: FirebaseFirestore.Transaction, id: string, i: FirebaseFirestore.DocumentData,
  from: string, qrSnap: FirebaseFirestore.DocumentSnapshot, extra: Record<string, unknown>,
): void {
  const fee = merchantFee(Number(i.amountMinor));
  writeLedger(tx, `payin_${id}`, false, 'merchant_payin', merchantLines(from, String(i.merchantUid), i.currency, Number(i.amountMinor), fee),
    { intentId: id, code: i.refId, merchantUid: i.merchantUid, fee, ...extra });
  if (qrSnap.exists) {
    tx.update(qrSnap.ref, {
      paidCount: FieldValue.increment(1), receivedMinor: FieldValue.increment(Number(i.amountMinor) - fee),
      ...(qrSnap.get('oneTime') === true ? { paid: true, paidBy: i.uid, paidIntentId: id } : {}),
      lastPaidAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  }
  const money = `${i.currency} ${toMajor(Number(i.amountMinor) - fee, i.currency).toLocaleString('en-US')}`;
  tx.set(db().collection('notifications').doc(`merchant_paid_${id}`), {
    userId: i.merchantUid, recipientId: i.merchantUid, actorId: i.uid, category: 'system', priority: 'high', type: 'payment',
    title: 'Payment received', body: `${money} is in your Oneova balance.`, deepLink: '/wallet', isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/** Scan to pay from the payer's Oneova balance: settles at once. */
async function payMerchantFromBalance(id: string): Promise<void> {
  const ref = intentRef(id);
  await db().runTransaction(async (tx) => {
    const i = (await tx.get(ref)).data();
    if (!i || i.purpose !== 'merchant' || !isOpenIntent(i.status)) return;
    const [bal, posted, qrSnap] = await Promise.all([tx.get(balanceRef(i.uid)), tx.get(ledgerRef(`payin_${id}`)), tx.get(db().doc(`pay_qr/${i.refId}`))]);
    if (posted.exists) return;
    const problem = qrProblem(qrSnap.data() as never);
    if (problem) {
      tx.update(ref, { status: 'failed', failureReason: problem, updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    if (bucketOf(bal.data(), i.currency, 'available') < i.amountMinor) {
      tx.update(ref, { status: 'failed', failureReason: 'Not enough in your Oneova balance.', updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    creditMerchant(tx, id, i, `user:${i.uid}`, qrSnap, { provider: 'oneova' });
    tx.update(ref, { status: 'succeeded', paidAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  });
}

/** Pays an intent from the payer's Oneova balance (orders only). */
async function payFromBalance(id: string): Promise<void> {
  const ref = intentRef(id);
  await db().runTransaction(async (tx) => {
    const i = (await tx.get(ref)).data();
    if (!i || i.purpose !== 'order' || !isOpenIntent(i.status)) return;
    const orderRef = db().doc(`orders/${i.refId}`);
    const [o, bal, posted] = await Promise.all([tx.get(orderRef), tx.get(balanceRef(i.uid)), tx.get(ledgerRef(`payin_${id}`))]);
    const order = o.data();
    const product = order ? (await tx.get(db().doc(`products/${order.productId}`))).data() : undefined;
    if (!order || !['awaiting_payment', 'payment_failed'].includes(order.status)) {
      tx.update(ref, { status: 'failed', failureReason: 'This order is closed.', updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    if (bucketOf(bal.data(), i.currency, 'available') < i.amountMinor) {
      tx.update(ref, { status: 'failed', failureReason: 'Not enough in your Oneova balance.', updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    writeLedger(tx, `payin_${id}`, posted.exists, 'order_payin', [
      { account: `user:${i.uid}`, currency: i.currency, amountMinor: -i.amountMinor, bucket: 'available' },
      { account: `escrow:${i.refId}`, currency: i.currency, amountMinor: i.amountMinor },
    ], { intentId: id, orderId: i.refId, provider: 'oneova' });
    applyOrderPaid(tx, i.refId, order, product, id);
    tx.update(ref, { status: 'succeeded', paidAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  });
}

// ───────────────────────────── Finishing ─────────────────────────────

/** Applies a confirmed pay-in once: ledger + the purpose's effect. */
async function applySuccess(id: string, check: CollectCheck): Promise<void> {
  const ref = intentRef(id);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const i = snap.data();
    if (!i) return;
    const posted = await tx.get(ledgerRef(`payin_${id}`));
    if (posted.exists || !canMoveIntent(i.status, 'succeeded')) return;
    const orderRef = i.purpose === 'order' ? db().doc(`orders/${i.refId}`) : null;
    const order = orderRef ? (await tx.get(orderRef)).data() : undefined;
    const product = order ? (await tx.get(db().doc(`products/${order.productId}`))).data() : undefined;
    const qrSnap = i.purpose === 'merchant' ? await tx.get(db().doc(`pay_qr/${i.refId}`)) : null;
    // --- writes ---
    const clearing = `clearing:${i.provider}`;
    const mismatch = (check.amountMinor != null && check.amountMinor !== i.amountMinor)
      || (check.currency != null && check.currency !== '' && check.currency.toUpperCase() !== i.currency);
    if (mismatch) {
      logger.error('pay-in amount mismatch', id, check.amountMinor, check.currency, i.amountMinor, i.currency);
      tx.update(ref, {
        status: 'review', reviewReason: 'amount_mismatch', paidAmountMinor: check.amountMinor ?? null, paidCurrency: check.currency ?? null,
        providerRef: check.providerRef ?? i.providerRef ?? null, updatedAt: FieldValue.serverTimestamp(),
      });
      if (orderRef) tx.update(orderRef, { status: 'payment_mismatch', updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    const providerRef = check.providerRef || i.providerRef || null;
    if (i.purpose === 'order') {
      const payable = !!order && ['awaiting_payment', 'payment_failed'].includes(order.status) && (!order.payIntentId || order.payIntentId === id);
      if (!payable) {
        // Paid, but the order can't take it (closed, or paid by another attempt): hold it for a person to return.
        writeLedger(tx, `payin_${id}`, false, 'payin_unmatched', [
          { account: clearing, currency: i.currency, amountMinor: -i.amountMinor },
          { account: `suspense:${id}`, currency: i.currency, amountMinor: i.amountMinor },
        ], { intentId: id, provider: i.provider, sandbox: i.sandbox === true });
        tx.update(ref, { status: 'review', reviewReason: 'order_not_payable', providerRef, paidAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
        return;
      }
      writeLedger(tx, `payin_${id}`, false, 'order_payin', [
        { account: clearing, currency: i.currency, amountMinor: -i.amountMinor },
        { account: `escrow:${i.refId}`, currency: i.currency, amountMinor: i.amountMinor },
      ], { intentId: id, orderId: i.refId, provider: i.provider, sandbox: i.sandbox === true });
      applyOrderPaid(tx, i.refId, order, product, id);
    } else if (i.purpose === 'merchant' && qrSnap) {
      // The money arrived, so the merchant is credited even if the code expired meanwhile.
      creditMerchant(tx, id, i, clearing, qrSnap, { provider: i.provider, sandbox: i.sandbox === true });
    } else {
      writeLedger(tx, `payin_${id}`, false, 'topup', [
        { account: clearing, currency: i.currency, amountMinor: -i.amountMinor },
        { account: `user:${i.uid}`, currency: i.currency, amountMinor: i.amountMinor, bucket: 'available' },
      ], { intentId: id, provider: i.provider, sandbox: i.sandbox === true });
      tx.set(db().collection('notifications').doc(`topup_${id}`), {
        userId: i.uid, recipientId: i.uid, category: 'system', priority: 'normal', type: 'payment',
        title: 'Money added', body: `${i.currency} ${toMajor(i.amountMinor, i.currency).toLocaleString('en-US')} is in your Oneova balance.`,
        deepLink: '/wallet', isRead: false, createdAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(ref, { status: 'succeeded', providerRef, paidAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  });
}

async function markFailed(id: string, reason: string): Promise<void> {
  await db().runTransaction(async (tx) => {
    const i = (await tx.get(intentRef(id))).data();
    if (!i || !canMoveIntent(i.status, 'failed')) return;
    const orderRef = i.purpose === 'order' ? db().doc(`orders/${i.refId}`) : null;
    const order = orderRef ? (await tx.get(orderRef)).data() : undefined;
    tx.update(intentRef(id), { status: 'failed', failureReason: reason.slice(0, 200), updatedAt: FieldValue.serverTimestamp() });
    if (orderRef && order?.status === 'awaiting_payment' && order.payIntentId === id) {
      tx.update(orderRef, { status: 'payment_failed', updatedAt: FieldValue.serverTimestamp() });
    }
  });
}

/**
 * Asks the partner about one intent and applies the answer. Safe to call any
 * number of times (webhooks, the app, the reconcile job). Returns the status.
 */
export async function refreshIntent(id: string): Promise<IntentStatus | null> {
  if (!UUID.test(id)) return null;
  const ref = intentRef(id);
  const i = (await ref.get()).data();
  if (!i) return null;
  const lateWindow = ['expired', 'cancelled'].includes(i.status)
    && Date.now() - ((i.updatedAt as Timestamp | undefined)?.toMillis() ?? 0) < 6 * 3600_000;
  if (!isOpenIntent(i.status) && !lateWindow) return i.status;
  if (i.provider === 'oneova') return i.status;
  const rt = await payRuntime();
  const collector = rt.collectors[i.provider as keyof typeof rt.collectors];
  if (!collector) return i.status; // keys missing right now; try later
  const check = await collector.check(id, i.providerRef ?? undefined).catch((e: any) => ({ status: 'unknown' as const, reason: String(e?.message ?? e) }));
  await ref.update({ checks: FieldValue.increment(1), lastCheckedAt: FieldValue.serverTimestamp(), lastCheckNote: check.status });

  if (check.status === 'paid') {
    await applySuccess(id, check);
  } else if (check.status === 'failed') {
    await markFailed(id, check.reason ?? 'The payment was not completed.');
  } else if (isOpenIntent(i.status) && (i.expiresAt as Timestamp).toMillis() < Date.now()) {
    if (check.status === 'unknown') {
      // Can't tell: a person looks after a day; until then we keep asking.
      const age = Date.now() - ((i.createdAt as Timestamp | undefined)?.toMillis() ?? Date.now());
      if (age > 24 * 3600_000) await ref.update({ status: 'review', reviewReason: 'status_unknown', updatedAt: FieldValue.serverTimestamp() });
    } else {
      await ref.update({ status: 'expired', updatedAt: FieldValue.serverTimestamp() });
      if (i.purpose === 'order') {
        await db().runTransaction(async (tx) => {
          const oref = db().doc(`orders/${i.refId}`);
          const o = (await tx.get(oref)).data();
          if (o?.status === 'awaiting_payment' && o.payIntentId === id) tx.update(oref, { status: 'payment_failed', updatedAt: FieldValue.serverTimestamp() });
        });
      }
    }
  }
  return ((await ref.get()).get('status') as IntentStatus) ?? null;
}

export const payStatus = onCall(async (req) => {
  const uid = me(req);
  const id = String(req.data?.intentId ?? '');
  if (!UUID.test(id)) throw new HttpsError('invalid-argument', 'Missing payment.');
  let d = (await intentRef(id).get()).data();
  if (!d || d.uid !== uid) throw new HttpsError('not-found', 'Payment not found.');
  const last = (d.lastCheckedAt as Timestamp | undefined)?.toMillis() ?? 0;
  if (isOpenIntent(d.status) && Date.now() - last > 3000) {
    await refreshIntent(id);
    d = (await intentRef(id).get()).data()!;
  }
  return view(id, d);
});

export const payCancel = onCall(async (req) => {
  const uid = me(req);
  const id = String(req.data?.intentId ?? '');
  if (!UUID.test(id)) throw new HttpsError('invalid-argument', 'Missing payment.');
  await db().runTransaction(async (tx) => {
    const d = (await tx.get(intentRef(id))).data();
    if (!d || d.uid !== uid) throw new HttpsError('not-found', 'Payment not found.');
    if (isOpenIntent(d.status)) tx.update(intentRef(id), { status: 'cancelled', updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
});

// ───────────────────────────── Refunds ─────────────────────────────

/**
 * Gives a succeeded order pay-in back to the buyer:
 *   Oneova balance          → straight back to the balance
 *   partner with refunds    → the partner refunds the card / wallet
 *   otherwise               → the Oneova balance when the wallet is on,
 *                             else a person sends it back ('review').
 */
export async function refundIntent(id: string, key: string): Promise<'refunded' | 'review' | 'none'> {
  if (!UUID.test(id)) return 'none';
  const i = (await intentRef(id).get()).data();
  if (!i || i.status !== 'succeeded') return 'none';
  const rt = await payRuntime();
  // Where the money sits now: the order's escrow, the merchant's balance, or the payer's own (top-up).
  const escrow = i.purpose === 'order' ? `escrow:${i.refId}` : i.purpose === 'merchant' ? `biz:${i.merchantUid}` : `user:${i.uid}`;
  const toBuyerBalance = async (via: string) => {
    await db().runTransaction(async (tx) => {
      const posted = await tx.get(ledgerRef(`refund_${id}`));
      writeLedger(tx, `refund_${id}`, posted.exists, 'refund_to_balance', [
        { account: escrow, currency: i.currency, amountMinor: -i.amountMinor },
        { account: `user:${i.uid}`, currency: i.currency, amountMinor: i.amountMinor, bucket: 'available' },
      ], { intentId: id, key });
      tx.update(intentRef(id), { status: 'refunded', refundedTo: via, refundedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    });
    return 'refunded' as const;
  };
  if (i.provider === 'oneova') return notifyRefund(i, id, await toBuyerBalance('balance'));

  const collector = rt.collectors[i.provider as keyof typeof rt.collectors];
  if (collector?.refund) {
    const r = await collector.refund(id, String(i.providerRef ?? ''), i.amountMinor, i.currency);
    if (r.kind === 'accepted') {
      await db().runTransaction(async (tx) => {
        const posted = await tx.get(ledgerRef(`refund_${id}`));
        writeLedger(tx, `refund_${id}`, posted.exists, 'refund_to_payer', [
          { account: escrow, currency: i.currency, amountMinor: -i.amountMinor },
          { account: `clearing:${i.provider}`, currency: i.currency, amountMinor: i.amountMinor },
        ], { intentId: id, key, providerRef: r.providerRef });
        tx.update(intentRef(id), { status: 'refunded', refundedTo: 'payer', refundRef: r.providerRef, refundedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
      });
      return notifyRefund(i, id, 'refunded');
    }
    if (r.kind === 'unknown') {
      // It may have gone through: never send a second refund on a guess.
      await intentRef(id).update({ status: 'review', reviewReason: 'refund_unknown', updatedAt: FieldValue.serverTimestamp() });
      return 'review';
    }
  }
  if (rt.cfg.wallet) return notifyRefund(i, id, await toBuyerBalance('balance'));
  await intentRef(id).update({ status: 'review', reviewReason: 'refund_manual', updatedAt: FieldValue.serverTimestamp() });
  return notifyRefund(i, id, 'review');
}

/** Tells the payer their money is coming back (or is being sent back by our team). */
async function notifyRefund(i: FirebaseFirestore.DocumentData, id: string, r: 'refunded' | 'review'): Promise<'refunded' | 'review'> {
  const money = `${i.currency} ${toMajor(i.amountMinor, i.currency).toLocaleString('en-US')}`;
  await db().collection('notifications').doc(`refund_${id}`).set({
    userId: i.uid, recipientId: i.uid, category: 'system', priority: 'high', type: 'payment',
    title: r === 'refunded' ? 'Refund sent' : 'Refund on its way',
    body: r === 'refunded'
      ? `${money} is on its way back to you.`
      : `We’re sending ${money} back to you. It can take up to 2 working days.`,
    deepLink: '/wallet/payments', isRead: false, createdAt: FieldValue.serverTimestamp(),
  }).catch(() => undefined);
  return r;
}

// ───────────────────────────── Reconcile & webhooks ─────────────────────────────

/** Intents still waiting on the payer, and recent late approvals. */
export const payReconcileIntents = onSchedule('every 5 minutes', async () => {
  const [open, late] = await Promise.all([
    db().collection('pay_intents').where('status', '==', 'pending_payer').limit(200).get(),
    db().collection('pay_intents').where('status', '==', 'expired').where('updatedAt', '>', Timestamp.fromMillis(Date.now() - 6 * 3600_000)).limit(100).get(),
  ]);
  const due = [...open.docs, ...late.docs].filter((d) => Date.now() - ((d.get('lastCheckedAt') as Timestamp | undefined)?.toMillis() ?? 0) > 60_000).slice(0, 80);
  for (const d of due) {
    try {
      await refreshIntent(d.id);
    } catch (e: any) {
      logger.error('pay reconcile failed', d.id, e?.message ?? e);
    }
  }
});

/** M-Pesa STK callback: only a hint; the status comes from the STK query. */
export const payWebhookMpesa = onRequest(async (req, res) => {
  try {
    const checkout = String(req.body?.Body?.stkCallback?.CheckoutRequestID ?? '');
    if (checkout) {
      const q = await db().collection('pay_intents').where('providerRef', '==', checkout).limit(1).get();
      if (!q.empty) await refreshIntent(q.docs[0].id);
    }
  } catch (e: any) {
    logger.error('mpesa callback failed', e?.message ?? e);
  }
  res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
});

/** MTN MoMo callback: only a hint; the status comes from the API. */
export const payWebhookMomo = onRequest(async (req, res) => {
  try {
    const ref = String(req.body?.externalId ?? req.body?.referenceId ?? '');
    if (UUID.test(ref)) await refreshIntent(ref);
  } catch (e: any) {
    logger.error('momo callback failed', e?.message ?? e);
  }
  res.status(200).send('ok');
});

export const isIntentReference = (ref: string) => UUID.test(ref);

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

/**
 * Where a partner's secure page sends the payer back. Checks the payment with
 * the partner, shows the result and offers a way back into the app (where the
 * pay sheet already updates by itself).
 */
export const payReturn = onRequest(async (req, res) => {
  const id = String(req.query.intent ?? req.query.tx_ref ?? req.query.reference ?? req.query.trxref ?? '');
  let status: IntentStatus | null = null;
  let amount = '';
  try {
    if (UUID.test(id)) {
      status = await refreshIntent(id);
      const d = (await intentRef(id).get()).data();
      if (d) amount = `${d.currency} ${toMajor(Number(d.amountMinor), String(d.currency)).toLocaleString('en-US')}`;
    }
  } catch (e: any) {
    logger.warn('pay return check failed', id, e?.message ?? e);
  }
  const done = status === 'succeeded';
  const waiting = status === 'created' || status === 'pending_payer' || status === null && UUID.test(id);
  const title = done ? 'Payment received' : waiting ? 'Finishing your payment…' : 'Payment didn’t go through';
  const body = done
    ? `${amount ? `${esc(amount)} is paid. ` : ''}You can go back to Oneova now.`
    : waiting
      ? 'This page updates by itself in a few seconds.'
      : 'Nothing was charged. Go back to Oneova to try again.';
  const appLink = 'intent://app/wallet/payments#Intent;scheme=oneova;package=com.oneova.app;end';
  res.set('Cache-Control', 'no-store');
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.status(200).send(`<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
${waiting ? '<meta http-equiv="refresh" content="4">' : ''}
<title>Oneova Pay</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;
font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;color:#fff;
background:radial-gradient(120% 80% at 50% 0%,#0E1630 0%,#07090F 70%)}
.card{width:100%;max-width:380px;text-align:center;padding:32px 24px;border-radius:24px;
background:rgba(255,255,255,.05);border:1px solid rgba(45,123,255,.25)}
.dot{width:72px;height:72px;margin:0 auto 18px;border-radius:50%;display:flex;align-items:center;justify-content:center;
font-size:34px;background:linear-gradient(135deg,#0C4FA8,#FF2D87)}
h1{font-size:22px;margin:0 0 8px}p{margin:0 0 22px;color:rgba(255,255,255,.7)}
a.btn{display:block;padding:15px;border-radius:999px;color:#fff;text-decoration:none;font-weight:800;
background:linear-gradient(90deg,#0C4FA8,#FF2D87)}
small{display:block;margin-top:16px;color:rgba(255,255,255,.4)}
</style></head><body><main class="card">
<div class="dot">${done ? '✓' : waiting ? '…' : '!'}</div>
<h1>${title}</h1><p>${body}</p>
<a class="btn" href="${appLink}">Back to Oneova</a>
<small>Oneova Pay · protected payment</small>
</main></body></html>`);
});
