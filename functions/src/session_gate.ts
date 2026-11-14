/**
 * Server-side two-check sign-in gate (PROPOSAL — not exported from index.ts,
 * so nothing here is deployed until the user approves it).
 *
 * Why: the app's LoginSecurity gate runs on the phone. A modified client
 * could skip it. These functions let the SERVER decide whether a sign-in
 * passed two checks, and mark that session with a custom claim that the
 * Firestore rules require for writes and private reads.
 *
 * Flow (client changes come with the approval):
 *   1. After every proof (password sign-in, SMS code, Google/Facebook,
 *      fingerprint device key) the app calls `recordSignInCheck({deviceId})`
 *      with its fresh ID token. The server reads the proof from the token
 *      itself (sign_in_provider + auth_time), so it cannot be faked.
 *      An SMS proof also marks this device as known (server-written).
 *   2. The app calls `confirmSignInChecks({deviceId})`. If the proofs meet the
 *      policy, the server adds this session's auth_time to the
 *      `mfaSessions` custom claim (last 5 sessions = up to 5 phones).
 *   3. The app refreshes its token (getIdToken(true)). Rules accept writes
 *      only when token.auth_time is in token.mfaSessions. Any new sign-in
 *      gets a new auth_time, so it is blocked until it passes again.
 *
 * Policy (same as LoginSecurity.missingFactor on the phone):
 *   - unknown device -> an SMS proof is required (then the device is known);
 *   - at least 2 different proofs among phone, password, federated,
 *     deviceKey (fingerprint key) and knownDevice;
 *   - at least one of password / federated / deviceKey.
 * Fingerprint and PIN are checked on the phone; the server counts the
 * fingerprint only through its server-issued device key.
 */
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { limit } from './guard/protect';

const PROOF_WINDOW_MS = 15 * 60 * 1000; // proofs older than this don't count
const FRESH_TOKEN_MS = 10 * 60 * 1000; // token must come from a recent sign-in
const MAX_SESSIONS = 5;

type Proof = 'phone' | 'password' | 'federated' | 'deviceKey';

function requireUser(request: CallableRequest<unknown>) {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const provider = auth.token.firebase?.sign_in_provider;
  if (provider === 'anonymous') throw new HttpsError('permission-denied', 'Guests cannot sign in this way.');
  return auth;
}

function deviceIdFrom(data: unknown): string {
  const id = String((data as { deviceId?: unknown })?.deviceId ?? '');
  if (!/^[0-9a-f]{32}$/.test(id)) throw new HttpsError('invalid-argument', 'Bad device.');
  return id;
}

/** Maps the token's sign-in method to a proof, or null if it isn't one. */
function proofFromToken(token: Record<string, unknown> & { firebase?: { sign_in_provider?: string } }): Proof | null {
  const p = token.firebase?.sign_in_provider ?? '';
  if (p === 'phone') return 'phone';
  if (p === 'password') return 'password';
  if (p === 'google.com' || p === 'facebook.com' || p.startsWith('oidc.')) return 'federated';
  if (p === 'custom' && token.biometric === true) return 'deviceKey';
  return null;
}

const checksDoc = (uid: string, deviceId: string) => getFirestore().collection('auth_checks').doc(`${uid}_${deviceId}`);
const deviceDoc = (uid: string, deviceId: string) =>
  getFirestore().collection('users').doc(uid).collection('trusted_devices').doc(deviceId);

/** Step 1: record the proof carried by the caller's (fresh) ID token. */
export const recordSignInCheck = onCall({ enforceAppCheck: true }, async (request) => {
  const auth = requireUser(request);
  const deviceId = deviceIdFrom(request.data);
  const authTimeMs = Number(auth.token.auth_time) * 1000;
  if (!authTimeMs || Date.now() - authTimeMs > FRESH_TOKEN_MS) {
    throw new HttpsError('failed-precondition', 'Please sign in again.');
  }
  const proof = proofFromToken(auth.token as never);
  if (!proof) throw new HttpsError('invalid-argument', 'This sign-in method does not count as a check.');

  await checksDoc(auth.uid, deviceId).set(
    { uid: auth.uid, deviceId, proofs: { [proof]: authTimeMs }, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  if (proof === 'phone') {
    // A fresh SMS proof on this device makes it a known device.
    await deviceDoc(auth.uid, deviceId).set(
      { trustedAt: FieldValue.serverTimestamp(), trustedVia: 'sms', lastSeenAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }
  return { recorded: proof };
});

/** Step 2: if the recorded proofs meet the policy, mark this session. */
export const confirmSignInChecks = onCall({ enforceAppCheck: true }, async (request) => {
  const auth = requireUser(request);
  const deviceId = deviceIdFrom(request.data);
  const db = getFirestore();

  const [checks, device] = await Promise.all([checksDoc(auth.uid, deviceId).get(), deviceDoc(auth.uid, deviceId).get()]);
  const now = Date.now();
  const proofs = new Set<string>();
  const recorded = (checks.get('proofs') ?? {}) as Record<string, number>;
  for (const [k, t] of Object.entries(recorded)) if (now - Number(t) <= PROOF_WINDOW_MS) proofs.add(k);
  const known = device.exists && device.get('revoked') !== true;
  if (known) proofs.add('knownDevice');

  if (!known && !proofs.has('phone')) {
    return { ok: false, needs: 'smsOtp' };
  }
  if (!proofs.has('password') && !proofs.has('federated') && !proofs.has('deviceKey')) {
    return { ok: false, needs: 'password' };
  }
  if (proofs.size < 2) {
    return { ok: false, needs: 'smsOtp' };
  }

  // Mark THIS session (auth_time) as verified, keeping other claims.
  const user = await getAuth().getUser(auth.uid);
  const claims = { ...(user.customClaims ?? {}) } as Record<string, unknown>;
  const sessions = Array.isArray(claims.mfaSessions) ? (claims.mfaSessions as number[]) : [];
  const authTime = Number(auth.token.auth_time);
  claims.mfaSessions = [...sessions.filter((s) => s !== authTime), authTime].slice(-MAX_SESSIONS);
  await getAuth().setCustomUserClaims(auth.uid, claims);

  // Old accounts kept a password hash in the public profile; once the
  // password lives in Firebase Auth, remove it.
  if (user.providerData.some((p) => p.providerId === 'password')) {
    await db.collection('users').doc(auth.uid).set(
      { passwordHash: FieldValue.delete(), password: FieldValue.delete() },
      { merge: true },
    );
  }
  await Promise.all([
    checks.ref.delete(),
    deviceDoc(auth.uid, deviceId).set({ lastSeenAt: FieldValue.serverTimestamp() }, { merge: true }),
    db.collection('users').doc(auth.uid).collection('security_events').add({
      type: 'sign_in',
      proofs: [...proofs].sort(),
      deviceId,
      newDevice: !known,
      at: FieldValue.serverTimestamp(),
    }),
  ]);
  return { ok: true };
});

/** "Sign out this phone": forget a known device and end all marked sessions. */
export const revokeTrustedDevice = onCall({ enforceAppCheck: true }, async (request) => {
  const auth = requireUser(request);
  const deviceId = deviceIdFrom(request.data);
  await deviceDoc(auth.uid, deviceId).delete();
  const user = await getAuth().getUser(auth.uid);
  const claims = { ...(user.customClaims ?? {}) } as Record<string, unknown>;
  delete claims.mfaSessions;
  await getAuth().setCustomUserClaims(auth.uid, claims);
  await getAuth().revokeRefreshTokens(auth.uid);
  return { ok: true };
});

/**
 * Login screen account lookup without public phone numbers: returns only
 * what the sign-in header shows. Replaces the client query on users.phoneNumber.
 */
/**
 * Was open to anyone (no sign-in) and returned the uid, name, username and
 * photo for any phone number: a ready-made tool to find who owns a number.
 * Not used by the app. Now: signed in, 5 lookups an hour, and only whether an
 * account exists.
 */
export const lookupAccountByPhone = onCall({ enforceAppCheck: true }, async (request) => {
  const auth = requireUser(request);
  await limit(auth.uid, 'phone_lookup', 5, 3600_000);
  const phone = String((request.data as { phone?: unknown })?.phone ?? '');
  if (!/^\+[1-9]\d{6,14}$/.test(phone)) throw new HttpsError('invalid-argument', 'Bad number.');
  const snap = await getFirestore().collection('users').where('phoneNumber', '==', phone).limit(1).get();
  return { found: !snap.empty };
});

/** One-off, admin only: strip legacy password hashes from every profile. */
export const scrubLegacyPasswordHashes = onCall(async (request) => {
  const auth = requireUser(request);
  const db = getFirestore();
  const me = await db.collection('users').doc(auth.uid).get();
  if (me.get('role') !== 'admin') throw new HttpsError('permission-denied', 'Admins only.');
  let cleaned = 0;
  for (const field of ['passwordHash', 'password']) {
    const snap = await db.collection('users').where(field, '!=', null).get();
    const writer = db.bulkWriter();
    for (const doc of snap.docs) {
      writer.update(doc.ref, { passwordHash: FieldValue.delete(), password: FieldValue.delete() });
      cleaned++;
    }
    await writer.close();
  }
  return { cleaned };
});
