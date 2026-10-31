/**
 * Creator insights: daily roll-ups the analytics screens chart.
 *
 *   creator_daily/{authorId}/days/{YYYY-MM-DD}
 *     views, plays, watchMs, completes, likes, comments, shares,
 *     followsGained, followsLost, giftDiamonds
 *   content/{id}: playCount, watchTimeMs, completionCount, giftDiamonds
 *     (viewCount / likeCount / commentCount / shareCount are kept by the app)
 *
 * Fed by triggers on the docs the app already writes (one per person:
 * content_views, content_likes, content_reposts, content comments,
 * relationships, wallet ledger) and by `recordWatchTime`, which the feed calls
 * in small batches with how long each clip was watched. Self-views are skipped.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentDeleted, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const db = () => getFirestore();
const day = (d = new Date()) => d.toISOString().slice(0, 10);

function bump(authorId: string, fields: Record<string, number>, batch?: FirebaseFirestore.WriteBatch) {
  const ref = db().doc(`creator_daily/${authorId}/days/${day()}`);
  const data: Record<string, unknown> = { date: day(), updatedAt: FieldValue.serverTimestamp() };
  for (const [k, v] of Object.entries(fields)) data[k] = FieldValue.increment(v);
  return batch ? batch.set(ref, data, { merge: true }) : ref.set(data, { merge: true });
}

async function authorOf(contentId: string): Promise<string | null> {
  if (!contentId || contentId.includes('/')) return null;
  const c = await db().doc(`content/${contentId}`).get();
  const a = c.get('authorId');
  return typeof a === 'string' && a ? a : null;
}

async function onEngagement(contentId: unknown, actor: unknown, field: string, delta: number) {
  const authorId = await authorOf(String(contentId ?? ''));
  if (!authorId || authorId === actor) return;
  await bump(authorId, { [field]: delta });
}

export const insightsOnView = onDocumentCreated('content_views/{id}', async (e) =>
  onEngagement(e.data?.get('contentId'), e.data?.get('userId'), 'views', 1));

export const insightsOnLike = onDocumentCreated('content_likes/{id}', async (e) =>
  onEngagement(e.data?.get('contentId'), e.data?.get('userId'), 'likes', 1));

export const insightsOnUnlike = onDocumentDeleted('content_likes/{id}', async (e) =>
  onEngagement(e.data?.get('contentId'), e.data?.get('userId'), 'likes', -1));

export const insightsOnShare = onDocumentCreated('content_reposts/{id}', async (e) =>
  onEngagement(e.data?.get('contentId'), e.data?.get('userId'), 'shares', 1));

export const insightsOnComment = onDocumentCreated('content/{contentId}/comments/{id}', async (e) =>
  onEngagement(e.params.contentId, e.data?.get('authorId') ?? e.data?.get('userId'), 'comments', 1));

export const insightsOnFollow = onDocumentWritten('relationships/{id}', async (e) => {
  const before = e.data?.before.data();
  const after = e.data?.after.data();
  const was = before?.status === 'accepted';
  const is = after?.status === 'accepted';
  if (was === is) return;
  const target = (after ?? before)?.followingId;
  if (typeof target !== 'string' || !target) return;
  await bump(target, is ? { followsGained: 1 } : { followsLost: 1 });
});

export const insightsOnEarning = onDocumentCreated('wallets/{uid}/ledger/{id}', async (e) => {
  const t = e.data?.get('type');
  if (t !== 'live_gift_received' && t !== 'user_gift_received') return;
  const amount = Number(e.data?.get('amount') ?? 0);
  if (!(amount > 0)) return;
  const batch = db().batch();
  bump(e.params.uid, { giftDiamonds: amount }, batch);
  const contentId = e.data?.get('contentId');
  if (typeof contentId === 'string' && contentId && !contentId.includes('/')) {
    batch.set(db().doc(`content/${contentId}`), { giftDiamonds: FieldValue.increment(amount) }, { merge: true });
  }
  await batch.commit();
});

/**
 * Watch time from the feed: [{contentId, watchMs, durationMs}], up to 40 per
 * call. Each item is capped (5 loops, 10 minutes) so nobody can inflate it.
 */
export const recordWatchTime = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const items = Array.isArray(req.data?.items) ? req.data.items.slice(0, 40) : [];
  const valid = items
    .map((i: any) => ({ id: String(i?.contentId ?? ''), watch: Number(i?.watchMs), dur: Number(i?.durationMs) }))
    .filter((i: { id: string; watch: number; dur: number }) => i.id && !i.id.includes('/') && i.watch >= 500 && i.dur >= 1000 && i.dur <= 3600_000);
  if (!valid.length) return { ok: true, n: 0 };
  const docs = await db().getAll(...valid.map((i: { id: string }) => db().doc(`content/${i.id}`)));
  const batch = db().batch();
  const perAuthor = new Map<string, { plays: number; watchMs: number; completes: number }>();
  let n = 0;
  docs.forEach((d, k) => {
    const authorId = d.get('authorId');
    if (!d.exists || typeof authorId !== 'string' || authorId === uid) return;
    const { watch, dur } = valid[k];
    const ms = Math.round(Math.min(watch, dur * 5, 600_000));
    const complete = ms >= dur * 0.9 ? 1 : 0;
    batch.update(d.ref, {
      playCount: FieldValue.increment(1), watchTimeMs: FieldValue.increment(ms), completionCount: FieldValue.increment(complete),
      ...(d.get('mediaMetadata.durationMs') ? {} : { 'mediaMetadata.durationMs': Math.round(dur) }),
    });
    const a = perAuthor.get(authorId) ?? { plays: 0, watchMs: 0, completes: 0 };
    a.plays += 1; a.watchMs += ms; a.completes += complete;
    perAuthor.set(authorId, a);
    n++;
  });
  for (const [authorId, a] of perAuthor) bump(authorId, a, batch);
  if (n) await batch.commit();
  return { ok: true, n };
});
