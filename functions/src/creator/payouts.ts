/**
 * Creator withdrawals: Diamonds (gift earnings) → mobile money, bank or Stripe.
 *
 *   app → walletSync          releases Diamonds past the hold into availableCoins
 *   app → payoutOptions       country (location → SIM → locale), rails, fees, FX
 *   app → payoutBanks         bank list for the country
 *   app → savePayoutMethod    KYC must be verified; the name on the ID is the payee
 *   app → requestWithdrawal   idempotent; fraud checks; locks Diamonds; sends it
 *   app → cancelWithdrawal    while it is still pending
 *   admin → reviewWithdrawal  approve / reject one held for review
 *   Flutterwave / Paystack → webhooks mark it paid or failed (failed refunds)
 *
 * Purchased coins (`balanceCoins`) are never touched here.
 *
 * Secrets (Secret Manager, read at run time; a missing one just turns its rail off):
 *   FLUTTERWAVE_SECRET_KEY, FLUTTERWAVE_WEBHOOK_HASH, PAYSTACK_SECRET_KEY,
 *   STRIPE_SECRET_KEY, GOOGLE_MAPS_SERVER_KEY (reverse geocoding)
 */
import * as crypto from 'crypto';
import Stripe from 'stripe';
import { onCall, onRequest, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { optionalSecret } from '../optionalSecrets';
import { ledgerOutbox } from '../ledger/outbox';
import { FetchFn, PaymentProvider, PayoutRequest, ProviderStatus, toMinor } from '../payments/provider';
import { FlutterwaveProvider, PaystackProvider, POLICY, StripeTransferProvider } from '../payments/adapters';
import { ReconcileAction, reconcileAction, routePayout } from '../payments/router';
import {
  AFRICA, DIAMOND_USD, HOLD_DAYS, MAX_REQUESTS_PER_DAY, MAX_WITHDRAW_USD, MIN_WITHDRAW_USD,
  Provider, Rail, WithdrawalStatus, canMove, diamondsToUsd, fraudReasons, isAfrica,
  normalizeMsisdn, payoutFeeUsd, railsFor, roundLocal,
} from './payoutLogic';

const db = () => getFirestore();
const FLW = 'https://api.flutterwave.com/v3';
const PAYSTACK = 'https://api.paystack.co';
const EARNING_TYPES = new Set(['live_gift_received', 'user_gift_received']);

function me(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

const cc = (v: unknown) => (typeof v === 'string' && /^[A-Za-z]{2}$/.test(v) ? v.toUpperCase() : null);

async function configured() {
  const [flw, ps, st] = await Promise.all([
    optionalSecret('FLUTTERWAVE_SECRET_KEY'), optionalSecret('PAYSTACK_SECRET_KEY'), optionalSecret('STRIPE_SECRET_KEY'),
  ]);
  return { flutterwave: !!flw, paystack: !!ps, stripe: !!st, keys: { flw, ps, st } };
}

// ───────────────────────────── FX ─────────────────────────────

/** Units of [currency] per 1 USD, cached 6 h in `fx_rates/USD`. */
async function usdRate(currency: string): Promise<number> {
  if (currency === 'USD') return 1;
  const ref = db().doc('fx_rates/USD');
  const snap = await ref.get();
  const fresh = snap.exists && Date.now() - (snap.get('fetchedAt') as Timestamp).toMillis() < 6 * 3600_000;
  let rates = snap.get('rates') as Record<string, number> | undefined;
  if (!fresh) {
    try {
      const res = await fetch('https://open.er-api.com/v6/latest/USD').then((r) => r.json()) as any;
      if (res?.result === 'success' && res.rates) {
        rates = res.rates;
        await ref.set({ rates, fetchedAt: FieldValue.serverTimestamp(), source: 'open.er-api.com' });
      }
    } catch (e: any) {
      logger.warn('fx fetch failed', e?.message ?? e);
    }
  }
  const r = rates?.[currency];
  if (!r || !Number.isFinite(r)) throw new HttpsError('unavailable', 'Exchange rates are not available right now. Try again in a minute.');
  return r;
}

// ───────────────────────────── Earnings release ─────────────────────────────

async function releaseMatured(uid: string): Promise<number> {
  const cutoff = Date.now() - HOLD_DAYS * 86400_000;
  const wallet = db().doc(`wallets/${uid}`);
  const pending = await wallet.collection('ledger').where('status', '==', 'pending').limit(400).get();
  const due = pending.docs.filter((d) => EARNING_TYPES.has(d.get('type')) && ((d.get('createdAt') as Timestamp | undefined)?.toMillis() ?? Infinity) <= cutoff).slice(0, 200);
  if (!due.length) return 0;
  return db().runTransaction(async (tx) => {
    const fresh = await Promise.all(due.map((d) => tx.get(d.ref)));
    let sum = 0;
    const ids: string[] = [];
    for (const d of fresh) {
      if (d.get('status') !== 'pending') continue;
      sum += Math.max(0, Number(d.get('amount') ?? 0));
      ids.push(d.id);
      tx.update(d.ref, { status: 'available', releasedAt: FieldValue.serverTimestamp() });
    }
    if (sum > 0) {
      const batchId = crypto.createHash('sha256').update(ids.sort().join(',')).digest('hex').slice(0, 24);
      ledgerOutbox(tx, `release_${uid}_${batchId}`, 'release', { uid, diamonds: sum });
      tx.set(wallet, {
        pendingCoins: FieldValue.increment(-sum), availableCoins: FieldValue.increment(sum),
        lifetimeEarnedCoins: FieldValue.increment(sum), updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    return sum;
  });
}

/** Releases matured earnings and returns the wallet in Diamonds and USD. */
export const walletSync = onCall(async (req) => {
  const uid = me(req);
  const released = await releaseMatured(uid);
  const w = (await db().doc(`wallets/${uid}`).get()).data() ?? {};
  const n = (k: string) => Math.max(0, Number(w[k] ?? 0));
  return {
    released,
    coins: n('balanceCoins'),
    pendingDiamonds: n('pendingCoins'),
    availableDiamonds: n('availableCoins'),
    lockedDiamonds: n('lockedCoins'),
    withdrawnDiamonds: n('withdrawnCoins'),
    diamondUsd: DIAMOND_USD,
    holdDays: HOLD_DAYS,
    minUsd: MIN_WITHDRAW_USD,
  };
});

// ───────────────────────────── Country & rails ─────────────────────────────

async function reverseGeocode(lat: number, lng: number): Promise<string | null> {
  const key = await optionalSecret('GOOGLE_MAPS_SERVER_KEY');
  if (!key) return null;
  const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
  url.searchParams.set('latlng', `${lat},${lng}`);
  url.searchParams.set('result_type', 'country');
  url.searchParams.set('key', key);
  const res = await fetch(url).then((r) => r.json()).catch(() => null) as any;
  const comp = res?.results?.[0]?.address_components?.find((c: any) => c.types?.includes('country'));
  return cc(comp?.short_name);
}

async function touchDevice(uid: string, deviceId: unknown): Promise<number | null> {
  if (typeof deviceId !== 'string' || deviceId.length < 6 || deviceId.length > 200) return null;
  // Top-level and server-only, so nobody can backdate their own device.
  const ref = db().doc(`payout_devices/${uid}_${crypto.createHash('sha256').update(deviceId).digest('hex').slice(0, 32)}`);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({ firstSeenAt: FieldValue.serverTimestamp(), lastSeenAt: FieldValue.serverTimestamp() });
    return 0;
  }
  await ref.update({ lastSeenAt: FieldValue.serverTimestamp() });
  return (Date.now() - (snap.get('firstSeenAt') as Timestamp).toMillis()) / 3600_000;
}

export const payoutOptions = onCall(async (req) => {
  const uid = me(req);
  const lat = Number(req.data?.lat), lng = Number(req.data?.lng);
  let country: string | null = null;
  let source = 'none';
  if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
    country = await reverseGeocode(lat, lng);
    if (country) source = 'location';
  }
  for (const [k, s] of [['simCountry', 'sim'], ['phoneCountry', 'phone'], ['localeCountry', 'locale']] as const) {
    if (!country && cc(req.data?.[k])) { country = cc(req.data[k]); source = s; }
  }
  const kyc = (await db().doc(`kyc/${uid}`).get()).data() ?? {};
  if (!country && cc(kyc.country)) { country = cc(kyc.country); source = 'id'; }
  if (!country) throw new HttpsError('failed-precondition', 'We could not tell which country you are in. Turn on location and try again.');

  await Promise.all([
    db().doc(`payout_profiles/${uid}`).set({
      uid, detectedCountry: country, detectedSource: source,
      ...(source === 'location' ? { locationCountry: country, locationAt: FieldValue.serverTimestamp() } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }),
    touchDevice(uid, req.data?.deviceId),
  ]);

  const cfg = await configured();
  const a = AFRICA[country];
  const currency = a?.currency ?? 'USD';
  const rate = await usdRate(currency).catch(() => null);
  const stripeAcct = (await db().doc(`payout_accounts/${uid}`).get()).data() ?? {};
  return {
    country,
    countryName: a?.name ?? null,
    source,
    africa: isAfrica(country),
    currency,
    usdRate: rate,
    rails: railsFor(country, cfg),
    minUsd: MIN_WITHDRAW_USD,
    maxUsd: MAX_WITHDRAW_USD,
    diamondUsd: DIAMOND_USD,
    fees: { mobile_money: '1.5% (min $0.20)', bank: '1% (min $0.50)', stripe: '$0.25 + 0.25%' },
    kycStatus: kyc.status ?? 'none',
    kycCountry: kyc.country ?? null,
    stripe: { connected: !!stripeAcct.stripeAccountId, payoutsEnabled: stripeAcct.payoutsEnabled === true },
  };
});

export const payoutBanks = onCall(async (req) => {
  me(req);
  const country = cc(req.data?.country);
  if (!country || !AFRICA[country]?.bank) return { banks: [] };
  const cfg = await configured();
  try {
    if (cfg.keys.flw) {
      const res = await fetch(`${FLW}/banks/${country}`, { headers: { Authorization: `Bearer ${cfg.keys.flw}` } }).then((r) => r.json()) as any;
      return { banks: (res?.data ?? []).map((b: any) => ({ code: String(b.code), name: String(b.name) })) };
    }
    if (cfg.keys.ps) {
      const names: Record<string, string> = { NG: 'nigeria', GH: 'ghana', KE: 'kenya', ZA: 'south africa' };
      const res = await fetch(`${PAYSTACK}/bank?country=${encodeURIComponent(names[country] ?? '')}&perPage=200`, { headers: { Authorization: `Bearer ${cfg.keys.ps}` } }).then((r) => r.json()) as any;
      return { banks: (res?.data ?? []).map((b: any) => ({ code: String(b.code), name: String(b.name) })) };
    }
  } catch (e: any) {
    logger.warn('bank list failed', country, e?.message ?? e);
  }
  return { banks: [] };
});

// ───────────────────────────── Payout methods ─────────────────────────────

async function verifiedKyc(uid: string) {
  const k = (await db().doc(`kyc/${uid}`).get()).data();
  if (!k || k.status !== 'verified') throw new HttpsError('failed-precondition', 'Verify your identity first. It keeps your money safe.');
  return k;
}

export const savePayoutMethod = onCall(async (req) => {
  const uid = me(req);
  const kyc = await verifiedKyc(uid);
  const rail = String(req.data?.rail ?? '') as Rail;
  const country = cc(req.data?.country);
  if (!country || !['mobile_money', 'bank', 'stripe'].includes(rail)) throw new HttpsError('invalid-argument', 'Choose how you want to be paid.');
  const cfg = await configured();
  const option = railsFor(country, cfg).find((o) => o.rail === rail);
  if (!option) throw new HttpsError('failed-precondition', 'This payout method is not open in your country yet.');
  const holder = String(kyc.verifiedName ?? '').trim();
  const a = AFRICA[country];

  const pub: Record<string, unknown> = {
    rail, provider: option.provider, country, currency: a?.currency ?? 'USD', holderName: holder,
    createdAt: FieldValue.serverTimestamp(),
  };
  const secret: Record<string, unknown> = { uid };

  if (rail === 'stripe') {
    const acct = (await db().doc(`payout_accounts/${uid}`).get()).data();
    if (!acct?.stripeAccountId || acct.payoutsEnabled !== true) {
      throw new HttpsError('failed-precondition', 'Finish connecting your bank with Stripe first.');
    }
    Object.assign(pub, { label: 'Stripe payouts', last4: String(acct.stripeAccountId).slice(-4), currency: 'USD' });
    secret.stripeAccountId = acct.stripeAccountId;
  } else if (rail === 'mobile_money') {
    const net = a.networks.find((n) => n.id === req.data?.network);
    const msisdn = normalizeMsisdn(String(req.data?.msisdn ?? ''), country);
    if (!net) throw new HttpsError('invalid-argument', 'Pick your mobile money network.');
    if (!msisdn) throw new HttpsError('invalid-argument', `Enter a valid ${a.name} phone number.`);
    Object.assign(pub, { network: net.id, label: net.label, last4: msisdn.slice(-4) });
    Object.assign(secret, { msisdn, flwBank: net.flw, paystackBank: net.paystack ?? null });
  } else {
    const bankCode = String(req.data?.bankCode ?? '').trim();
    const bankName = String(req.data?.bankName ?? '').trim().slice(0, 80);
    const account = String(req.data?.accountNumber ?? '').replace(/\s/g, '');
    if (!bankCode || !/^[0-9A-Za-z]{6,20}$/.test(account)) throw new HttpsError('invalid-argument', 'Check your bank and account number.');
    Object.assign(pub, { bankCode, label: bankName || 'Bank account', last4: account.slice(-4) });
    Object.assign(secret, { bankCode, accountNumber: account });
  }

  const ref = db().collection(`payout_methods/${uid}/methods`).doc();
  const batch = db().batch();
  batch.set(ref, pub);
  batch.set(db().doc(`payout_method_secrets/${uid}_${ref.id}`), secret);
  await batch.commit();
  return { id: ref.id, ...pub, createdAt: null };
});

export const deletePayoutMethod = onCall(async (req) => {
  const uid = me(req);
  const id = String(req.data?.id ?? '');
  if (!id || id.includes('/')) throw new HttpsError('invalid-argument', 'Missing method.');
  const batch = db().batch();
  batch.delete(db().doc(`payout_methods/${uid}/methods/${id}`));
  batch.delete(db().doc(`payout_method_secrets/${uid}_${id}`));
  await batch.commit();
  return { ok: true };
});

// ───────────────────────────── Withdrawals ─────────────────────────────

const now = () => Timestamp.now();

async function notify(uid: string, id: string, title: string, body: string) {
  await db().collection('notifications').doc(id).set({
    userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
    title, body, deepLink: '/wallet', isRead: false, createdAt: FieldValue.serverTimestamp(),
  }).catch(() => undefined);
}

/** Moves a withdrawal to paid / failed / cancelled and settles the Diamonds. Idempotent. */
async function settle(wid: string, to: WithdrawalStatus, info: Record<string, unknown> = {}): Promise<boolean> {
  const ref = db().doc(`withdrawals/${wid}`);
  const done = await db().runTransaction(async (tx) => {
    const w = (await tx.get(ref)).data();
    if (!w || !canMove(w.status, to)) return null;
    const wallet = db().doc(`wallets/${w.uid}`);
    const d = Number(w.diamonds);
    tx.update(ref, { status: to, ...info, updatedAt: FieldValue.serverTimestamp(), timeline: FieldValue.arrayUnion({ status: to, at: now() }) });
    tx.update(wallet.collection('ledger').doc(`withdraw_${wid}`), { status: to === 'paid' ? 'completed' : to });
    if (to === 'paid') {
      ledgerOutbox(tx, `wpaid_${wid}`, 'withdrawal_paid', { uid: w.uid, diamonds: d, withdrawal_id: wid });
      // Cash side with the fee as its own posting (fees engine, services/ledger/config/fee_rules.json).
      ledgerOutbox(tx, `wcash_${wid}`, 'payout_cash', {
        uid: w.uid, withdrawal_id: wid, currency: 'USD', gross_minor: toMinor(Number(w.amountUsd), 'USD'),
        rail: w.rail, country: w.country ?? null, partner: w.provider ?? null,
      });
      tx.set(wallet, { lockedCoins: FieldValue.increment(-d), withdrawnCoins: FieldValue.increment(d), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    } else if (to === 'failed' || to === 'cancelled') {
      ledgerOutbox(tx, `wret_${wid}`, 'withdrawal_returned', { uid: w.uid, diamonds: d, withdrawal_id: wid });
      tx.set(wallet, { lockedCoins: FieldValue.increment(-d), availableCoins: FieldValue.increment(d), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      tx.set(wallet.collection('ledger').doc(`withdraw_${wid}_back`), {
        amount: d, type: 'withdrawal_returned', status: 'completed', referenceId: wid, createdAt: FieldValue.serverTimestamp(),
      });
    }
    return w;
  });
  if (!done) return false;
  const money = `${done.currency} ${Number(done.localAmount).toLocaleString('en-US')}`;
  if (to === 'paid') await notify(done.uid, `payout_paid_${wid}`, 'Money sent 🎉', `${money} is on its way to your ${done.methodLabel}. Keep creating!`);
  if (to === 'failed') await notify(done.uid, `payout_failed_${wid}`, 'Withdrawal didn’t go through', `Your Diamonds are back in your wallet. ${info.failureReason ?? ''}`.trim());
  return true;
}

// ───────────────────────────── Sending (payments/ adapters) ─────────────────────────────

/** How long after sending we ask the provider ourselves if no webhook came. */
const CHECK_AFTER_MS = 6 * 3600_000;

function adapterFor(provider: string, cfg: Awaited<ReturnType<typeof configured>>, secretRef: FirebaseFirestore.DocumentReference): PaymentProvider | null {
  if (provider === 'stripe' && cfg.keys.st) return new StripeTransferProvider(new Stripe(cfg.keys.st, { apiVersion: '2025-02-24.acacia' }));
  if (provider === 'flutterwave' && cfg.keys.flw) return new FlutterwaveProvider(cfg.keys.flw, fetch as unknown as FetchFn);
  if (provider === 'paystack' && cfg.keys.ps) {
    return new PaystackProvider(cfg.keys.ps, fetch as unknown as FetchFn,
      async () => ((await secretRef.get()).get('paystackRecipient') as string | undefined) ?? null,
      async (_req, code) => { await secretRef.update({ paystackRecipient: code }); });
  }
  return null;
}

/** The provider request for a withdrawal, in integer minor units. */
function payoutRequest(wid: string, w: FirebaseFirestore.DocumentData, s: FirebaseFirestore.DocumentData): PayoutRequest {
  const momo = w.rail === 'mobile_money';
  if (w.provider === 'stripe') {
    return { reference: wid, country: w.country, rail: 'stripe', currency: 'USD', amountMinor: toMinor(Number(w.netUsd), 'USD'), holderName: w.holderName, account: s.stripeAccountId, narration: 'Oneova creator payout' };
  }
  return {
    reference: wid, country: w.country, rail: w.rail, currency: w.currency,
    amountMinor: toMinor(Number(w.localAmount), w.currency), holderName: w.holderName,
    account: momo ? s.msisdn : s.accountNumber,
    bankCode: w.provider === 'paystack' ? (momo ? s.paystackBank : s.bankCode) : (momo ? s.flwBank : s.bankCode),
    narration: 'Oneova creator payout',
  };
}

/**
 * Sends a pending withdrawal to its provider.
 *   accepted → wait for the webhook (Stripe is final at once)
 *   rejected → failed, Diamonds go back (the provider took nothing)
 *   unknown  → stays processing with needsCheck; payoutReconcile asks the
 *              provider later. Never refunded on a guess.
 */
async function dispatch(wid: string): Promise<void> {
  const ref = db().doc(`withdrawals/${wid}`);
  const w = await db().runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data();
    if (!d || d.status !== 'pending' || d.review === true) return null;
    tx.update(ref, { status: 'processing', updatedAt: FieldValue.serverTimestamp(), timeline: FieldValue.arrayUnion({ status: 'processing', at: now() }) });
    return d;
  });
  if (!w) return;
  const secretRef = db().doc(`payout_method_secrets/${w.uid}_${w.methodId}`);
  const s = (await secretRef.get()).data();
  if (!s) {
    await settle(wid, 'failed', { failureReason: 'The payout method was removed.' });
    return;
  }
  const adapter = adapterFor(w.provider, await configured(), secretRef);
  if (!adapter) {
    await settle(wid, 'failed', { failureReason: 'Payouts are paused for this method.' });
    return;
  }
  const { outcome } = await routePayout([adapter], payoutRequest(wid, w, s));
  if (outcome.kind === 'accepted') {
    if (w.provider === 'stripe') {
      await ref.update({ providerRef: outcome.providerRef });
      await settle(wid, 'paid', { paidAt: FieldValue.serverTimestamp() });
      return;
    }
    await ref.update({
      providerRef: outcome.providerRef, sentAt: FieldValue.serverTimestamp(),
      needsCheck: true, checkAfter: Timestamp.fromMillis(Date.now() + CHECK_AFTER_MS), updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }
  if (outcome.kind === 'rejected') {
    logger.warn('payout refused', wid, outcome.reason);
    await settle(wid, 'failed', { failureReason: outcome.reason.slice(0, 200) });
    return;
  }
  logger.error('payout outcome unknown; will reconcile', wid, outcome.reason);
  await ref.update({
    sentAt: FieldValue.serverTimestamp(), needsCheck: true, checkAfter: Timestamp.fromMillis(Date.now() + 10 * 60_000),
    lastCheckNote: outcome.reason.slice(0, 200), updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Asks the provider about one withdrawal that is waiting for a check. */
async function reconcileOne(doc: FirebaseFirestore.QueryDocumentSnapshot, cfg: Awaited<ReturnType<typeof configured>>): Promise<ReconcileAction | null> {
  const w = doc.data();
  if (w.status !== 'processing') {
    await doc.ref.update({ needsCheck: false });
    return null;
  }
  const secretRef = db().doc(`payout_method_secrets/${w.uid}_${w.methodId}`);
  const adapter = adapterFor(w.provider, cfg, secretRef);
  if (!adapter) return null; // keys missing right now; try next run
  const policy = POLICY[w.provider] ?? { notFoundIsFinalAfterMs: null, idempotentRetry: false };
  let status: ProviderStatus = 'unknown';
  if (policy.idempotentRetry) {
    // Re-sending the same reference returns the original result (no second payout).
    const s = (await secretRef.get()).data();
    const r = s ? await adapter.payout(payoutRequest(doc.id, w, s)) : { kind: 'unknown' as const, reason: 'method removed' };
    status = r.kind === 'accepted' ? 'paid' : r.kind === 'rejected' && !r.retryable ? 'failed' : 'unknown';
  } else {
    status = (await adapter.status(doc.id)).status;
  }
  const age = Date.now() - ((w.sentAt as Timestamp | undefined)?.toMillis() ?? (w.updatedAt as Timestamp | undefined)?.toMillis() ?? Date.now());
  const action = reconcileAction(status, age, { notFoundIsFinalAfterMs: policy.notFoundIsFinalAfterMs });
  if (action === 'settle_paid') await settle(doc.id, 'paid', { paidAt: FieldValue.serverTimestamp(), needsCheck: false });
  else if (action === 'settle_failed') await settle(doc.id, 'failed', { failureReason: 'The network didn’t complete it.', needsCheck: false });
  else if (action === 'review') {
    await doc.ref.update({ needsCheck: false, review: true, reviewReasons: FieldValue.arrayUnion('provider_status_unknown'), updatedAt: FieldValue.serverTimestamp() });
  } else {
    await doc.ref.update({ checkAfter: Timestamp.fromMillis(Date.now() + 30 * 60_000), checks: FieldValue.increment(1), lastCheckNote: status });
  }
  return action;
}

/** Withdrawals whose outcome we don't know yet, or whose webhook never came. */
export const payoutReconcile = onSchedule('every 15 minutes', async () => {
  const due = (await db().collection('withdrawals').where('needsCheck', '==', true).limit(200).get())
    .docs.filter((d) => ((d.get('checkAfter') as Timestamp | undefined)?.toMillis() ?? 0) <= Date.now()).slice(0, 50);
  if (!due.length) return;
  const cfg = await configured();
  for (const d of due) {
    try {
      await reconcileOne(d, cfg);
    } catch (e: any) {
      logger.error('payout reconcile failed', d.id, e?.message ?? e);
    }
  }
});

export const requestWithdrawal = onCall({ timeoutSeconds: 60 }, async (req) => {
  const uid = me(req);
  const key = String(req.data?.idempotencyKey ?? '');
  if (key.length < 8 || key.length > 80) throw new HttpsError('invalid-argument', 'Missing request id.');
  const wid = crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 32);
  const ref = db().doc(`withdrawals/${wid}`);
  const existing = await ref.get();
  if (existing.exists) return { id: wid, status: existing.get('status'), duplicate: true };

  const kyc = await verifiedKyc(uid);
  await releaseMatured(uid);
  const methodId = String(req.data?.methodId ?? '');
  const method = methodId && !methodId.includes('/') ? (await db().doc(`payout_methods/${uid}/methods/${methodId}`).get()).data() : null;
  if (!method) throw new HttpsError('invalid-argument', 'Choose where to send the money.');
  const cfg = await configured();
  if (!railsFor(method.country, cfg).some((o) => o.rail === method.rail && o.provider === method.provider)) {
    throw new HttpsError('failed-precondition', 'This payout method is paused right now. Try another one.');
  }

  const diamonds = Math.floor(Number(req.data?.diamonds));
  const amountUsd = Math.round(diamondsToUsd(diamonds) * 100) / 100;
  if (!Number.isFinite(diamonds) || amountUsd < MIN_WITHDRAW_USD) throw new HttpsError('invalid-argument', 'Choose an amount to withdraw.');
  if (amountUsd > MAX_WITHDRAW_USD) throw new HttpsError('invalid-argument', `You can withdraw up to $${MAX_WITHDRAW_USD} at a time.`);

  // Velocity: one open withdrawal at a time and a few per day.
  const recent = await db().collection('withdrawals').where('uid', '==', uid).orderBy('createdAt', 'desc').limit(20).get();
  const open = recent.docs.find((d) => ['pending', 'processing'].includes(d.get('status')));
  if (open) throw new HttpsError('failed-precondition', 'You already have a withdrawal on the way. Wait for it to finish.');
  const today = recent.docs.filter((d) => ((d.get('createdAt') as Timestamp | undefined)?.toMillis() ?? Date.now()) > Date.now() - 86400_000);
  if (today.length >= MAX_REQUESTS_PER_DAY) throw new HttpsError('resource-exhausted', 'You reached today’s withdrawal limit. Try again tomorrow.');
  const paidBefore = recent.docs.filter((d) => d.get('status') === 'paid').length;

  const [user, profile, deviceAge] = await Promise.all([
    getAuth().getUser(uid),
    db().doc(`payout_profiles/${uid}`).get(),
    touchDevice(uid, req.data?.deviceId),
  ]);
  const locAt = profile.get('locationAt') as Timestamp | undefined;
  const locationCountry = locAt && Date.now() - locAt.toMillis() < 3 * 86400_000 ? (profile.get('locationCountry') as string) : null;
  // Ova Guard can pause withdrawals after a suspicious sign-in (security_state).
  const guard = await db().doc(`security_state/${uid}`).get();
  const frozen = (guard.get('withdrawalsFrozenUntil') as Timestamp | undefined)?.toMillis() ?? 0;
  if (frozen > Date.now()) {
    throw new HttpsError('failed-precondition', `Withdrawals are paused for your safety: ${guard.get('withdrawalsFrozenReason') ?? 'unusual sign-in'}. See Security in your profile.`);
  }
  // A refunded coin pack paid for gifts this creator received (coins/voidedPurchases.ts).
  const hold = (await db().doc(`payout_holds/${uid}`).get()).get('reasons') as string[] | undefined;
  const reasons = fraudReasons({
    amountUsd,
    accountAgeDays: (Date.now() - new Date(user.metadata.creationTime).getTime()) / 86400_000,
    deviceAgeHours: deviceAge,
    paidBefore,
    kycCountry: cc(kyc.country),
    locationCountry,
    payoutCountry: method.country,
  });
  if (Array.isArray(hold)) for (const r of hold) if (!reasons.includes(r)) reasons.push(r);

  const feeUsd = payoutFeeUsd(method.rail, amountUsd);
  const netUsd = Math.round((amountUsd - feeUsd) * 100) / 100;
  const rate = method.provider === 'stripe' ? 1 : await usdRate(method.currency);
  const currency = method.provider === 'stripe' ? 'USD' : method.currency;
  const localAmount = roundLocal(netUsd * rate, currency);
  // Any amount works as long as at least 1 unit of the payout currency arrives after the fee.
  if (localAmount < 1) {
    throw new HttpsError('invalid-argument', `After the ${currency} ${roundLocal(feeUsd * rate, currency)} payout fee nothing would arrive. Withdraw a little more.`);
  }
  const wallet = db().doc(`wallets/${uid}`);

  await db().runTransaction(async (tx) => {
    const [w, again] = await Promise.all([tx.get(wallet), tx.get(ref)]);
    if (again.exists) return;
    const available = Number(w.get('availableCoins') ?? 0);
    if (available < diamonds) throw new HttpsError('failed-precondition', 'You don’t have that many withdrawable Diamonds yet.');
    tx.set(wallet, { availableCoins: FieldValue.increment(-diamonds), lockedCoins: FieldValue.increment(diamonds), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    ledgerOutbox(tx, `wlock_${wid}`, 'withdrawal_lock', { uid, diamonds, withdrawal_id: wid });
    tx.set(wallet.collection('ledger').doc(`withdraw_${wid}`), {
      amount: -diamonds, type: 'withdrawal', status: 'pending', referenceId: wid, createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(ref, {
      uid, status: 'pending', diamonds, amountUsd, feeUsd, netUsd, currency, localAmount, fxRate: rate,
      rail: method.rail, provider: method.provider as Provider, methodId, methodLabel: `${method.label} ••${method.last4}`,
      holderName: method.holderName, country: method.country,
      review: reasons.length > 0, reviewReasons: reasons,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      timeline: [{ status: 'pending', at: now() }],
    });
  });

  if (!reasons.length) await dispatch(wid);
  const final = await ref.get();
  return { id: wid, status: final.get('status'), review: reasons.length > 0, localAmount, currency, netUsd, feeUsd };
});

export const cancelWithdrawal = onCall(async (req) => {
  const uid = me(req);
  const id = String(req.data?.id ?? '');
  const w = id && !id.includes('/') ? (await db().doc(`withdrawals/${id}`).get()).data() : null;
  if (!w || w.uid !== uid) throw new HttpsError('not-found', 'Withdrawal not found.');
  if (!(await settle(id, 'cancelled'))) throw new HttpsError('failed-precondition', 'It is already being sent and can’t be cancelled.');
  return { ok: true };
});

export const reviewWithdrawal = onCall(async (req) => {
  const uid = me(req);
  if ((await db().doc(`users/${uid}`).get()).get('role') !== 'admin') throw new HttpsError('permission-denied', 'Admins only.');
  const id = String(req.data?.id ?? '');
  if (!id || id.includes('/')) throw new HttpsError('invalid-argument', 'Missing withdrawal.');
  const current = (await db().doc(`withdrawals/${id}`).get()).data();
  if (req.data?.approve === true && current?.status === 'processing') {
    // Sent, but the provider's status was unclear: the reviewer confirmed it in the provider dashboard.
    await settle(id, 'paid', { paidAt: FieldValue.serverTimestamp(), review: false, reviewedBy: uid, reviewedAt: FieldValue.serverTimestamp() });
  } else if (req.data?.approve === true) {
    await db().doc(`withdrawals/${id}`).update({ review: false, reviewedBy: uid, reviewedAt: FieldValue.serverTimestamp() });
    await dispatch(id);
  } else {
    await settle(id, 'failed', { failureReason: 'We couldn’t confirm this request. Contact support if this was you.', reviewedBy: uid });
  }
  return { ok: true };
});

// ───────────────────────────── Provider webhooks ─────────────────────────────

/** Flutterwave transfer.completed → paid / failed (status re-read from the API). */
export const flutterwaveWebhook = onRequest(async (req, res) => {
  const [hash, key] = await Promise.all([optionalSecret('FLUTTERWAVE_WEBHOOK_HASH'), optionalSecret('FLUTTERWAVE_SECRET_KEY')]);
  const sig = String(req.headers['verif-hash'] ?? '');
  if (!hash || !key || sig.length !== hash.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(hash))) {
    res.status(401).send('unauthorized');
    return;
  }
  try {
    const id = req.body?.data?.id;
    if (req.body?.event === 'transfer.completed' && id) {
      const t = await fetch(`${FLW}/transfers/${encodeURIComponent(String(id))}`, { headers: { Authorization: `Bearer ${key}` } }).then((r) => r.json()) as any;
      const ref = String(t?.data?.reference ?? '');
      if (/^[0-9a-f]{32}$/.test(ref)) {
        if (t.data.status === 'SUCCESSFUL') await settle(ref, 'paid', { paidAt: FieldValue.serverTimestamp() });
        else if (t.data.status === 'FAILED') await settle(ref, 'failed', { failureReason: String(t.data.complete_message ?? 'The network declined it.').slice(0, 200) });
      }
    }
    res.status(200).send('ok');
  } catch (e: any) {
    logger.error('flutterwave webhook failed', e?.message ?? e);
    res.status(500).send('error');
  }
});

/** Paystack transfer.success / failed / reversed (HMAC-SHA512 signed). */
export const paystackWebhook = onRequest(async (req, res) => {
  const key = await optionalSecret('PAYSTACK_SECRET_KEY');
  const sig = String(req.headers['x-paystack-signature'] ?? '');
  const want = key ? crypto.createHmac('sha512', key).update(req.rawBody).digest('hex') : '';
  if (!key || sig.length !== want.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want))) {
    res.status(401).send('unauthorized');
    return;
  }
  try {
    const ref = String(req.body?.data?.reference ?? '');
    if (/^[0-9a-f]{32}$/.test(ref)) {
      if (req.body.event === 'transfer.success') await settle(ref, 'paid', { paidAt: FieldValue.serverTimestamp() });
      if (req.body.event === 'transfer.failed' || req.body.event === 'transfer.reversed') {
        await settle(ref, 'failed', { failureReason: String(req.body.data?.reason ?? 'The bank or network declined it.').slice(0, 200) });
      }
    }
    res.status(200).send('ok');
  } catch (e: any) {
    logger.error('paystack webhook failed', e?.message ?? e);
    res.status(500).send('error');
  }
});

export { settle as settleWithdrawal };
