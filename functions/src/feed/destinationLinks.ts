/**
 * Reel destination links (product / shop / any URL on a post).
 *
 * Callables:
 *   contentSetDestination  `{contentId, url?, productId?, label?}` (author
 *       only). Validates the link (destination_logic.ts), checks web links
 *       with Ova Guard, and writes `content/{id}.destination`. `{contentId,
 *       clear: true}` removes it. Clients cannot write `destination` or the
 *       click counters themselves (firestore.rules).
 *   contentOpenDestination `{contentId}` → `{kind, url, route, verdict,
 *       reasons}`. Re-checks web links (Web Risk is cached 24 h), counts the
 *       click (`destinationClicks`, plus `destinationUniqueClicks` once per
 *       person via `content/{id}/destination_clicks/{uid}`), and blocks the
 *       destination if Ova Guard now says it is dangerous.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { analyzeUrl } from '../guard/linkSafety';
import { checkLinks } from '../guard/reputation';
import { limit, requireAccount } from '../guard/protect';
import { defaultLabel, parseDestination } from './destination_logic';

const db = () => getFirestore();
const CONTENT_ID = /^[A-Za-z0-9_-]{1,64}$/;

async function guardVerdict(url: string): Promise<{ verdict: string; reasons: string[] }> {
  const finding = analyzeUrl(url);
  if (!finding) return { verdict: 'safe', reasons: [] };
  const [rep] = await checkLinks({ links: [finding], points: 0, reasons: [], categories: [] });
  return { verdict: rep?.verdict ?? 'safe', reasons: (rep?.reasons ?? []).slice(0, 3) };
}

function contentIdOf(data: unknown): string {
  const id = String((data as { contentId?: unknown })?.contentId ?? '');
  if (!CONTENT_ID.test(id)) throw new HttpsError('invalid-argument', 'Missing post.');
  return id;
}

export const contentSetDestination = onCall(async (request) => {
  const uid = requireAccount(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const contentId = contentIdOf(data);
  await limit(uid, 'destination_set', 30, 10 * 60000);

  const ref = db().collection('content').doc(contentId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'That post does not exist.');
  if (snap.get('authorId') !== uid) throw new HttpsError('permission-denied', 'Only the creator can change this link.');

  if (data.clear === true) {
    await ref.update({ destination: FieldValue.delete(), link: null });
    return { ok: true, destination: null };
  }

  const parsed = parseDestination(data);
  if (!parsed.ok) throw new HttpsError('invalid-argument', parsed.reason);
  const d = parsed.value;

  let productTitle: string | null = null;
  if (d.kind === 'product' && d.productId) {
    const p = await db().collection('biz_products').doc(d.productId).get();
    if (!p.exists) throw new HttpsError('not-found', 'That product is not in Biz anymore.');
    productTitle = typeof p.get('title') === 'string' ? p.get('title') : null;
  }

  let verdict = 'safe';
  let reasons: string[] = [];
  if (d.kind === 'web' && d.url) {
    ({ verdict, reasons } = await guardVerdict(d.url));
    if (verdict === 'dangerous') {
      throw new HttpsError('failed-precondition', `Ova Guard blocked this link: ${reasons[0] ?? 'it is on a list of dangerous sites'}.`);
    }
  }

  const destination = {
    kind: d.kind,
    url: d.url,
    host: d.host,
    route: d.route,
    productId: d.productId,
    label: d.label || defaultLabel(d.kind, d.host, productTitle),
    verdict,
    reasons,
    status: 'ok',
    checkedAt: FieldValue.serverTimestamp(),
  };
  await ref.update({
    destination,
    link: d.url ?? d.route,
    destinationClicks: snap.get('destinationClicks') ?? 0,
    destinationUniqueClicks: snap.get('destinationUniqueClicks') ?? 0,
  });
  return { ok: true, destination: { ...destination, checkedAt: null } };
});

export const contentOpenDestination = onCall(async (request) => {
  const uid = requireAccount(request);
  const contentId = contentIdOf(request.data);
  await limit(uid, 'destination_open', 120, 10 * 60000);

  const ref = db().collection('content').doc(contentId);
  const snap = await ref.get();
  const dest = snap.get('destination') as Record<string, unknown> | undefined;
  if (!snap.exists || !dest) throw new HttpsError('not-found', 'This link is no longer on the post.');
  if (dest.status === 'blocked') {
    return { kind: dest.kind, url: null, route: null, verdict: 'dangerous', reasons: (dest.reasons as string[]) ?? [] };
  }

  let verdict = String(dest.verdict ?? 'safe');
  let reasons = (dest.reasons as string[] | undefined) ?? [];
  const url = typeof dest.url === 'string' ? dest.url : null;
  if (dest.kind === 'web' && url) ({ verdict, reasons } = await guardVerdict(url));

  const clickRef = ref.collection('destination_clicks').doc(uid);
  await db().runTransaction(async (tx) => {
    const click = await tx.get(clickRef);
    const update: Record<string, unknown> = { destinationClicks: FieldValue.increment(1) };
    if (!click.exists) {
      update.destinationUniqueClicks = FieldValue.increment(1);
      tx.set(clickRef, { uid, firstAt: FieldValue.serverTimestamp(), lastAt: FieldValue.serverTimestamp(), count: 1 });
    } else {
      tx.update(clickRef, { lastAt: FieldValue.serverTimestamp(), count: FieldValue.increment(1) });
    }
    if (verdict === 'dangerous') {
      update['destination.status'] = 'blocked';
      update['destination.verdict'] = 'dangerous';
      update['destination.reasons'] = reasons;
    } else if (verdict !== dest.verdict) {
      update['destination.verdict'] = verdict;
      update['destination.reasons'] = reasons;
    }
    tx.update(ref, update);
  });

  return {
    kind: dest.kind,
    url: verdict === 'dangerous' ? null : url,
    route: typeof dest.route === 'string' ? dest.route : null,
    verdict,
    reasons,
  };
});
