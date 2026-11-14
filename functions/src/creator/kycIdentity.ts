/**
 * One ID, one person (with linked accounts).
 *
 * The ID number read from the document is never stored. It is turned into an
 * HMAC-SHA256 with a secret pepper (`KYC_ID_PEPPER`, Secret Manager), so the
 * index can't be reversed or matched against a leaked list without the key.
 *
 *   kyc_id_index/{hash} = { primaryUid, linkedUids: [...] }   (server only)
 *
 * - The first verified account owns the ID.
 * - Another account submitting the same ID is flagged as a duplicate and can't
 *   be approved, unless the owner linked it first (`kycLinkAccount`), for
 *   example a business or creator second account. At most [MAX_LINKED].
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { limit } from '../guard/protect';

export const MAX_LINKED = 3;
const db = () => getFirestore();

/** Letters and digits only, upper case: "AB 12-34" → "AB1234". */
export function normalizeIdNumber(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const n = raw.normalize('NFKC').toUpperCase().replace(/[^A-Z0-9]/g, '');
  return n.length >= 5 && n.length <= 24 ? n : null;
}

export function idHash(pepper: string, country: string, docType: string, number: string): string {
  return crypto.createHmac('sha256', pepper).update(`${country.toUpperCase()}|${docType}|${number}`).digest('hex');
}

export type IdStatus = 'new' | 'same' | 'linked' | 'duplicate';

export function idStatusFor(index: { primaryUid?: string; linkedUids?: string[] } | undefined, uid: string): IdStatus {
  if (!index?.primaryUid) return 'new';
  if (index.primaryUid === uid) return 'same';
  return (index.linkedUids ?? []).includes(uid) ? 'linked' : 'duplicate';
}

export async function lookupId(hash: string, uid: string): Promise<{ status: IdStatus; primaryUid?: string }> {
  const s = await db().collection('kyc_id_index').doc(hash).get();
  const d = s.data() as { primaryUid?: string; linkedUids?: string[] } | undefined;
  return { status: idStatusFor(d, uid), primaryUid: d?.primaryUid };
}

/** On approval: the ID becomes this person's, or this account joins as linked. Throws on a duplicate. */
export async function claimId(hash: string, uid: string): Promise<IdStatus> {
  const ref = db().collection('kyc_id_index').doc(hash);
  return db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const d = s.data() as { primaryUid?: string; linkedUids?: string[] } | undefined;
    const st = idStatusFor(d, uid);
    if (st === 'duplicate') throw new HttpsError('already-exists', 'This ID is already verified on another Oneova account.');
    if (st === 'new') tx.set(ref, { primaryUid: uid, linkedUids: [], createdAt: FieldValue.serverTimestamp() });
    return st;
  });
}

/**
 * The verified owner of an ID allows one more of their own accounts (by
 * @username) to verify with the same ID.
 */
export const kycLinkAccount = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  await limit(uid, 'kyc_link', 10, 24 * 3600_000);
  const handle = String(req.data?.username ?? '').trim().replace(/^@/, '').toLowerCase();
  if (!/^[a-z0-9._]{2,30}$/.test(handle)) throw new HttpsError('invalid-argument', 'Enter the other account’s @username.');
  const mine = (await db().doc(`kyc/${uid}`).get()).data();
  if (mine?.status !== 'verified' || typeof mine.idHash !== 'string') {
    throw new HttpsError('failed-precondition', 'Verify your own ID first, then you can link your other accounts.');
  }
  const q = await db().collection('users').where('username', '==', handle).limit(1).get();
  const target = q.docs[0]?.id;
  if (!target) throw new HttpsError('not-found', 'No account with that @username.');
  if (target === uid) throw new HttpsError('invalid-argument', 'That’s this account.');
  const ref = db().collection('kyc_id_index').doc(mine.idHash);
  await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const d = s.data() as { primaryUid?: string; linkedUids?: string[] } | undefined;
    if (d?.primaryUid !== uid) throw new HttpsError('permission-denied', 'Only the first account verified with this ID can link others.');
    const linked = d.linkedUids ?? [];
    if (linked.includes(target)) return;
    if (linked.length >= MAX_LINKED) throw new HttpsError('resource-exhausted', `You can link up to ${MAX_LINKED} accounts.`);
    tx.update(ref, { linkedUids: FieldValue.arrayUnion(target), updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true, linked: handle };
});
