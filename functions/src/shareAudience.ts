/**
 * "Share to all": sends one post to everyone who follows you (or everyone you
 * follow) as a friendly notification ("Amina shared a post with you"),
 * instead of flooding chats. Done on the server because it has to respect
 * each recipient's own privacy settings, which the sender cannot read:
 *
 *  - `user_settings/{rid}.privacy.messagePermissions == 'none'` → skipped;
 *    'contactsOnly' → only when the recipient follows the sender.
 *  - `user_settings/{rid}.privacy.allowShares === false` → skipped (opt-out).
 *  - Anyone who blocked the sender (relationships/{rid}_{sender} blocked) → skipped.
 *  - Posts the sender may not share (private, or another creator's post with
 *    sharing off) → refused.
 *
 * Rate limits: 3 bulk shares per rolling hour, 10 per day, 500 people each.
 * The same post reaches the same person at most once (deterministic ids).
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';

const db = () => getFirestore();
const MAX_RECIPIENTS = 500;
const PER_HOUR = 3;
const PER_DAY = 10;

async function takeRateSlot(uid: string): Promise<boolean> {
  const ref = db().collection('share_limits').doc(uid);
  return db().runTransaction(async (tx) => {
    const now = Date.now();
    const recent: number[] = ((await tx.get(ref)).get('bulk') as number[] | undefined ?? [])
      .filter((t) => now - t < 24 * 3600_000);
    if (recent.length >= PER_DAY || recent.filter((t) => now - t < 3600_000).length >= PER_HOUR) return false;
    tx.set(ref, { bulk: [...recent, now], updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

async function audienceIds(uid: string, audience: string): Promise<string[]> {
  const field = audience === 'following' ? 'followerId' : 'followingId';
  const other = audience === 'following' ? 'followingId' : 'followerId';
  const snap = await db().collection('relationships')
    .where(field, '==', uid).where('status', '==', 'accepted').limit(MAX_RECIPIENTS).get();
  return [...new Set(snap.docs.map((d) => String(d.get(other) || '')).filter((id) => id && id !== uid))];
}

export const shareToAudience = onCall({ timeoutSeconds: 120, memory: '256MiB' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to share.');
  const data = (request.data ?? {}) as Record<string, unknown>;
  const postId = typeof data.postId === 'string' ? data.postId.trim() : '';
  const audience = data.audience === 'following' ? 'following' : 'followers';
  const note = typeof data.message === 'string' ? data.message.trim().slice(0, 140) : '';
  if (!postId || postId.includes('/')) throw new HttpsError('invalid-argument', 'Pick a post to share.');

  // The post must exist and be shareable by this person.
  let post: FirebaseFirestore.DocumentData | undefined;
  for (const col of ['content', 'posts']) {
    post = (await db().collection(col).doc(postId).get()).data();
    if (post) break;
  }
  if (!post) throw new HttpsError('not-found', 'This post is no longer available.');
  const authorId = String(post.authorId || '');
  const isPrivate = post.isPrivate === true || post.visibility === 'private' || post.privacy === 'private';
  if (isPrivate && authorId !== uid) throw new HttpsError('permission-denied', 'This post is private, so it can’t be shared.');
  if (post.allowShare === false && authorId !== uid) throw new HttpsError('permission-denied', 'The creator turned off sharing for this post.');

  if (!(await takeRateSlot(uid))) {
    throw new HttpsError('resource-exhausted', 'You’ve shared to everyone a few times already. Try again a bit later.');
  }

  const me = (await db().collection('users').doc(uid).get()).data() || {};
  const myName = String(me.fullName || me.displayName || me.username || 'Someone').trim();
  const myAvatar = [me.avatarUrl, me.photoUrl, me.photoURL].find((v) => typeof v === 'string' && v.startsWith('http'));

  const ids = await audienceIds(uid, audience);
  let sent = 0;
  let skipped = 0;
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    const settings = await db().getAll(...chunk.map((id) => db().collection('user_settings').doc(id)));
    // relationships/{rid}_{me}: blocked, or (accepted) they follow me.
    const blocks = await db().getAll(...chunk.map((id) => db().collection('relationships').doc(`${id}_${uid}`)));
    const notes = await db().getAll(...chunk.map((id) => db().collection('notifications').doc(`share_${postId}_${uid}_${id}`)));
    const batch = db().batch();
    chunk.forEach((rid, j) => {
      const privacy = (settings[j].get('privacy') || {}) as Record<string, unknown>;
      const rel = blocks[j].get('status');
      const perm = String(privacy.messagePermissions || 'everyone');
      const follows = audience === 'followers' || rel === 'accepted';
      if (rel === 'blocked' || privacy.allowShares === false || perm === 'none' ||
          (perm === 'contactsOnly' && !follows) || notes[j].exists) {
        skipped++;
        return;
      }
      batch.set(notes[j].ref, {
        userId: rid,
        recipientId: rid,
        actorId: uid,
        category: 'share',
        priority: 'normal',
        type: 'social',
        title: `${myName} shared a post with you`,
        body: note ? `“${note}”` : 'Tap to watch it.',
        message: note ? `“${note}”` : 'Tap to watch it.',
        deepLink: `/hub/home?v=${postId}`,
        groupId: `share_${uid}`,
        payload: {
          postId,
          sharedWithYou: true,
          actorName: myName,
          ...(myAvatar ? { avatarUrl: myAvatar } : {}),
          ...(typeof post!.thumbnailUrl === 'string' ? { thumbnailUrl: post!.thumbnailUrl } : {}),
        },
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
        timestamp: FieldValue.serverTimestamp(),
      });
      sent++;
    });
    await batch.commit();
  }

  await db().collection('share_logs').add({
    uid, postId, audience, sent, skipped, createdAt: Timestamp.now(),
  }).catch(() => undefined);
  logger.info('shareToAudience', { uid, postId, audience, sent, skipped });
  return { sent, skipped, total: ids.length };
});
