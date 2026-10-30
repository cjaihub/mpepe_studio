"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsGifSearch = exports.lsLivekitWebhook = exports.lsShare = exports.lsReact = exports.lsMuteChat = exports.lsDeleteComment = exports.lsComment = void 0;
/**
 * LIVE STUDIO v2 — realtime social callables (workstream #2).
 *
 * lsComment · lsDeleteComment · lsMuteChat · lsReact · lsShare ·
 * lsLivekitWebhook (counts + joined lines).
 *
 * Firestore is the source of record; LiveKit data messages (via
 * `broadcast()`) are the fan-out. Pure decisions live in `social_logic.ts`.
 *
 * ── Scale design ─────────────────────────────────────────────────────────────
 *
 * Comment broadcast sampling (ARCHITECTURE §5, 25/s):
 *   Every comment is persisted. Host/co-host comments are always broadcast.
 *   Others pass two gates:
 *   1. an in-memory per-instance, per-stream 1-second counter (free, no I/O).
 *      Best effort: it only sees this instance's share of the traffic, so it
 *      alone would allow instances × 25/s.
 *   2. a global Firestore gate: COMMENT_GATE_SHARDS docs
 *      `studio_counters/chat_gate_{k}` each holding `{sec, n}` with a budget of
 *      ceil(25 / shards) per second. A comment picks a random shard and
 *      claims a slot in a small transaction. Sharding keeps each doc near the
 *      Firestore per-document write rate, and once a shard is full for the
 *      current second, the instance memoizes that and skips it without I/O.
 *   On any gate error the comment is not broadcast (fail closed). It is still
 *   persisted and visible to late joiners, and the author's client confirms
 *   its own row from the callable result.
 *
 * Reaction aggregation (100k viewers must not mean 100k broadcasts):
 *   Each call increments one of 10 shards `studio_counters/shard_{i}` with
 *   FieldValue.increment (no transaction, no contention). It then tries to
 *   claim the window lease `studio_counters/agg.leaseAt`:
 *   - a per-instance memo skips the check while the lease is known to be held;
 *   - otherwise a plain read decides, and only when the lease looks free does
 *     a transaction claim it.
 *   The single claimer per window (the "flush leader") waits until the
 *   window closes (≤ 500 ms + grace, inside its own invocation, because Cloud
 *   Run throttles CPU after the response), sums the shards, computes deltas
 *   against `agg.flushed` (the totals last broadcast), stores the new
 *   `flushed` and sends ONE lossy `reaction.agg`. So the broadcast rate is
 *   ≤ 2/s per stream regardless of audience size, and increments that miss a
 *   window's read show up in the next delta (never lost). A window with no
 *   calls has no leader and sends nothing ("only when non-zero").
 *
 * Counts (webhook): join/leave events update a ±1 viewer counter on the same
 * shards. `counts` is broadcast (lossy) at most every countsIntervalMs and
 * only when changed, and studio/state `counts` is patched at most every 10 s,
 * both through leases on `studio_counters/presence`. `joined` lines are sent
 * for every join in rooms up to LARGE_ROOM_VIEWERS, and at most 1/s above.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const livekit_server_sdk_1 = require("livekit-server-sdk");
const controls_1 = require("./controls");
const security_1 = require("./security");
const lifecycle_1 = require("./lifecycle");
const gif_logic_1 = require("./gif_logic");
const optionalSecrets_1 = require("../optionalSecrets");
const broadcast_1 = require("./broadcast");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const social_logic_1 = require("./social_logic");
// ─── Small helpers ──────────────────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const counterDoc = (streamId, name) => (0, shared_1.db)().doc(`${contracts_1.Paths.counters(streamId)}/${name}`);
const shardRefs = (streamId) => Array.from({ length: social_logic_1.COUNTER_SHARDS }, (_, i) => counterDoc(streamId, `shard_${i}`));
const muteRef = (streamId, uid) => (0, shared_1.db)().doc(`${contracts_1.Paths.rate(streamId)}/${uid}_chatmute`);
function requireStreamId(data) {
    const id = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    if (!/^[A-Za-z0-9_-]+$/.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Invalid streamId.');
    return id;
}
const asData = (d) => (d && typeof d === 'object' ? d : {});
const leaseMemo = new social_logic_1.LeaseMemo();
/**
 * Claims a time lease stored as `field` (ms) on [ref]: returns true for the
 * single caller that may act now, false while the lease is held. A memo
 * avoids Firestore I/O while a lease is known to be held, and a plain read
 * precedes the transaction so hot paths rarely take locks.
 */
async function claimLease(ref, field, intervalMs, nowMs = Date.now()) {
    const key = `${ref.path}#${field}`;
    if (leaseMemo.blocked(key, nowMs))
        return null;
    const snap = await ref.get();
    const last = snap.get(field);
    if (!(0, social_logic_1.throttleDue)(last, nowMs, intervalMs)) {
        leaseMemo.hold(key, (last !== null && last !== void 0 ? last : nowMs) + intervalMs);
        return null;
    }
    const claimed = await (0, shared_1.db)().runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const l = s.get(field);
        if (!(0, social_logic_1.throttleDue)(l, nowMs, intervalMs))
            return false;
        tx.set(ref, { [field]: nowMs }, { merge: true });
        return true;
    });
    leaseMemo.hold(key, nowMs + intervalMs);
    return claimed ? nowMs : null;
}
async function sendSystemLine(streamId, kind, who) {
    const ts = Date.now();
    await (0, shared_1.broadcast)(streamId, 'chat', {
        v: 1,
        type: 'system',
        id: (0, social_logic_1.systemLineId)(ts, Math.random()),
        kind,
        uid: who.uid,
        name: who.name,
        avatarUrl: who.avatarUrl,
        text: social_logic_1.SYSTEM_TEXT[kind],
        ts,
    });
}
async function profileOf(uid) {
    if (!uid || uid.includes('/'))
        return { name: (0, social_logic_1.displayNameOf)(undefined), avatarUrl: '' };
    const snap = await (0, shared_1.db)().doc(`users/${uid}`).get();
    const d = snap.exists ? snap.data() : undefined;
    return { name: (0, social_logic_1.displayNameOf)(d), avatarUrl: (0, social_logic_1.avatarOf)(d) };
}
/** Patches studio/state `counts` at most every COUNTS_STATE_INTERVAL_MS (lease per [leaseField]). */
async function maybePatchCountsState(streamId, leaseField, build) {
    const lease = await claimLease(counterDoc(streamId, 'presence'), leaseField, social_logic_1.COUNTS_STATE_INTERVAL_MS);
    if (lease === null)
        return;
    await (0, shared_1.patchState)(streamId, 'counts', async (s) => {
        var _a;
        const cur = (_a = s.counts) !== null && _a !== void 0 ? _a : { viewers: 0, participants: 0, loves: 0, sparkles: 0, shares: 0 };
        const next = await build(cur);
        if (!next)
            return undefined;
        const same = Object.keys(next).every((k) => next[k] === cur[k]);
        return same ? undefined : next;
    });
}
async function shardTotals(streamId) {
    const snaps = await (0, shared_1.db)().getAll(...shardRefs(streamId));
    return (0, social_logic_1.sumShards)(snaps.map((s) => (s.exists ? s.data() : undefined)));
}
// ─── lsComment ──────────────────────────────────────────────────────────────
const localCommentWindow = new social_logic_1.SecondWindowCounter();
const fullGateShards = new social_logic_1.LeaseMemo();
/** Global per-second budget gate (see header). Returns null on error. */
async function globalCommentGate(streamId, nowMs) {
    const shard = (0, social_logic_1.pickShard)(Math.random(), social_logic_1.COMMENT_GATE_SHARDS);
    const key = `${streamId}#${shard}`;
    if (fullGateShards.blocked(key, nowMs))
        return false;
    const ref = counterDoc(streamId, `chat_gate_${shard}`);
    const budget = (0, social_logic_1.shardBudget)(contracts_1.Limits.commentBroadcastPerSecond, social_logic_1.COMMENT_GATE_SHARDS);
    try {
        const allow = await (0, shared_1.db)().runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const step = (0, social_logic_1.gateStep)(snap.exists ? snap.data() : undefined, nowMs, budget);
            if (step.next)
                tx.set(ref, step.next);
            return step.allow;
        });
        if (!allow)
            fullGateShards.hold(key, ((0, social_logic_1.epochSecond)(nowMs) + 1) * 1000);
        return allow;
    }
    catch (e) {
        console.warn(`[liveStudio] comment gate failed for ${streamId}:`, e.message);
        return null;
    }
}
exports.lsComment = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a, _b, _c, _d;
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = requireStreamId(data);
    const gif = (0, gif_logic_1.parseCommentGif)(data.gif);
    if (gif === 'invalid')
        throw new https_1.HttpsError('invalid-argument', 'That GIF cannot be posted.');
    // A GIF may be posted on its own; it then carries the text "GIF".
    const rawText = gif && (typeof data.text !== 'string' || !data.text.trim()) ? 'GIF' : data.text;
    const norm = (0, social_logic_1.normalizeCommentText)(rawText);
    if (!norm.ok)
        throw new https_1.HttpsError('invalid-argument', norm.reason);
    const clientId = data.clientId === undefined ? undefined : data.clientId;
    if (clientId !== undefined && !(0, social_logic_1.isValidClientId)(clientId))
        throw new https_1.HttpsError('invalid-argument', 'Invalid clientId.');
    // One round trip for every precondition read.
    const [stateSnap, blockSnap, memberSnap, muteSnap, userSnap] = await (0, shared_1.db)().getAll((0, shared_1.db)().doc(contracts_1.Paths.state(streamId)), (0, shared_1.db)().doc(`${contracts_1.Paths.blocks(streamId)}/${uid}`), (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`), muteRef(streamId, uid), (0, shared_1.db)().doc(`users/${uid}`));
    if (!stateSnap.exists)
        throw new https_1.HttpsError('not-found', 'This live does not exist.');
    const state = stateSnap.data();
    if (state.status !== 'live')
        throw new https_1.HttpsError('failed-precondition', 'This live is not on air.');
    if (blockSnap.exists)
        throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
    const member = memberSnap.exists ? memberSnap.data() : undefined;
    const role = state.hostId === uid ? 'host' : ((_a = member === null || member === void 0 ? void 0 : member.role) !== null && _a !== void 0 ? _a : 'viewer');
    const now = Date.now();
    if (role !== 'host' && (0, social_logic_1.isChatMuted)(member === null || member === void 0 ? void 0 : member.chatMuted, muteSnap.get('until'), now)) {
        throw new https_1.HttpsError('permission-denied', 'You are muted in this chat.');
    }
    void (0, security_1.recordStudioSignal)(streamId, uid, 'comment');
    await (0, controls_1.enforceChatMode)(streamId, uid, role, state.hostId);
    await (0, shared_1.rateLimit)(streamId, uid, 'cmt_int', 1, contracts_1.Limits.commentMinIntervalMs);
    await (0, shared_1.rateLimit)(streamId, uid, 'cmt_min', contracts_1.Limits.commentsPerMinute, 60000);
    const verdict = await (0, social_logic_1.moderateComment)(norm.text, uid);
    if (!verdict.allow)
        throw new https_1.HttpsError('invalid-argument', (_b = verdict.reason) !== null && _b !== void 0 ? _b : 'This comment was not allowed.');
    const text = (0, social_logic_1.normalizeCommentText)(verdict.text);
    if (!text.ok)
        throw new https_1.HttpsError('invalid-argument', text.reason);
    const u = userSnap.exists ? userSnap.data() : undefined;
    const coll = (0, shared_1.db)().collection(contracts_1.Paths.comments(streamId));
    const ref = clientId ? coll.doc((0, social_logic_1.commentDocId)(uid, clientId)) : coll.doc();
    const comment = Object.assign({ id: ref.id, uid, name: (member === null || member === void 0 ? void 0 : member.displayName) || (0, social_logic_1.displayNameOf)(u), avatarUrl: (member === null || member === void 0 ? void 0 : member.avatarUrl) || (0, social_logic_1.avatarOf)(u), text: text.text, ts: now }, (gif ? { gif } : {}));
    try {
        await ref.create(comment);
    }
    catch (e) {
        // ALREADY_EXISTS (gRPC 6): a retry of the same clientId. Idempotent success.
        if (e.code === 6) {
            const prev = (await ref.get()).data();
            return { id: ref.id, ts: (_c = prev === null || prev === void 0 ? void 0 : prev.ts) !== null && _c !== void 0 ? _c : now, text: (_d = prev === null || prev === void 0 ? void 0 : prev.text) !== null && _d !== void 0 ? _d : comment.text, broadcast: false };
        }
        throw e;
    }
    const local = localCommentWindow.hit(streamId, now);
    const globalAllow = (0, contracts_1.isManager)(role) || local > contracts_1.Limits.commentBroadcastPerSecond ? null : await globalCommentGate(streamId, now);
    const send = (0, social_logic_1.shouldBroadcastComment)({ role, localCountThisSecond: local, globalAllow });
    if (send)
        await (0, shared_1.broadcast)(streamId, 'chat', Object.assign({ v: 1, type: 'comment' }, comment));
    return { id: comment.id, ts: comment.ts, text: comment.text, broadcast: send };
});
// ─── lsDeleteComment ────────────────────────────────────────────────────────
exports.lsDeleteComment = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = requireStreamId(data);
    const commentId = (0, shared_1.requireString)(data.commentId, 'commentId', 200);
    if (commentId.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Invalid commentId.');
    const state = await (0, shared_1.loadState)(streamId);
    const role = await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost', 'guest', 'viewer'], state);
    const ref = (0, shared_1.db)().doc(`${contracts_1.Paths.comments(streamId)}/${commentId}`);
    const snap = await ref.get();
    if (!snap.exists)
        return { deleted: false };
    const author = (_a = snap.get('uid')) !== null && _a !== void 0 ? _a : '';
    if (!(0, social_logic_1.canDeleteComment)(role, uid, author))
        throw new https_1.HttpsError('permission-denied', 'You cannot delete this comment.');
    await ref.delete();
    await (0, shared_1.broadcast)(streamId, 'chat', { v: 1, type: 'comment.deleted', id: commentId, ts: Date.now() });
    return { deleted: true };
});
// ─── lsMuteChat ─────────────────────────────────────────────────────────────
exports.lsMuteChat = (0, https_1.onCall)(async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = requireStreamId(data);
    const target = (0, shared_1.requireString)(data.uid, 'uid', 128);
    const minutes = (0, social_logic_1.parseMuteMinutes)(data.minutes);
    if (minutes === null)
        throw new https_1.HttpsError('invalid-argument', 'minutes must be 0–1440 (0 unmutes).');
    const state = await (0, shared_1.loadState)(streamId);
    const actorRole = await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    const targetRole = await (0, shared_1.roleOf)(streamId, target, state);
    if (!(0, social_logic_1.canMuteChat)(actorRole, uid, targetRole, target))
        throw new https_1.HttpsError('permission-denied', 'You cannot mute this user.');
    const ref = muteRef(streamId, target);
    if (minutes === 0) {
        await ref.delete();
        return { until: 0 };
    }
    const until = (0, social_logic_1.muteUntil)(Date.now(), minutes);
    await ref.set({ until, by: uid, at: firestore_1.FieldValue.serverTimestamp() });
    return { until };
});
// ─── lsReact ────────────────────────────────────────────────────────────────
async function flushReactions(streamId, leaseAt, state) {
    var _a;
    await sleep((0, social_logic_1.flushDelayMs)(leaseAt, Date.now()));
    const totals = await shardTotals(streamId);
    const aggRef = counterDoc(streamId, 'agg');
    const deltas = await (0, shared_1.db)().runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(aggRef);
        const flushed = snap.get('flushed');
        const d = (0, social_logic_1.reactionDeltas)(totals, flushed);
        // Monotonic: never move `flushed` backwards if a slower leader commits late.
        tx.set(aggRef, { flushed: { loves: Math.max(totals.loves, (_a = flushed === null || flushed === void 0 ? void 0 : flushed.loves) !== null && _a !== void 0 ? _a : 0), sparkles: Math.max(totals.sparkles, (_b = flushed === null || flushed === void 0 ? void 0 : flushed.sparkles) !== null && _b !== void 0 ? _b : 0) } }, { merge: true });
        return d;
    });
    if (deltas.loves === 0 && deltas.sparkles === 0)
        return;
    const counts = Object.assign(Object.assign({}, ((_a = state.counts) !== null && _a !== void 0 ? _a : { viewers: 0, participants: 0, loves: 0, sparkles: 0, shares: 0 })), { loves: totals.loves, sparkles: totals.sparkles, shares: totals.shares });
    await (0, shared_1.broadcast)(streamId, 'react', { v: 1, type: 'reaction.agg', loves: deltas.loves, sparkles: deltas.sparkles, totals: counts, ts: Date.now() }, { lossy: true });
    await maybePatchCountsState(streamId, 'stateReactAt', (cur) => (Object.assign(Object.assign({}, cur), { loves: totals.loves, sparkles: totals.sparkles, shares: totals.shares })));
}
exports.lsReact = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = requireStreamId(data);
    const r = (0, social_logic_1.parseReaction)(data.kind, data.n);
    if (!r.ok)
        throw new https_1.HttpsError('invalid-argument', r.reason);
    const [stateSnap, blockSnap] = await (0, shared_1.db)().getAll((0, shared_1.db)().doc(contracts_1.Paths.state(streamId)), (0, shared_1.db)().doc(`${contracts_1.Paths.blocks(streamId)}/${uid}`));
    if (!stateSnap.exists)
        throw new https_1.HttpsError('not-found', 'This live does not exist.');
    const state = stateSnap.data();
    if (state.status !== 'live')
        throw new https_1.HttpsError('failed-precondition', 'This live is not on air.');
    if (blockSnap.exists)
        throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
    await (0, shared_1.rateLimit)(streamId, uid, 'react', contracts_1.Limits.reactionCallsPerSecond, 1000);
    const field = (0, social_logic_1.reactionField)(r.kind);
    await shardRefs(streamId)[(0, social_logic_1.pickShard)(Math.random())].set({ [field]: firestore_1.FieldValue.increment(r.n) }, { merge: true });
    // System line, at most one per user per 10 s.
    const lineLease = await claimLease((0, shared_1.db)().doc(`${contracts_1.Paths.rate(streamId)}/${uid}_reactline`), 'at', social_logic_1.SYSTEM_LINE_USER_INTERVAL_MS);
    if (lineLease !== null) {
        const p = await profileOf(uid);
        await sendSystemLine(streamId, (0, social_logic_1.systemKindForReaction)(r.kind), Object.assign({ uid }, p));
    }
    // Aggregated broadcast: only the window's lease holder flushes.
    const leaseAt = await claimLease(counterDoc(streamId, 'agg'), 'leaseAt', contracts_1.Limits.reactionAggregateWindowMs);
    if (leaseAt !== null)
        await flushReactions(streamId, leaseAt, state);
    return { ok: true, flushed: leaseAt !== null };
});
// ─── lsShare ────────────────────────────────────────────────────────────────
exports.lsShare = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = requireStreamId(data);
    const state = await (0, shared_1.loadState)(streamId);
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost', 'guest', 'viewer'], state);
    const url = (0, contracts_1.shareUrl)(streamId);
    if (state.status !== 'live')
        return { url };
    // Count and announce at most once per user per 10 s; the link is always returned.
    const lease = await claimLease((0, shared_1.db)().doc(`${contracts_1.Paths.rate(streamId)}/${uid}_shareline`), 'at', social_logic_1.SYSTEM_LINE_USER_INTERVAL_MS);
    if (lease === null)
        return { url };
    await shardRefs(streamId)[(0, social_logic_1.pickShard)(Math.random())].set({ shares: firestore_1.FieldValue.increment(1) }, { merge: true });
    const p = await profileOf(uid);
    await sendSystemLine(streamId, 'shared', Object.assign({ uid }, p));
    await maybePatchCountsState(streamId, 'stateShareAt', async (cur) => (Object.assign(Object.assign({}, cur), { shares: (await shardTotals(streamId)).shares })));
    return { url };
});
// ─── lsLivekitWebhook ───────────────────────────────────────────────────────
async function participantsOf(streamId, state) {
    const [coHosts, pending] = await Promise.all([
        (0, shared_1.db)().collection(contracts_1.Paths.members(streamId)).where('role', '==', 'coHost').select().get(),
        (0, shared_1.db)().collection(contracts_1.Paths.requests(streamId)).where('status', '==', 'pending').count().get(),
    ]);
    return (0, social_logic_1.computeParticipants)((0, social_logic_1.stagePublishers)(state.stage), coHosts.docs.map((d) => d.id), pending.data().count);
}
async function handlePresence(streamId, joined, participant, roomNum) {
    var _a;
    await shardRefs(streamId)[(0, social_logic_1.pickShard)(Math.random())].set({ viewers: firestore_1.FieldValue.increment(joined ? 1 : -1) }, { merge: true });
    const presence = counterDoc(streamId, 'presence');
    let viewers;
    const viewersNow = async () => (viewers !== null && viewers !== void 0 ? viewers : (viewers = (0, social_logic_1.resolveViewers)(roomNum, (await shardTotals(streamId)).viewers)));
    if (joined && participant.identity) {
        const n = typeof roomNum === 'number' && roomNum > 0 ? roomNum : await viewersNow();
        const emit = (0, social_logic_1.joinLineMode)(n) === 'always' || (await claimLease(presence, 'joinLineAt', social_logic_1.JOIN_LINE_INTERVAL_MS)) !== null;
        if (emit) {
            const p = await profileOf(participant.identity);
            await sendSystemLine(streamId, 'joined', {
                uid: participant.identity,
                name: ((_a = participant.name) === null || _a === void 0 ? void 0 : _a.trim()) || p.name,
                avatarUrl: p.avatarUrl,
            });
        }
    }
    const countsLease = await claimLease(presence, 'countsAt', contracts_1.Limits.countsIntervalMs);
    if (countsLease === null)
        return;
    const state = await (0, shared_1.loadState)(streamId);
    const next = { viewers: await viewersNow(), participants: await participantsOf(streamId, state) };
    const prev = (await presence.get()).get('last');
    if ((0, social_logic_1.countsChanged)(prev, next)) {
        await presence.set({ last: next }, { merge: true });
        await (0, shared_1.broadcast)(streamId, 'counts', Object.assign(Object.assign({ v: 1, type: 'counts' }, next), { ts: Date.now() }), { lossy: true });
    }
    await maybePatchCountsState(streamId, 'statePresenceAt', (cur) => (Object.assign(Object.assign({}, cur), next)));
}
exports.lsLivekitWebhook = (0, https_1.onRequest)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req, res) => {
    var _a, _b;
    var _c, _d, _e;
    if (req.method !== 'POST') {
        res.status(405).send('Method not allowed');
        return;
    }
    const receiver = new livekit_server_sdk_1.WebhookReceiver(shared_1.LIVEKIT_API_KEY.value(), shared_1.LIVEKIT_API_SECRET.value());
    let event;
    try {
        const body = req.rawBody ? req.rawBody.toString('utf8') : JSON.stringify((_c = req.body) !== null && _c !== void 0 ? _c : {});
        event = await receiver.receive(body, (_d = req.get('Authorization')) !== null && _d !== void 0 ? _d : req.get('Authorize'));
    }
    catch (e) {
        console.warn('[liveStudio] webhook rejected:', e.message);
        res.status(401).send('Invalid signature');
        return;
    }
    try {
        const streamId = (0, social_logic_1.streamIdFromRoom)((_a = event.room) === null || _a === void 0 ? void 0 : _a.name);
        const p = event.participant;
        // Only standard clients count as viewers (kind 0); skip egress/ingress/agents.
        if (event.event === 'egress_ended' && event.egressInfo) {
            await (0, broadcast_1.onEgressEnded)(event.egressInfo);
        }
        if (streamId && event.event === 'room_finished') {
            // The room closed (empty timeout / deleted): the live is over.
            await (0, lifecycle_1.endStudioStream)(streamId, 'room_closed');
        }
        if (streamId && p && ((_e = p.kind) !== null && _e !== void 0 ? _e : 0) === 0 && (event.event === 'participant_joined' || event.event === 'participant_left')) {
            await (0, lifecycle_1.onHostPresence)(streamId, p.identity, event.event === 'participant_joined');
            await handlePresence(streamId, event.event === 'participant_joined', { identity: p.identity, name: p.name }, (_b = event.room) === null || _b === void 0 ? void 0 : _b.numParticipants);
        }
    }
    catch (e) {
        // Never make LiveKit retry storms: log and acknowledge.
        console.error('[liveStudio] webhook handling failed:', e.message);
    }
    res.status(200).send('ok');
});
// ─── lsGifSearch ────────────────────────────────────────────────────────────
/**
 * GIF search for comments (GIPHY). `{q?}` → `{gifs: [{id, url, w, h}], enabled}`.
 * Trending when q is empty. The GIPHY key is optional (GIPHY_API_KEY in
 * Secret Manager, read at run time): without it `enabled` is false.
 */
exports.lsGifSearch = (0, https_1.onCall)(async (req) => {
    var _a;
    (0, shared_1.requireUid)(req);
    const q = (0, gif_logic_1.sanitizeGifQuery)(asData(req.data).q);
    const key = await (0, optionalSecrets_1.optionalSecret)('GIPHY_API_KEY');
    if (!key)
        return { gifs: [], enabled: false };
    const params = new URLSearchParams({ api_key: key, limit: '24', rating: 'pg-13', bundle: 'messaging_non_clips' });
    if (q)
        params.set('q', q);
    const url = `https://api.giphy.com/v1/gifs/${q ? 'search' : 'trending'}?${params.toString()}`;
    try {
        const res = await fetch(url);
        if (!res.ok)
            throw new Error(`GIPHY ${res.status}`);
        const body = (await res.json());
        const gifs = ((_a = body.data) !== null && _a !== void 0 ? _a : []).map(gif_logic_1.fromGiphy).filter((g) => g !== null);
        return { gifs, enabled: true };
    }
    catch (e) {
        console.warn('[liveStudio] gif search failed:', e.message);
        throw new https_1.HttpsError('unavailable', 'GIF search is not available right now.');
    }
});
//# sourceMappingURL=social.js.map