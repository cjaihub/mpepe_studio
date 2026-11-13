/**
 * Scan to pay: merchant QR codes (`pay_qr/{code}`, server-only).
 *
 *   merchant → payQrCreate    a shop code (payer types the amount) or a one-time
 *                             code with an amount (15 minutes, paid once)
 *   payer    → payQrResolve   who is being paid and how much, before paying
 *   payer    → payCreate({ purpose: 'merchant', refId: code, amount? })
 *   merchant → payQrList / payQrDisable
 *
 * The QR holds only an unguessable code; the merchant, amount and currency
 * come from the server. Receiving money needs a verified identity (KYC), and
 * lands in the merchant's Oneova balance minus the merchant fee, so it is open
 * only where the stored balance is (PAY_WALLET_ENABLED / sandbox).
 */
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { limit } from '../guard/protect';
import { toMajor, toMinor } from '../payments/provider';
import { PAY_QR_PREFIX, QR_ONE_TIME_TTL_MS, currencyFor, qrCodeFrom, qrProblem } from './payLogic';
import { payRuntime } from './payConfig';
import { countryOf } from './intents';

const db = () => getFirestore();
export const qrRef = (code: string) => db().doc(`pay_qr/${code}`);

function me(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

/** Upper bound for one QR payment, in major units of the currency (anti-abuse, KYC tier 1). */
const MAX_MAJOR = 1_000_000;

export interface MerchantView {
  code: string;
  merchantUid: string;
  name: string;
  avatarUrl: string | null;
  verified: boolean;
  label: string | null;
  country: string;
  currency: string;
  amountMinor: number | null;
  amount: number | null;
  oneTime: boolean;
}

async function merchantProfile(uid: string) {
  const [u, kyc] = await Promise.all([db().doc(`users/${uid}`).get(), db().doc(`kyc/${uid}`).get()]);
  const p = u.data() ?? {};
  const avatar = [p.avatarUrl, p.photoUrl, p.photoURL].find((v) => typeof v === 'string' && v.startsWith('http')) ?? null;
  return {
    name: String(p.businessName || p.fullName || p.displayName || p.username || 'Oneova merchant').slice(0, 80),
    avatarUrl: avatar as string | null,
    verified: kyc.get('status') === 'verified',
  };
}

export function viewOf(code: string, q: FirebaseFirestore.DocumentData, m: { name: string; avatarUrl: string | null; verified: boolean }): MerchantView {
  const amountMinor = typeof q.amountMinor === 'number' ? q.amountMinor : null;
  return {
    code, merchantUid: q.merchantUid, name: m.name, avatarUrl: m.avatarUrl, verified: m.verified,
    label: q.label ?? null, country: q.country, currency: q.currency, amountMinor,
    amount: amountMinor == null ? null : toMajor(amountMinor, q.currency), oneTime: q.oneTime === true,
  };
}

export const payQrCreate = onCall(async (req) => {
  const uid = me(req);
  await limit(uid, 'pay_qr_create', 30, 3600_000);
  const rt = await payRuntime();
  if (!rt.cfg.wallet) throw new HttpsError('failed-precondition', 'Receiving payments opens soon in your country.');
  const kyc = await db().doc(`kyc/${uid}`).get();
  if (kyc.get('status') !== 'verified') throw new HttpsError('failed-precondition', 'Verify your identity first to receive payments.');
  const country = await countryOf(uid);
  const currency = currencyFor(country);
  const raw = req.data?.amount;
  let amountMinor: number | null = null;
  if (raw != null && raw !== '') {
    const amount = Number(raw);
    amountMinor = Number.isFinite(amount) ? toMinor(amount, currency) : 0;
    if (amountMinor < toMinor(1, currency) || amountMinor > toMinor(MAX_MAJOR, currency)) throw new HttpsError('invalid-argument', 'Enter an amount to receive.');
  }
  const label = typeof req.data?.label === 'string' ? req.data.label.trim().slice(0, 60) || null : null;
  const oneTime = amountMinor != null;
  const code = crypto.randomBytes(16).toString('base64url').slice(0, 22);
  await qrRef(code).set({
    merchantUid: uid, country, currency, amountMinor, label, oneTime, active: true, paid: false,
    paidCount: 0, receivedMinor: 0,
    expiresAt: oneTime ? Timestamp.fromMillis(Date.now() + QR_ONE_TIME_TTL_MS) : null,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  const m = await merchantProfile(uid);
  return { ...viewOf(code, (await qrRef(code).get()).data()!, m), qr: `${PAY_QR_PREFIX}${code}` };
});

export const payQrResolve = onCall(async (req) => {
  const uid = me(req);
  await limit(uid, 'pay_qr_resolve', 60, 600_000);
  const code = qrCodeFrom(String(req.data?.qr ?? req.data?.code ?? ''));
  if (!code) throw new HttpsError('invalid-argument', 'This isn’t an Oneova Pay code.');
  const q = (await qrRef(code).get()).data();
  const problem = qrProblem(q);
  if (problem) throw new HttpsError('failed-precondition', problem);
  if (q!.merchantUid === uid) throw new HttpsError('failed-precondition', 'This is your own code.');
  return viewOf(code, q!, await merchantProfile(q!.merchantUid));
});

export const payQrList = onCall(async (req) => {
  const uid = me(req);
  const snap = await db().collection('pay_qr').where('merchantUid', '==', uid).orderBy('createdAt', 'desc').limit(30).get();
  const m = await merchantProfile(uid);
  return {
    codes: snap.docs.map((d) => ({
      ...viewOf(d.id, d.data(), m), qr: `${PAY_QR_PREFIX}${d.id}`, active: d.get('active') === true && !qrProblem(d.data()),
      paidCount: Number(d.get('paidCount') ?? 0), receivedMinor: Number(d.get('receivedMinor') ?? 0),
    })),
  };
});

export const payQrDisable = onCall(async (req) => {
  const uid = me(req);
  const code = qrCodeFrom(String(req.data?.code ?? ''));
  if (!code) throw new HttpsError('invalid-argument', 'Missing code.');
  await db().runTransaction(async (tx) => {
    const q = (await tx.get(qrRef(code))).data();
    if (!q || q.merchantUid !== uid) throw new HttpsError('not-found', 'Code not found.');
    tx.update(qrRef(code), { active: false, updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
});
