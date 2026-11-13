/**
 * Oneova ID for people. The check itself is the payments KYC (creator/kyc.ts);
 * this file reacts to its decisions and gives the person a reusable,
 * shareable credential, plus "delete my identity data".
 *
 *   kycReview approve → onPersonalVerified  (badge, audit, notification)
 *   app → idCredential   signed SD-JWT VC, returned once to be kept on the phone
 *   app → idShare        short-lived QR token with only the chosen fields
 *   app → idShareRevoke  stops a share
 *   app → kycDelete      deletes photos + record, revokes everything
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { audit, callerUid, db, deleteFolder, notify, syncBadges } from './common';
import { CredentialKind, issueCredential, revokeCredential, signingJwk, signShare, VERIFY_URL } from './credentials';

const monthOf = (t: unknown): string => {
  const d = t instanceof Timestamp ? t.toDate() : new Date();
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
};

/** Called from kycReview after an approval. */
export async function onPersonalVerified(uid: string, reviewer: string): Promise<void> {
  await db().doc(`identity/${uid}`).set({
    uid, level: 2, status: 'verified', credentialReady: true, verifiedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await syncBadges(uid);
  await audit(uid, 'id.verified', 'reviewer', reviewer ? 'Approved by the review team' : '');
  await notify(uid, `id_ok_${uid}`, 'Your Oneova ID is ready', 'Your identity is verified. You can now share it with a QR code.', '/id');
}

export async function onPersonalRejected(uid: string, reason: string): Promise<void> {
  await db().doc(`identity/${uid}`).set({ uid, status: 'rejected', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(uid, 'id.rejected', 'reviewer', reason);
}

export async function onPersonalSubmitted(uid: string): Promise<void> {
  await db().doc(`identity/${uid}`).set({ uid, status: 'review', consentAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(uid, 'id.submitted', 'you', 'Photos sent for review');
}

async function personClaims(uid: string): Promise<Record<string, string | number | boolean>> {
  const [k, u] = await Promise.all([db().doc(`kyc/${uid}`).get(), db().doc(`users/${uid}`).get()]);
  if (k.get('status') !== 'verified') throw new HttpsError('failed-precondition', 'Verify your identity first.');
  return {
    verified: true,
    level: 2,
    name: String(k.get('verifiedName') ?? ''),
    country: String(k.get('country') ?? ''),
    document: String(k.get('documentType') ?? ''),
    since: monthOf(k.get('verifiedAt')),
    handle: String(u.get('username') ?? ''),
  };
}

async function businessClaims(uid: string): Promise<Record<string, string | number | boolean>> {
  const b = await db().doc(`business_identity/${uid}`).get();
  if (b.get('status') !== 'verified') throw new HttpsError('failed-precondition', 'Your business is not verified yet.');
  return {
    verified: true,
    level: Number(b.get('level') ?? 1),
    name: String(b.get('legalName') ?? ''),
    country: String(b.get('country') ?? ''),
    type: String(b.get('businessType') ?? ''),
    registration: String(b.get('registrationNumber') ?? ''),
    since: monthOf(b.get('verifiedAt')),
  };
}

export const claimsFor = (uid: string, kind: CredentialKind) => (kind === 'person' ? personClaims(uid) : businessClaims(uid));

const kindOf = (v: unknown): CredentialKind => (v === 'business' ? 'business' : 'person');

export const idCredential = onCall({ secrets: [signingJwk] }, async (req) => {
  const uid = callerUid(req);
  const kind = kindOf(req.data?.kind);
  const claims = await claimsFor(uid, kind);
  const { id, token, expiresAt } = await issueCredential(uid, kind, claims, kind === 'person' ? 2 : 1);
  await audit(uid, `${kind === 'person' ? 'id' : 'business'}.credential_issued`, 'you', 'Saved to this phone');
  return { id, token, expiresAt: expiresAt.toISOString() };
});

const SHARE_FIELDS: Record<CredentialKind, string[]> = {
  person: ['name', 'country', 'document', 'since', 'handle'],
  business: ['name', 'country', 'type', 'registration', 'since'],
};

export const idShare = onCall({ secrets: [signingJwk] }, async (req) => {
  const uid = callerUid(req);
  const kind = kindOf(req.data?.kind);
  const asked = Array.isArray(req.data?.fields) ? req.data.fields.map(String) : [];
  const fields = SHARE_FIELDS[kind].filter((f) => asked.includes(f));
  const minutes = Math.min(Math.max(Number(req.data?.minutes) || 10, 5), 60 * 24 * 30);
  const doc = (await db().doc(kind === 'person' ? `identity/${uid}` : `business_identity/${uid}`).get());
  let credentialId = doc.get('credentialId');
  const all = await claimsFor(uid, kind);
  if (!credentialId) credentialId = (await issueCredential(uid, kind, all, kind === 'person' ? 2 : 1)).id;
  const claims: Record<string, unknown> = { verified: true, level: all.level };
  for (const f of fields) claims[f] = all[f];
  const shareId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + minutes * 60000);
  await db().doc(`identity/${uid}/shares/${shareId}`).set({
    kind, fields, credentialId, createdAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromDate(expiresAt), revokedAt: null, views: 0,
  });
  await audit(uid, `${kind === 'person' ? 'id' : 'business'}.shared`, 'you', fields.length ? `Shared: ${fields.join(', ')}` : 'Shared: verified only');
  const token = signShare(shareId, credentialId, kind, claims, minutes * 60);
  return { shareId, token, url: `${VERIFY_URL}#t=${token}`, expiresAt: expiresAt.toISOString() };
});

export const idShareRevoke = onCall(async (req) => {
  const uid = callerUid(req);
  const shareId = String(req.data?.shareId ?? '');
  if (!/^[0-9a-f-]{36}$/.test(shareId)) throw new HttpsError('invalid-argument', 'Unknown share.');
  const ref = db().doc(`identity/${uid}/shares/${shareId}`);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Unknown share.');
  await ref.update({ revokedAt: FieldValue.serverTimestamp() });
  await audit(uid, 'id.share_stopped', 'you');
  return { ok: true };
});

/** Deletes the ID photos and the check record; payouts stop until verified again. */
export const kycDelete = onCall({ timeoutSeconds: 120 }, async (req) => {
  const uid = callerUid(req);
  if (req.data?.confirm !== true) throw new HttpsError('failed-precondition', 'Confirm first.');
  const removed = await deleteFolder(`kyc/${uid}/`);
  await db().doc(`kyc/${uid}`).delete();
  await revokeCredential(uid, 'person');
  await db().doc(`identity/${uid}`).set({
    level: 0, status: 'deleted', credentialId: FieldValue.delete(), credentialReady: false, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  // A verified business needs a verified owner.
  const biz = db().doc(`business_identity/${uid}`);
  if ((await biz.get()).get('status') === 'verified') {
    await biz.set({ status: 'expired', expiredReason: 'The owner’s identity was deleted.', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await revokeCredential(uid, 'business');
  }
  await syncBadges(uid);
  await audit(uid, 'id.deleted', 'you', `Identity data deleted (${removed} photos)`);
  return { ok: true, photosDeleted: removed };
});
