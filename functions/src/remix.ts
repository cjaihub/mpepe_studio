/**
 * Remixes: a post published from Studio's Remix carries
 * `remixOf: {contentId, authorId, authorName, status: 'pending'}`.
 *
 * remixOnCreate checks the original creator allows remixes (remix_logic):
 * - allowed: writes `remix_links/{remixContentId}` (the earnings split that
 *   sendUserGift applies), marks the remix `active`, bumps the original's
 *   `remixCount` and tells its creator;
 * - not allowed: marks it `rejected`, takes the remix private and tells the
 *   remixer why.
 * remixOnDelete ends the link when a remix is deleted.
 *
 * Only this server writes `remix_links` (no client rules).
 */
import { onDocumentCreated, onDocumentDeleted } from 'firebase-functions/v2/firestore';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { REMIX_ORIGINAL_SHARE, remixAllowed } from './remix_logic';

const db = () => getFirestore();
const safeId = (v: unknown): v is string => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);

export const remixOnCreate = onDocumentCreated('content/{contentId}', async (e) => {
  const data = e.data?.data();
  const remixOf = data?.remixOf as Record<string, unknown> | undefined;
  if (!data || !remixOf) return;
  const remixId = e.params.contentId;
  const remixAuthorId = String(data.authorId ?? '');
  const ref = e.data!.ref;
  const originalId = remixOf.contentId;
  if (!safeId(originalId) || !remixAuthorId) {
    await ref.update({ 'remixOf.status': 'rejected', 'remixOf.reason': 'bad_request' });
    return;
  }
  const original = await db().doc(`content/${originalId}`).get();
  const verdict = remixAllowed(original.data(), remixAuthorId, remixOf.authorId);
  if (!verdict.ok) {
    logger.info('Remix rejected', { remixId, originalId, reason: verdict.reason });
    const update: Record<string, unknown> = { 'remixOf.status': 'rejected', 'remixOf.reason': verdict.reason };
    // The creator turned remixes off: the remix does not stay public.
    if (verdict.reason === 'not_allowed' || verdict.reason === 'not_public') update.visibility = 'private';
    if (verdict.reason === 'own_post') {
      // Remixing yourself is fine; there is just nothing to split.
      await ref.update({ remixOf: FieldValue.delete(), attribution: FieldValue.delete() });
      return;
    }
    await ref.update(update);
    await db().collection('notifications').doc(`remix_rejected_${remixId}`).set({
      userId: remixAuthorId, recipientId: remixAuthorId, category: 'system', priority: 'normal', type: 'remix_rejected',
      title: 'Your remix is private',
      body: verdict.reason === 'not_allowed'
        ? 'The creator of the original turned off remixes, so only you can see it.'
        : 'The original post is no longer public, so only you can see your remix.',
      deepLink: `/hub/home`, isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
    return;
  }
  const originalAuthorId = String(original.get('authorId'));
  const batch = db().batch();
  batch.set(db().doc(`remix_links/${remixId}`), {
    remixContentId: remixId,
    remixAuthorId,
    originalContentId: originalId,
    originalAuthorId,
    share: REMIX_ORIGINAL_SHARE,
    status: 'active',
    giftCoins: 0,
    originalCoins: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.update(ref, { 'remixOf.status': 'active', 'remixOf.share': REMIX_ORIGINAL_SHARE });
  batch.set(original.ref, { remixCount: FieldValue.increment(1) }, { merge: true });
  const me = (await db().doc(`users/${remixAuthorId}`).get()).data() ?? {};
  const name = String(me.fullName || me.displayName || me.username || 'Someone');
  batch.set(db().collection('notifications').doc(`remix_${remixId}`), {
    userId: originalAuthorId, recipientId: originalAuthorId, actorId: remixAuthorId, category: 'social', priority: 'normal', type: 'remix',
    title: `${name} remixed your post`,
    body: `You get ${Math.round(REMIX_ORIGINAL_SHARE * 100)}% of the gift coins their remix earns.`,
    deepLink: `/profile/${remixAuthorId}`, isRead: false, createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
});

export const remixOnDelete = onDocumentDeleted('content/{contentId}', async (e) => {
  const remixOf = e.data?.get('remixOf') as Record<string, unknown> | undefined;
  if (!remixOf) return;
  const link = db().doc(`remix_links/${e.params.contentId}`);
  const snap = await link.get();
  if (!snap.exists) return;
  await link.update({ status: 'ended', endedAt: FieldValue.serverTimestamp() });
  const originalId = snap.get('originalContentId');
  if (safeId(originalId)) await db().doc(`content/${originalId}`).set({ remixCount: FieldValue.increment(-1) }, { merge: true });
});
