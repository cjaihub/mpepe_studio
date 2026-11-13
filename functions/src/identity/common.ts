/**
 * Oneova ID shared helpers: caller checks, the audit trail, folder cleanup
 * and the badge fields on users/{uid} and biz_shops/{uid}.
 *
 * Everything under identity/, business_identity/ and kyb_requirements/ is
 * written only from here (see firestore.rules).
 */
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

export const db = () => getFirestore();

export function callerUid(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

export async function requireAdmin(req: CallableRequest): Promise<string> {
  const uid = callerUid(req);
  const role = String((await db().doc(`users/${uid}`).get()).get('role') ?? '');
  if (!['admin', 'owner', 'founder'].includes(role)) throw new HttpsError('permission-denied', 'Admins only.');
  return uid;
}

export function cleanUid(v: unknown): string {
  const s = String(v ?? '');
  if (!s || s.length > 128 || s.includes('/')) throw new HttpsError('invalid-argument', 'Missing user.');
  return s;
}

export type AuditActor = 'you' | 'reviewer' | 'system' | 'verifier';

/** One line in the user's own audit log. Never holds document numbers or images. */
export async function audit(uid: string, type: string, actor: AuditActor, detail = ''): Promise<void> {
  await db().collection(`identity/${uid}/audit`).add({
    type, actor, detail: detail.slice(0, 200), at: FieldValue.serverTimestamp(),
  });
}

/** Reviewer actions also go to the dashboard's audit log. */
export async function adminAudit(actorUid: string, action: string, targetId: string, reason = '', details: Record<string, unknown> = {}): Promise<void> {
  await db().collection('admin_audit').add({
    actorUid, action, targetType: action.split('.')[0], targetId, reason: reason.slice(0, 300), details, via: 'identity',
    at: FieldValue.serverTimestamp(),
  });
}

export async function deleteFolder(prefix: string): Promise<number> {
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles({ prefix });
  await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
  return files.length;
}

export async function notify(uid: string, id: string, title: string, body: string, deepLink: string): Promise<void> {
  await db().collection('notifications').doc(id).set({
    userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'identity',
    title, body, deepLink, isRead: false, createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Recomputes the public badge fields from the two sources of truth
 * (kyc/{uid} and business_identity/{uid}). The tick is only removed when
 * Oneova ID set it, so ticks granted by the team before Oneova ID stay.
 */
export async function syncBadges(uid: string): Promise<void> {
  const [kyc, biz, user] = await Promise.all([
    db().doc(`kyc/${uid}`).get(), db().doc(`business_identity/${uid}`).get(), db().doc(`users/${uid}`).get(),
  ]);
  const personal = kyc.get('status') === 'verified' ? 2 : 0;
  const bizVerified = biz.get('status') === 'verified';
  const bizLevel = bizVerified ? Number(biz.get('level') ?? 1) : 0;
  const ours = !user.get('verifiedBy') || user.get('verifiedBy') === 'oneova_id';
  if (user.exists) {
    const patch: Record<string, unknown> = { identityLevel: personal, businessLevel: bizLevel };
    if (personal > 0 || bizVerified) {
      patch.isVerified = true;
      if (ours) patch.verifiedBy = 'oneova_id';
    } else if (ours && user.get('isVerified') === true) {
      patch.isVerified = false;
      patch.verifiedBy = FieldValue.delete();
    }
    await user.ref.set(patch, { merge: true });
  }
  const shop = db().doc(`biz_shops/${uid}`);
  if ((await shop.get()).exists) await shop.update({ verified: bizVerified, verifiedLevel: bizLevel });
}
