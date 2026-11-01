/**
 * LIVE STUDIO v2 — "Watch together" callables (pure rules: watch_logic.ts).
 *
 * - `lsWatch({streamId, op, ...})` → `{ok, watch}` — host / co-host only.
 *   ops: youtube {videoId, title?, channel?, thumbUrl?} · browser {url} ·
 *   play|pause|seek {positionMs} · rate {rate} · ended · stop.
 *   Writes `live_streams/{id}/studio/watch` (signed-in users read it; the
 *   app keeps one listener per viewer and plays the layer locally).
 * - `lsYouTubeSearch({streamId, q, pageToken?})` → `{enabled, items, nextPageToken}`
 *   YouTube Data API v3 `search.list` (embeddable videos only). The key is
 *   YOUTUBE_API_KEY in Secret Manager, read at run time: without it
 *   `enabled` is false and the app says it is waiting for the key.
 *
 * YouTube is never re-streamed: each viewer's app plays the official player.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { optionalSecret } from '../optionalSecrets';
import { Paths } from './contracts';
import { db, loadState, rateLimit, requireLive, requireRole, requireString, requireUid } from './shared';
import {
  WatchError,
  WatchYouTube,
  YouTubeHit,
  applyWatchOp,
  fromYouTubeItem,
  normalizeWatch,
  parseWatchOp,
  sanitizeYouTubeQuery,
} from './watch_logic';

export const watchPath = (streamId: string) => `${Paths.streams}/${streamId}/studio/watch`;

const guard = <T>(fn: () => T): T => {
  try {
    return fn();
  } catch (e) {
    if (e instanceof WatchError) throw new HttpsError(e.code, e.message);
    throw e;
  }
};

/**
 * YouTube oEmbed (no key needed): fills title / channel / thumbnail and
 * refuses private or non-embeddable videos before anyone tries to play them.
 * Network trouble is not fatal: the app's player reports errors too.
 */
async function withOEmbed(video: WatchYouTube): Promise<WatchYouTube> {
  const url = `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${video.videoId}`)}`;
  let res: Response;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(3000) });
  } catch (e) {
    console.warn('[liveStudio] oembed failed:', (e as Error).message);
    return video;
  }
  if (res.status === 401 || res.status === 403 || res.status === 404) {
    throw new HttpsError('failed-precondition', 'This video cannot be played inside Oneova (it is private or its owner turned off embedding).');
  }
  if (!res.ok) return video;
  const body = (await res.json().catch(() => ({}))) as { title?: unknown; author_name?: unknown; thumbnail_url?: unknown };
  const hit = fromYouTubeItem({
    id: { videoId: video.videoId },
    snippet: { title: body.title, channelTitle: body.author_name, thumbnails: { high: { url: body.thumbnail_url } } },
  });
  return {
    videoId: video.videoId,
    title: video.title || hit?.title || '',
    channel: video.channel || hit?.channel || '',
    thumbUrl: video.thumbUrl || hit?.thumbUrl || '',
  };
}

export const lsWatch = onCall(async (req) => {
  const uid = requireUid(req);
  const data = (req.data ?? {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  let op = guard(() => parseWatchOp(data));
  const state = await loadState(streamId);
  requireLive(state);
  await requireRole(streamId, uid, ['host', 'coHost'], state);
  await rateLimit(streamId, uid, 'watch', 8, 2000);
  if (op.op === 'youtube') op = { op: 'youtube', video: await withOEmbed(op.video) };

  const ref = db().doc(watchPath(streamId));
  const watch = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = normalizeWatch(snap.exists ? (snap.data() as Record<string, unknown>) : null);
    const next = guard(() => applyWatchOp(cur, op, uid, Date.now()));
    tx.set(ref, next);
    return next;
  });
  return { ok: true, watch };
});

const CACHE_MS = 10 * 60 * 1000;
const cache = new Map<string, { at: number; items: YouTubeHit[]; next: string | null }>();

export const lsYouTubeSearch = onCall(async (req) => {
  const uid = requireUid(req);
  const data = (req.data ?? {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  const q = sanitizeYouTubeQuery(data.q);
  const pageToken = typeof data.pageToken === 'string' ? data.pageToken.slice(0, 100) : '';
  await requireRole(streamId, uid, ['host', 'coHost']);

  const key = await optionalSecret('YOUTUBE_API_KEY');
  if (!key) return { enabled: false, items: [], nextPageToken: null };
  if (!q) return { enabled: true, items: [], nextPageToken: null };

  const cacheKey = `${q.toLowerCase()}|${pageToken}`;
  const hit = cache.get(cacheKey);
  if (hit && Date.now() - hit.at < CACHE_MS) return { enabled: true, items: hit.items, nextPageToken: hit.next };
  await rateLimit(streamId, uid, 'yt_search', 10, 60_000);

  const params = new URLSearchParams({
    key,
    part: 'snippet',
    type: 'video',
    videoEmbeddable: 'true',
    safeSearch: 'moderate',
    maxResults: '20',
    q,
  });
  if (pageToken) params.set('pageToken', pageToken);
  try {
    const res = await fetch(`https://www.googleapis.com/youtube/v3/search?${params.toString()}`);
    if (!res.ok) throw new Error(`YouTube ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const body = (await res.json()) as { items?: unknown[]; nextPageToken?: string };
    const items = (body.items ?? []).map(fromYouTubeItem).filter((h): h is YouTubeHit => h !== null);
    const next = body.nextPageToken ?? null;
    if (cache.size > 200) cache.clear();
    cache.set(cacheKey, { at: Date.now(), items, next });
    return { enabled: true, items, nextPageToken: next };
  } catch (e) {
    console.warn('[liveStudio] youtube search failed:', (e as Error).message);
    throw new HttpsError('unavailable', 'YouTube search is not available right now.');
  }
});
