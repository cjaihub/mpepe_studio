/**
 * Shared endpoint protection: who is calling, per-user / per-IP limits,
 * admin checks and the private contact index used instead of public
 * users.phoneNumber / users.email queries.
 */
import * as crypto from 'crypto';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const db = () => getFirestore();
const sha = (v: string) => crypto.createHash('sha256').update(v).digest('hex');

export function requireAccount(request: CallableRequest<unknown>): string {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (auth.token.firebase?.sign_in_provider === 'anonymous') throw new HttpsError('permission-denied', 'Sign in to your account first.');
  return auth.uid;
}

export function callerIp(request: CallableRequest<unknown>): string | null {
  const fwd = String(request.rawRequest?.headers?.['x-forwarded-for'] ?? '');
  return fwd.split(',')[0].trim() || request.rawRequest?.ip || null;
}

/**
 * Fixed-window limiter in `security_rate/{bucket}_{hash(key)}` (deny-all to
 * clients; TTL field `expiresAt`). Throws resource-exhausted when over.
 */
export async function limit(key: string | null, bucket: string, max: number, windowMs: number): Promise<void> {
  if (!key) return;
  const ref = db().collection('security_rate').doc(`${bucket}_${sha(key).slice(0, 32)}`);
  const ok = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const start = Number(snap.get('start') ?? 0);
    const count = Date.now() - start < windowMs ? Number(snap.get('count') ?? 0) : 0;
    if (count >= max) return false;
    tx.set(ref, {
      start: count === 0 ? Date.now() : start,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(Date.now() + Math.max(windowMs, 3600000)),
    });
    return true;
  });
  if (!ok) throw new HttpsError('resource-exhausted', 'Too many requests. Please wait a little and try again.');
}

/** Same rule as firestore.rules isAdmin(), plus an `admin` custom claim. */
export async function isAdmin(uid: string, claims?: Record<string, unknown>): Promise<boolean> {
  if (claims?.admin === true) return true;
  return (await db().collection('users').doc(uid).get()).get('role') === 'admin';
}

export async function requireAdmin(request: CallableRequest<unknown>): Promise<string> {
  const uid = requireAccount(request);
  if (!(await isAdmin(uid, request.auth?.token as Record<string, unknown>))) throw new HttpsError('permission-denied', 'Admins only.');
  return uid;
}

// ─────────────── Private contact index ───────────────
// `contact_index/{p:+E164 | e:email}` → { uid }. Deny-all to clients, so a
// phone number or e-mail can be matched to an account without making every
// profile's contact details readable.

export const contactKey = {
  phone: (e164: string) => `p:${e164}`,
  email: (email: string) => `e:${email.trim().toLowerCase()}`,
};

export async function uidForPhone(phone: string): Promise<string | null> {
  try {
    return (await getAuth().getUserByPhoneNumber(phone)).uid;
  } catch {
    // not an Auth phone; try the index, then legacy profile fields
  }
  const idx = await db().collection('contact_index').doc(contactKey.phone(phone)).get();
  if (idx.exists) return String(idx.get('uid'));
  // Older profiles stored local formats (07…, 254…).
  const variants = [phone, phone.slice(1), ...(phone.startsWith('+254') ? [`0${phone.slice(4)}`] : [])];
  for (const v of variants) {
    for (const field of ['phoneNumber', 'phone']) {
      const q = await db().collection('users').where(field, '==', v).limit(1).get();
      if (!q.empty) return q.docs[0].id;
    }
  }
  return null;
}

export async function uidForEmail(email: string): Promise<string | null> {
  const e = email.trim().toLowerCase();
  try {
    return (await getAuth().getUserByEmail(e)).uid;
  } catch {
    // fall through
  }
  const idx = await db().collection('contact_index').doc(contactKey.email(e)).get();
  if (idx.exists) return String(idx.get('uid'));
  for (const [field, op] of [['email', '=='], ['linkedEmails', 'array-contains']] as const) {
    const q = await db().collection('users').where(field, op, e).limit(1).get();
    if (!q.empty) return q.docs[0].id;
  }
  return null;
}
