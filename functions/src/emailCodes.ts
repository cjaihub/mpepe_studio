/**
 * Email one-time codes, sent from the team's Gmail (see mailer.ts).
 *
 *   sendEmailCode({ purpose, email?, deviceLabel?, platform? })
 *   verifyEmailCode({ purpose, email?, code })
 *
 * Purposes (both need a signed-in user):
 *   verify_email     signed in; marks the email verified (or adopts the new
 *                    email the user just proved they own).
 *   sensitive_action signed in; a fresh "it's really me" check before risky
 *                    changes (stamps security_state/{uid}.stepUpAt).
 *
 * Codes: 6 digits, stored only as a salted hash, 10 minutes, one use,
 * 5 wrong tries. Sending: one per minute and 5 per hour per address, plus a
 * per-IP cap.
 *
 * There is deliberately no "sign in with an email code": Oneova sign-in needs
 * two checks (password + SMS code), and a passwordless email login would skip
 * them. SMS login codes are auto-filled in the app via Google's SMS User
 * Consent API instead.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getAuth, UserRecord } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { codeEmail, CodePurpose, Fact } from './mailTemplates';
import { sendMail } from './mailer';
import { createSecurityLink } from './securityMail';

const db = () => getFirestore();
const CODE_MINUTES = 10;
const MAX_TRIES = 5;
const RESEND_SECONDS = 60;
const MAX_PER_HOUR = 5;
const MAX_PER_IP_HOUR = 20;

const sha = (s: string) => crypto.createHash('sha256').update(s).digest('hex');
const PURPOSES: CodePurpose[] = ['verify_email', 'sensitive_action'];

function cleanEmail(v: unknown): string | null {
  const e = String(v ?? '').trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) && e.length <= 254 ? e : null;
}

function purposeOf(v: unknown): CodePurpose {
  const p = String(v ?? '') as CodePurpose;
  if (!PURPOSES.includes(p)) throw new HttpsError('invalid-argument', 'Unknown code purpose.');
  return p;
}

function maskIp(ip: string | null): string {
  if (!ip) return '';
  if (ip.includes(':')) return ip.split(':').slice(0, 3).join(':') + ':…';
  const p = ip.split('.');
  return p.length === 4 ? `${p[0]}.${p[1]}.${p[2]}.x` : '';
}

async function resolveTarget(data: Record<string, unknown>, authUid?: string): Promise<{ email: string; user: UserRecord }> {
  if (!authUid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const user = await getAuth().getUser(authUid);
  const email = cleanEmail(data.email) ?? cleanEmail(user.email);
  if (!email) throw new HttpsError('failed-precondition', 'Add an email address to your account first.');
  return { email, user };
}

export const sendEmailCode = onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const purpose = purposeOf(data.purpose);
  const { email, user } = await resolveTarget(data, request.auth?.uid);
  const ip = request.rawRequest?.ip ?? null;
  const now = Date.now();

  // Per-IP cap (all addresses).
  if (ip) {
    const ipRef = db().collection('email_code_ips').doc(sha(ip));
    const ok = await db().runTransaction(async (tx) => {
      const s = await tx.get(ipRef);
      const start = (s.get('windowStart') as number | undefined) ?? 0;
      const count = now - start > 3_600_000 ? 0 : ((s.get('count') as number | undefined) ?? 0);
      if (count >= MAX_PER_IP_HOUR) return false;
      tx.set(ipRef, { windowStart: count === 0 ? now : start, count: count + 1 }, { merge: true });
      return true;
    });
    if (!ok) throw new HttpsError('resource-exhausted', 'Too many codes from this network. Try again in an hour.');
  }

  const docId = sha(`${email}|${purpose}`);
  const ref = db().collection('email_codes').doc(docId);
  const code = crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');

  const limit = await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const sentAt = (s.get('sentAt') as number | undefined) ?? 0;
    const windowStart = (s.get('windowStart') as number | undefined) ?? 0;
    const inWindow = now - windowStart < 3_600_000;
    const sends = inWindow ? ((s.get('sends') as number | undefined) ?? 0) : 0;
    if (now - sentAt < RESEND_SECONDS * 1000) return { wait: Math.ceil((RESEND_SECONDS * 1000 - (now - sentAt)) / 1000) };
    if (sends >= MAX_PER_HOUR) return { wait: Math.ceil((3_600_000 - (now - windowStart)) / 1000) };
    tx.set(ref, {
      purpose,
      uid: user.uid,
      codeHash: sha(`${code}:${docId}`),
      expiresAt: Timestamp.fromMillis(now + CODE_MINUTES * 60_000),
      tries: 0,
      sentAt: now,
      windowStart: inWindow ? windowStart : now,
      sends: sends + 1,
    });
    return { wait: 0 };
  });
  if (limit.wait > 0) {
    throw new HttpsError('resource-exhausted', `Please wait ${limit.wait < 120 ? `${limit.wait} seconds` : `${Math.ceil(limit.wait / 60)} minutes`} before asking for another code.`);
  }

  const from: Fact[] = [
    { label: 'Device', value: [data.deviceLabel, data.platform].filter((x) => typeof x === 'string' && x).join(' · ').slice(0, 80) },
    { label: 'IP address', value: maskIp(ip) },
    { label: 'Time', value: new Date(now).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }) + ' UTC' },
  ];
  // A code the user didn't ask for while signed in means someone else has the session.
  const secureUrl = await createSecurityLink(user.uid, null, 'secure');
  const sent = await sendMail(email, codeEmail({ code, purpose, minutes: CODE_MINUTES, requestedFrom: from, secureUrl }));
  if (!sent) {
    await ref.delete();
    throw new HttpsError('unavailable', 'We couldn’t send the email right now. Try again in a minute.');
  }
  return { ok: true, expiresInMinutes: CODE_MINUTES, resendInSeconds: RESEND_SECONDS };
});

export const verifyEmailCode = onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const purpose = purposeOf(data.purpose);
  const code = String(data.code ?? '').replace(/\D/g, '');
  if (code.length !== 6) throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
  const { email, user } = await resolveTarget(data, request.auth?.uid);

  const docId = sha(`${email}|${purpose}`);
  const ref = db().collection('email_codes').doc(docId);
  const result = await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists || !s.get('codeHash')) return { error: 'expired' as const };
    if ((s.get('expiresAt') as Timestamp).toMillis() < Date.now()) {
      tx.update(ref, { codeHash: null });
      return { error: 'expired' as const };
    }
    const tries = (s.get('tries') as number) ?? 0;
    if (tries >= MAX_TRIES) return { error: 'locked' as const };
    const expected = Buffer.from(String(s.get('codeHash')), 'hex');
    const given = Buffer.from(sha(`${code}:${docId}`), 'hex');
    if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) {
      tx.update(ref, { tries: tries + 1 });
      return { error: 'wrong' as const, left: MAX_TRIES - tries - 1 };
    }
    tx.update(ref, { codeHash: null, usedAt: FieldValue.serverTimestamp() });
    return { error: null };
  });

  if (result.error === 'expired') throw new HttpsError('deadline-exceeded', 'This code expired. Ask for a new one.');
  if (result.error === 'locked') throw new HttpsError('resource-exhausted', 'Too many wrong tries. Ask for a new code.');
  if (result.error === 'wrong') {
    throw new HttpsError('invalid-argument', result.left > 0 ? `That code isn’t right. ${result.left} tries left.` : 'Too many wrong tries. Ask for a new code.');
  }
  switch (purpose) {
    case 'verify_email':
      await getAuth().updateUser(user.uid, { email, emailVerified: true });
      return { ok: true, email };
    case 'sensitive_action':
      await db().collection('security_state').doc(user.uid).set({ stepUpAt: FieldValue.serverTimestamp() }, { merge: true });
      return { ok: true };
  }
});
