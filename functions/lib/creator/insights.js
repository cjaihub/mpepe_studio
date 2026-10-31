"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.recordWatchTime = exports.insightsOnEarning = exports.insightsOnFollow = exports.insightsOnComment = exports.insightsOnShare = exports.insightsOnUnlike = exports.insightsOnLike = exports.insightsOnView = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const db = () => (0, firestore_2.getFirestore)();
const day = (d = new Date()) => d.toISOString().slice(0, 10);
function bump(authorId, fields, batch) {
    const ref = db().doc(`creator_daily/${authorId}/days/${day()}`);
    const data = { date: day(), updatedAt: firestore_2.FieldValue.serverTimestamp() };
    for (const [k, v] of Object.entries(fields))
        data[k] = firestore_2.FieldValue.increment(v);
    return batch ? batch.set(ref, data, { merge: true }) : ref.set(data, { merge: true });
}
async function authorOf(contentId) {
    if (!contentId || contentId.includes('/'))
        return null;
    const c = await db().doc(`content/${contentId}`).get();
    const a = c.get('authorId');
    return typeof a === 'string' && a ? a : null;
}
async function onEngagement(contentId, actor, field, delta) {
    const authorId = await authorOf(String(contentId !== null && contentId !== void 0 ? contentId : ''));
    if (!authorId || authorId === actor)
        return;
    await bump(authorId, { [field]: delta });
}
exports.insightsOnView = (0, firestore_1.onDocumentCreated)('content_views/{id}', async (e) => { var _a, _b; return onEngagement((_a = e.data) === null || _a === void 0 ? void 0 : _a.get('contentId'), (_b = e.data) === null || _b === void 0 ? void 0 : _b.get('userId'), 'views', 1); });
exports.insightsOnLike = (0, firestore_1.onDocumentCreated)('content_likes/{id}', async (e) => { var _a, _b; return onEngagement((_a = e.data) === null || _a === void 0 ? void 0 : _a.get('contentId'), (_b = e.data) === null || _b === void 0 ? void 0 : _b.get('userId'), 'likes', 1); });
exports.insightsOnUnlike = (0, firestore_1.onDocumentDeleted)('content_likes/{id}', async (e) => { var _a, _b; return onEngagement((_a = e.data) === null || _a === void 0 ? void 0 : _a.get('contentId'), (_b = e.data) === null || _b === void 0 ? void 0 : _b.get('userId'), 'likes', -1); });
exports.insightsOnShare = (0, firestore_1.onDocumentCreated)('content_reposts/{id}', async (e) => { var _a, _b; return onEngagement((_a = e.data) === null || _a === void 0 ? void 0 : _a.get('contentId'), (_b = e.data) === null || _b === void 0 ? void 0 : _b.get('userId'), 'shares', 1); });
exports.insightsOnComment = (0, firestore_1.onDocumentCreated)('content/{contentId}/comments/{id}', async (e) => { var _a, _b; var _c; return onEngagement(e.params.contentId, (_c = (_a = e.data) === null || _a === void 0 ? void 0 : _a.get('authorId')) !== null && _c !== void 0 ? _c : (_b = e.data) === null || _b === void 0 ? void 0 : _b.get('userId'), 'comments', 1); });
exports.insightsOnFollow = (0, firestore_1.onDocumentWritten)('relationships/{id}', async (e) => {
    var _a, _b, _c;
    const before = (_a = e.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = e.data) === null || _b === void 0 ? void 0 : _b.after.data();
    const was = (before === null || before === void 0 ? void 0 : before.status) === 'accepted';
    const is = (after === null || after === void 0 ? void 0 : after.status) === 'accepted';
    if (was === is)
        return;
    const target = (_c = (after !== null && after !== void 0 ? after : before)) === null || _c === void 0 ? void 0 : _c.followingId;
    if (typeof target !== 'string' || !target)
        return;
    await bump(target, is ? { followsGained: 1 } : { followsLost: 1 });
});
exports.insightsOnEarning = (0, firestore_1.onDocumentCreated)('wallets/{uid}/ledger/{id}', async (e) => {
    var _a, _b, _c;
    var _d;
    const t = (_a = e.data) === null || _a === void 0 ? void 0 : _a.get('type');
    if (t !== 'live_gift_received' && t !== 'user_gift_received')
        return;
    const amount = Number((_d = (_b = e.data) === null || _b === void 0 ? void 0 : _b.get('amount')) !== null && _d !== void 0 ? _d : 0);
    if (!(amount > 0))
        return;
    const batch = db().batch();
    bump(e.params.uid, { giftDiamonds: amount }, batch);
    const contentId = (_c = e.data) === null || _c === void 0 ? void 0 : _c.get('contentId');
    if (typeof contentId === 'string' && contentId && !contentId.includes('/')) {
        batch.set(db().doc(`content/${contentId}`), { giftDiamonds: firestore_2.FieldValue.increment(amount) }, { merge: true });
    }
    await batch.commit();
});
/**
 * Watch time from the feed: [{contentId, watchMs, durationMs}], up to 40 per
 * call. Each item is capped (5 loops, 10 minutes) so nobody can inflate it.
 */
exports.recordWatchTime = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const items = Array.isArray((_b = req.data) === null || _b === void 0 ? void 0 : _b.items) ? req.data.items.slice(0, 40) : [];
    const valid = items
        .map((i) => { var _a; return ({ id: String((_a = i === null || i === void 0 ? void 0 : i.contentId) !== null && _a !== void 0 ? _a : ''), watch: Number(i === null || i === void 0 ? void 0 : i.watchMs), dur: Number(i === null || i === void 0 ? void 0 : i.durationMs) }); })
        .filter((i) => i.id && !i.id.includes('/') && i.watch >= 500 && i.dur >= 1000 && i.dur <= 3600000);
    if (!valid.length)
        return { ok: true, n: 0 };
    const docs = await db().getAll(...valid.map((i) => db().doc(`content/${i.id}`)));
    const batch = db().batch();
    const perAuthor = new Map();
    let n = 0;
    docs.forEach((d, k) => {
        var _a;
        const authorId = d.get('authorId');
        if (!d.exists || typeof authorId !== 'string' || authorId === uid)
            return;
        const { watch, dur } = valid[k];
        const ms = Math.round(Math.min(watch, dur * 5, 600000));
        const complete = ms >= dur * 0.9 ? 1 : 0;
        batch.update(d.ref, Object.assign({ playCount: firestore_2.FieldValue.increment(1), watchTimeMs: firestore_2.FieldValue.increment(ms), completionCount: firestore_2.FieldValue.increment(complete) }, (d.get('mediaMetadata.durationMs') ? {} : { 'mediaMetadata.durationMs': Math.round(dur) })));
        const a = (_a = perAuthor.get(authorId)) !== null && _a !== void 0 ? _a : { plays: 0, watchMs: 0, completes: 0 };
        a.plays += 1;
        a.watchMs += ms;
        a.completes += complete;
        perAuthor.set(authorId, a);
        n++;
    });
    for (const [authorId, a] of perAuthor)
        bump(authorId, a, batch);
    if (n)
        await batch.commit();
    return { ok: true, n };
});
//# sourceMappingURL=insights.js.map