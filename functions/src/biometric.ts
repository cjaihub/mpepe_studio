/**
 * Fingerprint / Face quick re-login.
 *
 * When a signed-in user turns on biometric sign-in, the app generates a
 * 256-bit random secret, keeps it in the device's secure storage (Android
 * Keystore / iOS Keychain) and registers only its SHA-256 hash here. Later,
 * after a local biometric check, the app sends the key id + secret to
 * `biometricSignIn`, which returns a Firebase custom token for that user.
 *
 * Passwords are never stored. `biometric_keys` must not be readable or
 * writable by clients (Firestore rules: deny all); only this code touches it.
 *
 * Needs: the functions' service account must have
 * "Service Account Token Creator" so createCustomToken can sign.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { recordSecurityEvent } from './security';
import { callerIp, limit } from './guard/protect';

const KEYS = 'biometric_keys';
const MAX_KEYS_PER_USER = 5;
const KEY_TTL_DAYS = 90;

function sha256(v: string): string {
  return crypto.createHash('sha256').update(v).digest('hex');
}

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a, 'hex');
  const bb = Buffer.from(b, 'hex');
  return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}

/** Registers this device's biometric key for the signed-in user. */
export const registerBiometricKey = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid || request.auth?.token?.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in to your account first.');
  }
  const secretHash = String(request.data?.secretHash ?? '');
  const deviceLabel = String(request.data?.deviceLabel ?? '').slice(0, 80);
  const deviceId = String(request.data?.deviceId ?? '');
  if (deviceId && !/^[0-9a-f]{32}$/.test(deviceId)) {
    throw new HttpsError('invalid-argument', 'Bad device.');
  }
  if (!/^[0-9a-f]{64}$/.test(secretHash)) {
    throw new HttpsError('invalid-argument', 'Bad key.');
  }
  const db = getFirestore();

  // Keep at most a few devices per user; drop the oldest.
  const existing = await db.collection(KEYS).where('uid', '==', uid).get();
  const sorted = existing.docs.sort(
    (a, b) => (a.get('createdAt')?.toMillis?.() ?? 0) - (b.get('createdAt')?.toMillis?.() ?? 0),
  );
  const batch = db.batch();
  for (const d of sorted.slice(0, Math.max(0, sorted.length - (MAX_KEYS_PER_USER - 1)))) {
    batch.delete(d.ref);
  }
  const ref = db.collection(KEYS).doc();
  batch.set(ref, {
    uid,
    secretHash,
    deviceLabel,
    deviceId: deviceId || null,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + KEY_TTL_DAYS * 86400000),
    lastUsedAt: null,
  });
  await batch.commit();

  // Ova Guard: a new fingerprint key is worth knowing about, more so on a
  // device that first appeared in the last day.
  let newDevice = true;
  if (deviceId) {
    const seen = await db.collection('security_state').doc(uid).collection('devices').doc(deviceId).get();
    const first = seen.get('firstSeenAt')?.toMillis?.() ?? Date.now();
    newDevice = !seen.exists || Date.now() - first < 86400000;
  }
  await recordSecurityEvent(uid, 'biometric_key_added', {
    deviceId: deviceId || null,
    deviceLabel: deviceLabel || null,
    details: { newDevice },
  }).catch((e) => console.warn('guard event failed', e));
  return { keyId: ref.id };
});

/** Exchanges a device key for a custom token. Called while signed out. */
export const biometricSignIn = onCall(async (request) => {
  const keyId = String(request.data?.keyId ?? '');
  const secret = String(request.data?.secret ?? '');
  if (!/^[A-Za-z0-9]{10,40}$/.test(keyId) || secret.length < 32 || secret.length > 256) {
    throw new HttpsError('invalid-argument', 'Bad key.');
  }
  await limit(callerIp(request), 'bio_signin', 30, 15 * 60000);
  const db = getFirestore();
  const ref = db.collection(KEYS).doc(keyId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'This device is no longer enrolled.');
  const data = snap.data()!;
  const expires = (data.expiresAt as Timestamp | undefined)?.toMillis() ?? 0;
  if (expires < Date.now()) {
    await ref.delete();
    throw new HttpsError('deadline-exceeded', 'Biometric sign-in expired. Sign in again.');
  }
  if (!safeEqual(sha256(secret), String(data.secretHash))) {
    throw new HttpsError('permission-denied', 'This device is no longer enrolled.');
  }
  // The key only works on the device it was registered from.
  if (data.deviceId && String(request.data?.deviceId ?? '') !== String(data.deviceId)) {
    throw new HttpsError('permission-denied', 'This device is no longer enrolled.');
  }
  const uid = String(data.uid);
  try {
    const user = await getAuth().getUser(uid);
    if (user.disabled) throw new HttpsError('permission-denied', 'Account disabled.');
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    await ref.delete();
    throw new HttpsError('not-found', 'Account not found.');
  }
  // Sliding expiry: each successful use extends the key.
  await ref.update({
    lastUsedAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + KEY_TTL_DAYS * 86400000),
  });
  const token = await getAuth().createCustomToken(uid, { biometric: true });
  return { token };
});

/** Removes a device key (turning biometric sign-in off). */
export const revokeBiometricKey = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const keyId = String(request.data?.keyId ?? '');
  const db = getFirestore();
  if (keyId) {
    const ref = db.collection(KEYS).doc(keyId);
    const snap = await ref.get();
    if (snap.exists && snap.get('uid') === uid) await ref.delete();
  }
  return { ok: true };
});
