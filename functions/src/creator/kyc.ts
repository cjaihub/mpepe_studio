/**
 * Identity verification (KYC) before a creator's first withdrawal, with
 * Stripe Identity: government ID + live selfie, captured on Stripe's hosted
 * page. Oneova never receives or stores the images; `kyc/{uid}` keeps only the
 * status, the name and country on the ID, and the document type.
 *
 *   app → kycStart            VerificationSession → hosted url
 *   app → kycRefresh          re-reads the session (after returning to the app)
 *   Stripe → creatorStripeWebhook  identity.verification_session.* and transfer.reversed
 *
 * Secrets: STRIPE_SECRET_KEY, STRIPE_PAYOUTS_WEBHOOK_SECRET (a separate
 * webhook endpoint from Biz commerce, so each has its own signing secret).
 */
import Stripe from 'stripe';
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { optionalSecret } from '../optionalSecrets';
import { settleWithdrawal } from './payouts';

const db = () => getFirestore();
const RETURN_URL = 'https://mpepe-2b4bd.web.app/';

async function stripe(): Promise<Stripe> {
  const key = await optionalSecret('STRIPE_SECRET_KEY');
  if (!key) throw new HttpsError('failed-precondition', 'Identity checks are being set up. Please try again soon.');
  return new Stripe(key, { apiVersion: '2025-02-24.acacia' });
}

const STATUS: Record<string, string> = {
  verified: 'verified', processing: 'processing', requires_input: 'requires_input', canceled: 'canceled',
};

async function store(uid: string, s: Stripe.Identity.VerificationSession) {
  const out = s.verified_outputs;
  const name = [out?.first_name, out?.last_name].filter(Boolean).join(' ').trim();
  const report = typeof s.last_verification_report === 'object' ? s.last_verification_report : null;
  const idCountry = report?.document?.issuing_country ?? out?.address?.country ?? null;
  await db().doc(`kyc/${uid}`).set({
    uid,
    provider: 'stripe_identity',
    sessionId: s.id,
    status: STATUS[s.status] ?? 'processing',
    lastError: s.last_error?.reason ?? null,
    ...(s.status === 'verified' ? {
      verifiedName: name || null,
      country: idCountry,
      documentType: report?.document?.type ?? null,
      verifiedAt: FieldValue.serverTimestamp(),
    } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

export const kycStart = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const current = (await db().doc(`kyc/${uid}`).get()).data();
  if (current?.status === 'verified') return { status: 'verified' };
  const s = await stripe();
  // Reuse an open session so a second tap continues the same check.
  if (current?.sessionId && ['requires_input', 'processing'].includes(current.status)) {
    const old = await s.identity.verificationSessions.retrieve(current.sessionId);
    if (old.status === 'requires_input' && old.url) return { status: old.status, url: old.url };
    if (old.status === 'processing') return { status: 'processing' };
  }
  const session = await s.identity.verificationSessions.create({
    type: 'document',
    options: { document: { require_live_capture: true, require_matching_selfie: true, allowed_types: ['passport', 'id_card', 'driving_license'] } },
    metadata: { uid },
    return_url: RETURN_URL,
  });
  await db().doc(`kyc/${uid}`).set({
    uid, provider: 'stripe_identity', sessionId: session.id, status: 'requires_input',
    startedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { status: 'requires_input', url: session.url };
});

export const kycRefresh = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const current = (await db().doc(`kyc/${uid}`).get()).data();
  if (!current?.sessionId) return { status: 'none' };
  if (current.status === 'verified') return { status: 'verified' };
  const session = await (await stripe()).identity.verificationSessions.retrieve(current.sessionId, { expand: ['verified_outputs', 'last_verification_report'] });
  await store(uid, session);
  return { status: STATUS[session.status] ?? 'processing' };
});

export const creatorStripeWebhook = onRequest(async (req, res) => {
  const secret = await optionalSecret('STRIPE_PAYOUTS_WEBHOOK_SECRET');
  if (!secret) {
    res.status(503).send('not configured');
    return;
  }
  let event: Stripe.Event;
  try {
    event = (await stripe()).webhooks.constructEvent(req.rawBody, String(req.headers['stripe-signature'] ?? ''), secret);
  } catch (e: any) {
    logger.warn('creator webhook signature failed', e?.message);
    res.status(400).send('bad signature');
    return;
  }
  try {
    if (event.type.startsWith('identity.verification_session.')) {
      const s = event.data.object as Stripe.Identity.VerificationSession;
      const uid = s.metadata?.uid;
      if (uid) {
        const full = await (await stripe()).identity.verificationSessions.retrieve(s.id, { expand: ['verified_outputs', 'last_verification_report'] });
        await store(uid, full);
        if (full.status === 'verified') {
          await db().collection('notifications').doc(`kyc_ok_${uid}`).set({
            userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
            title: 'You’re verified ✅', body: 'You can now withdraw your earnings.', deepLink: '/wallet/withdraw',
            isRead: false, createdAt: FieldValue.serverTimestamp(),
          });
        }
      }
    } else if (event.type === 'transfer.reversed') {
      const t = event.data.object as Stripe.Transfer;
      const wid = t.metadata?.withdrawalId;
      if (wid) await settleWithdrawal(wid, 'failed', { failureReason: 'The transfer was reversed.' });
    }
    res.status(200).send('ok');
  } catch (e: any) {
    logger.error('creator webhook failed', event.type, e?.message ?? e);
    res.status(500).send('error');
  }
});
