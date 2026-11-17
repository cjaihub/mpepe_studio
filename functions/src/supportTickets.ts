import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { callerIp, limit } from './guard/protect';

const db = () => getFirestore();

const ALLOWED_CATEGORIES = new Set([
  'account',
  'live',
  'interaction',
  'desktop',
  'post',
  'monetization',
  'feed',
  'privacy',
  'other',
]);

function sha256Hex(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function generateTrackingCode(): string {
  const num = crypto.randomInt(100000, 999999);
  return `OVA-${num}`;
}

function generateAccessPin(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) {
    out += alphabet[crypto.randomInt(0, alphabet.length)];
  }
  return out;
}

export const submitSupportTicket = onCall(async (request) => {
  const ip = callerIp(request);
  await limit(ip, 'support_ticket_ip', 8, 60 * 60000);

  const authUid =
    request.auth && request.auth.token?.firebase?.sign_in_provider !== 'anonymous'
      ? request.auth.uid
      : '';
  if (authUid) {
    await limit(authUid, 'support_ticket_uid', 15, 24 * 3600000);
  }

  const raw = (request.data ?? {}) as Record<string, unknown>;
  const categoryRaw = String(raw.category ?? 'other').trim().toLowerCase();
  const category = ALLOWED_CATEGORIES.has(categoryRaw) ? categoryRaw : 'other';
  const subject = String(raw.subject ?? '').trim();
  const message = String(raw.message ?? '').trim();
  const contactEmail = String(raw.contactEmail ?? '').trim().slice(0, 120);

  if (subject.length < 3 || subject.length > 140) {
    throw new HttpsError(
      'invalid-argument',
      'Subject must be between 3 and 140 characters.',
    );
  }
  if (message.length < 10 || message.length > 2000) {
    throw new HttpsError(
      'invalid-argument',
      'Message must be between 10 and 2000 characters.',
    );
  }
  if (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
    throw new HttpsError('invalid-argument', 'Please provide a valid email address.');
  }

  const trackingCode = generateTrackingCode();
  const accessPin = generateAccessPin();
  const ref = db().collection('support_tickets').doc();

  await ref.set({
    uid: authUid,
    trackingCode,
    pinHash: sha256Hex(`${trackingCode}:${accessPin}`),
    category,
    subject,
    message,
    contactEmail,
    status: 'open',
    adminReply: '',
    repliedByUid: '',
    repliedByName: '',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    ok: true,
    ticketId: ref.id,
    trackingCode,
    accessPin,
    status: 'open',
  };
});

export const lookupSupportTicket = onCall(async (request) => {
  const ip = callerIp(request);
  await limit(ip, 'support_lookup_ip', 20, 10 * 60000);

  const raw = (request.data ?? {}) as Record<string, unknown>;
  const trackingCode = String(raw.trackingCode ?? '')
    .trim()
    .toUpperCase();
  const accessPin = String(raw.accessPin ?? '')
    .trim()
    .toUpperCase();

  if (!/^OVA-\d{6}$/.test(trackingCode) || !/^[A-Z0-9]{6}$/.test(accessPin)) {
    throw new HttpsError('invalid-argument', 'Enter a valid tracking code and 6-character PIN.');
  }

  const snap = await db()
    .collection('support_tickets')
    .where('trackingCode', '==', trackingCode)
    .limit(1)
    .get();

  if (snap.empty) {
    throw new HttpsError('not-found', 'Ticket not found or PIN mismatch.');
  }

  const data = snap.docs[0].data();
  const expectedHash = String(data.pinHash ?? '');
  const providedHash = sha256Hex(`${trackingCode}:${accessPin}`);
  if (
    expectedHash.length !== providedHash.length ||
    !crypto.timingSafeEqual(Buffer.from(expectedHash), Buffer.from(providedHash))
  ) {
    throw new HttpsError('not-found', 'Ticket not found or PIN mismatch.');
  }

  const updatedAt =
    data.updatedAt && typeof data.updatedAt.toDate === 'function'
      ? data.updatedAt.toDate().toISOString()
      : null;

  return {
    ok: true,
    trackingCode: data.trackingCode,
    category: data.category,
    subject: data.subject,
    status: data.status,
    adminReply: data.adminReply || '',
    updatedAt,
  };
});
