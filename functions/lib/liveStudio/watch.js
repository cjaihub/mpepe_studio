"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsYouTubeSearch = exports.lsWatch = exports.watchPath = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const optionalSecrets_1 = require("../optionalSecrets");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const watch_logic_1 = require("./watch_logic");
const watchPath = (streamId) => `${contracts_1.Paths.streams}/${streamId}/studio/watch`;
exports.watchPath = watchPath;
const guard = (fn) => {
    try {
        return fn();
    }
    catch (e) {
        if (e instanceof watch_logic_1.WatchError)
            throw new https_1.HttpsError(e.code, e.message);
        throw e;
    }
};
/**
 * YouTube oEmbed (no key needed): fills title / channel / thumbnail and
 * refuses private or non-embeddable videos before anyone tries to play them.
 * Network trouble is not fatal: the app's player reports errors too.
 */
async function withOEmbed(video) {
    const url = `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${video.videoId}`)}`;
    let res;
    try {
        res = await fetch(url, { signal: AbortSignal.timeout(3000) });
    }
    catch (e) {
        console.warn('[liveStudio] oembed failed:', e.message);
        return video;
    }
    if (res.status === 401 || res.status === 403 || res.status === 404) {
        throw new https_1.HttpsError('failed-precondition', 'This video cannot be played inside Oneova (it is private or its owner turned off embedding).');
    }
    if (!res.ok)
        return video;
    const body = (await res.json().catch(() => ({})));
    const hit = (0, watch_logic_1.fromYouTubeItem)({
        id: { videoId: video.videoId },
        snippet: { title: body.title, channelTitle: body.author_name, thumbnails: { high: { url: body.thumbnail_url } } },
    });
    return {
        videoId: video.videoId,
        title: video.title || (hit === null || hit === void 0 ? void 0 : hit.title) || '',
        channel: video.channel || (hit === null || hit === void 0 ? void 0 : hit.channel) || '',
        thumbUrl: video.thumbUrl || (hit === null || hit === void 0 ? void 0 : hit.thumbUrl) || '',
    };
}
exports.lsWatch = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    let op = guard(() => (0, watch_logic_1.parseWatchOp)(data));
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    await (0, shared_1.rateLimit)(streamId, uid, 'watch', 8, 2000);
    if (op.op === 'youtube')
        op = { op: 'youtube', video: await withOEmbed(op.video) };
    const ref = (0, shared_1.db)().doc((0, exports.watchPath)(streamId));
    const watch = await (0, shared_1.db)().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const cur = (0, watch_logic_1.normalizeWatch)(snap.exists ? snap.data() : null);
        const next = guard(() => (0, watch_logic_1.applyWatchOp)(cur, op, uid, Date.now()));
        tx.set(ref, next);
        return next;
    });
    return { ok: true, watch };
});
const CACHE_MS = 10 * 60 * 1000;
const cache = new Map();
exports.lsYouTubeSearch = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    const uid = (0, shared_1.requireUid)(req);
    const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const q = (0, watch_logic_1.sanitizeYouTubeQuery)(data.q);
    const pageToken = typeof data.pageToken === 'string' ? data.pageToken.slice(0, 100) : '';
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost']);
    const key = await (0, optionalSecrets_1.optionalSecret)('YOUTUBE_API_KEY');
    if (!key)
        return { enabled: false, items: [], nextPageToken: null };
    if (!q)
        return { enabled: true, items: [], nextPageToken: null };
    const cacheKey = `${q.toLowerCase()}|${pageToken}`;
    const hit = cache.get(cacheKey);
    if (hit && Date.now() - hit.at < CACHE_MS)
        return { enabled: true, items: hit.items, nextPageToken: hit.next };
    await (0, shared_1.rateLimit)(streamId, uid, 'yt_search', 10, 60000);
    const params = new URLSearchParams({
        key,
        part: 'snippet',
        type: 'video',
        videoEmbeddable: 'true',
        safeSearch: 'moderate',
        maxResults: '20',
        q,
    });
    if (pageToken)
        params.set('pageToken', pageToken);
    try {
        const res = await fetch(`https://www.googleapis.com/youtube/v3/search?${params.toString()}`);
        if (!res.ok)
            throw new Error(`YouTube ${res.status}: ${(await res.text()).slice(0, 200)}`);
        const body = (await res.json());
        const items = ((_b = body.items) !== null && _b !== void 0 ? _b : []).map(watch_logic_1.fromYouTubeItem).filter((h) => h !== null);
        const next = (_c = body.nextPageToken) !== null && _c !== void 0 ? _c : null;
        if (cache.size > 200)
            cache.clear();
        cache.set(cacheKey, { at: Date.now(), items, next });
        return { enabled: true, items, nextPageToken: next };
    }
    catch (e) {
        console.warn('[liveStudio] youtube search failed:', e.message);
        throw new https_1.HttpsError('unavailable', 'YouTube search is not available right now.');
    }
});
//# sourceMappingURL=watch.js.map