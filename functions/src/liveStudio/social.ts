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
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, DocumentReference } from 'firebase-admin/firestore';
import { WebhookReceiver } from 'livekit-server-sdk';
import { enforceChatMode } from './controls';
import { recordStudioSignal } from './security';
import { endStudioStream, onHostPresence } from './lifecycle';
import { parseCommentGif, fromGiphy, sanitizeGifQuery } from './gif_logic';
import { optionalSecret } from '../optionalSecrets';
import { onEgressEnded } from './broadcast';
import { Paths, Limits, StudioRole, StudioState, StageMember, ReactionKind, StudioCounts, shareUrl, isManager } from './contracts';
import {
  LIVEKIT_SECRETS,
  LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET,
  db,
  requireUid,
  requireString,
  loadState,
  roleOf,
  requireRole,
  patchState,
  broadcast,
  rateLimit,
} from './shared';
import {
  normalizeCommentText,
  isValidClientId,
  commentDocId,
  moderateComment,
  isChatMuted,
  canDeleteComment,
  canMuteChat,
  parseMuteMinutes,
  muteUntil,
  SecondWindowCounter,
  shouldBroadcastComment,
  gateStep,
  shardBudget,
  epochSecond,
  COMMENT_GATE_SHARDS,
  LeaseMemo,
  throttleDue,
  parseReaction,
  reactionField,
  systemKindForReaction,
  SYSTEM_TEXT,
  SYSTEM_LINE_USER_INTERVAL_MS,
  COUNTS_STATE_INTERVAL_MS,
  JOIN_LINE_INTERVAL_MS,
  pickShard,
  COUNTER_SHARDS,
  sumShards,
  reactionDeltas,
  flushDelayMs,
  streamIdFromRoom,
  resolveViewers,
  computeParticipants,
  stagePublishers,
  countsChanged,
  joinLineMode,
  systemLineId,
  displayNameOf,
  avatarOf,
} from './social_logic';

// ─── Small helpers ──────────────────────────────────────────────────────────

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

const counterDoc = (streamId: string, name: string) => db().doc(`${Paths.counters(streamId)}/${name}`);
const shardRefs = (streamId: string) =>
  Array.from({ length: COUNTER_SHARDS }, (_, i) => counterDoc(streamId, `shard_${i}`));

const muteRef = (streamId: string, uid: string) => db().doc(`${Paths.rate(streamId)}/${uid}_chatmute`);

function requireStreamId(data: Record<string, unknown>): string {
  const id = requireString(data.streamId, 'streamId', 128);
  if (!/^[A-Za-z0-9_-]+$/.test(id)) throw new HttpsError('invalid-argument', 'Invalid streamId.');
  return id;
}

const asData = (d: unknown): Record<string, unknown> => (d && typeof d === 'object' ? (d as Record<string, unknown>) : {});

const leaseMemo = new LeaseMemo();

/**
 * Claims a time lease stored as `field` (ms) on [ref]: returns true for the
 * single caller that may act now, false while the lease is held. A memo
 * avoids Firestore I/O while a lease is known to be held, and a plain read
 * precedes the transaction so hot paths rarely take locks.
 */
async function claimLease(ref: DocumentReference, field: string, intervalMs: number, nowMs = Date.now()): Promise<number | null> {
  const key = `${ref.path}#${field}`;
  if (leaseMemo.blocked(key, nowMs)) return null;
  const snap = await ref.get();
  const last = snap.get(field) as number | undefined;
  if (!throttleDue(last, nowMs, intervalMs)) {
    leaseMemo.hold(key, (last ?? nowMs) + intervalMs);
    return null;
  }
  const claimed = await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const l = s.get(field) as number | undefined;
    if (!throttleDue(l, nowMs, intervalMs)) return false;
    tx.set(ref, { [field]: nowMs }, { merge: true });
    return true;
  });
  leaseMemo.hold(key, nowMs + intervalMs);
  return claimed ? nowMs : null;
}

async function sendSystemLine(
  streamId: string,
  kind: keyof typeof SYSTEM_TEXT,
  who: { uid: string; name: string; avatarUrl: string },
): Promise<void> {
  const ts = Date.now();
  await broadcast(streamId, 'chat', {
    v: 1,
    type: 'system',
    id: systemLineId(ts, Math.random()),
    kind,
    uid: who.uid,
    name: who.name,
    avatarUrl: who.avatarUrl,
    text: SYSTEM_TEXT[kind],
    ts,
  });
}

async function profileOf(uid: string): Promise<{ name: string; avatarUrl: string }> {
  if (!uid || uid.includes('/')) return { name: displayNameOf(undefined), avatarUrl: '' };
  const snap = await db().doc(`users/${uid}`).get();
  const d = snap.exists ? (snap.data() as Record<string, unknown>) : undefined;
  return { name: displayNameOf(d), avatarUrl: avatarOf(d) };
}

/** Patches studio/state `counts` at most every COUNTS_STATE_INTERVAL_MS (lease per [leaseField]). */
async function maybePatchCountsState(
  streamId: string,
  leaseField: string,
  build: (current: StudioCounts) => Promise<StudioCounts | undefined> | StudioCounts | undefined,
): Promise<void> {
  const lease = await claimLease(counterDoc(streamId, 'presence'), leaseField, COUNTS_STATE_INTERVAL_MS);
  if (lease === null) return;
  await patchState(streamId, 'counts', async (s) => {
    const cur = s.counts ?? { viewers: 0, participants: 0, loves: 0, sparkles: 0, shares: 0 };
    const next = await build(cur);
    if (!next) return undefined;
    const same = (Object.keys(next) as (keyof StudioCounts)[]).every((k) => next[k] === cur[k]);
    return same ? undefined : next;
  });
}

async function shardTotals(streamId: string) {
  const snaps = await db().getAll(...shardRefs(streamId));
  return sumShards(snaps.map((s) => (s.exists ? (s.data() as Record<string, unknown>) : undefined)));
}

// ─── lsComment ──────────────────────────────────────────────────────────────

const localCommentWindow = new SecondWindowCounter();
const fullGateShards = new LeaseMemo();

/** Global per-second budget gate (see header). Returns null on error. */
async function globalCommentGate(streamId: string, nowMs: number): Promise<boolean | null> {
  const shard = pickShard(Math.random(), COMMENT_GATE_SHARDS);
  const key = `${streamId}#${shard}`;
  if (fullGateShards.blocked(key, nowMs)) return false;
  const ref = counterDoc(streamId, `chat_gate_${shard}`);
  const budget = shardBudget(Limits.commentBroadcastPerSecond, COMMENT_GATE_SHARDS);
  try {
    const allow = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const step = gateStep(snap.exists ? (snap.data() as { sec?: number; n?: number }) : undefined, nowMs, budget);
      if (step.next) tx.set(ref, step.next);
      return step.allow;
    });
    if (!allow) fullGateShards.hold(key, (epochSecond(nowMs) + 1) * 1000);
    return allow;
  } catch (e) {
    console.warn(`[liveStudio] comment gate failed for ${streamId}:`, (e as Error).message);
    return null;
  }
}

export const lsComment = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireStreamId(data);
  const gif = parseCommentGif(data.gif);
  if (gif === 'invalid') throw new HttpsError('invalid-argument', 'That GIF cannot be posted.');
  // A GIF may be posted on its own; it then carries the text "GIF".
  const rawText = gif && (typeof data.text !== 'string' || !data.text.trim()) ? 'GIF' : data.text;
  const norm = normalizeCommentText(rawText);
  if (!norm.ok) throw new HttpsError('invalid-argument', norm.reason);
  const clientId = data.clientId === undefined ? undefined : data.clientId;
  if (clientId !== undefined && !isValidClientId(clientId)) throw new HttpsError('invalid-argument', 'Invalid clientId.');

  // One round trip for every precondition read.
  const [stateSnap, blockSnap, memberSnap, muteSnap, userSnap] = await db().getAll(
    db().doc(Paths.state(streamId)),
    db().doc(`${Paths.blocks(streamId)}/${uid}`),
    db().doc(`${Paths.members(streamId)}/${uid}`),
    muteRef(streamId, uid),
    db().doc(`users/${uid}`),
  );
  if (!stateSnap.exists) throw new HttpsError('not-found', 'This live does not exist.');
  const state = stateSnap.data() as StudioState;
  if (state.status !== 'live') throw new HttpsError('failed-precondition', 'This live is not on air.');
  if (blockSnap.exists) throw new HttpsError('permission-denied', 'You are blocked from this live.');
  const member = memberSnap.exists ? (memberSnap.data() as StageMember) : undefined;
  const role: StudioRole = state.hostId === uid ? 'host' : (member?.role ?? 'viewer');
  const now = Date.now();
  if (role !== 'host' && isChatMuted(member?.chatMuted, muteSnap.get('until') as number | undefined, now)) {
    throw new HttpsError('permission-denied', 'You are muted in this chat.');
  }

  void recordStudioSignal(streamId, uid, 'comment');
  await enforceChatMode(streamId, uid, role, state.hostId);
  await rateLimit(streamId, uid, 'cmt_int', 1, Limits.commentMinIntervalMs);
  await rateLimit(streamId, uid, 'cmt_min', Limits.commentsPerMinute, 60_000);

  const verdict = await moderateComment(norm.text, uid);
  if (!verdict.allow) throw new HttpsError('invalid-argument', verdict.reason ?? 'This comment was not allowed.');
  const text = normalizeCommentText(verdict.text);
  if (!text.ok) throw new HttpsError('invalid-argument', text.reason);

  const u = userSnap.exists ? (userSnap.data() as Record<string, unknown>) : undefined;
  const coll = db().collection(Paths.comments(streamId));
  const ref = clientId ? coll.doc(commentDocId(uid, clientId)) : coll.doc();
  const comment = {
    id: ref.id,
    uid,
    name: member?.displayName || displayNameOf(u),
    avatarUrl: member?.avatarUrl || avatarOf(u),
    text: text.text,
    ts: now,
    ...(gif ? { gif } : {}),
  };
  try {
    await ref.create(comment);
  } catch (e) {
    // ALREADY_EXISTS (gRPC 6): a retry of the same clientId. Idempotent success.
    if ((e as { code?: number }).code === 6) {
      const prev = (await ref.get()).data() as typeof comment | undefined;
      return { id: ref.id, ts: prev?.ts ?? now, text: prev?.text ?? comment.text, broadcast: false };
    }
    throw e;
  }

  const local = localCommentWindow.hit(streamId, now);
  const globalAllow = isManager(role) || local > Limits.commentBroadcastPerSecond ? null : await globalCommentGate(streamId, now);
  const send = shouldBroadcastComment({ role, localCountThisSecond: local, globalAllow });
  if (send) await broadcast(streamId, 'chat', { v: 1, type: 'comment', ...comment });
  return { id: comment.id, ts: comment.ts, text: comment.text, broadcast: send };
});

// ─── lsDeleteComment ────────────────────────────────────────────────────────

export const lsDeleteComment = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireStreamId(data);
  const commentId = requireString(data.commentId, 'commentId', 200);
  if (commentId.includes('/')) throw new HttpsError('invalid-argument', 'Invalid commentId.');

  const state = await loadState(streamId);
  const role = await requireRole(streamId, uid, ['host', 'coHost', 'guest', 'viewer'], state);
  const ref = db().doc(`${Paths.comments(streamId)}/${commentId}`);
  const snap = await ref.get();
  if (!snap.exists) return { deleted: false };
  const author = (snap.get('uid') as string | undefined) ?? '';
  if (!canDeleteComment(role, uid, author)) throw new HttpsError('permission-denied', 'You cannot delete this comment.');
  await ref.delete();
  await broadcast(streamId, 'chat', { v: 1, type: 'comment.deleted', id: commentId, ts: Date.now() });
  return { deleted: true };
});

// ─── lsMuteChat ─────────────────────────────────────────────────────────────

export const lsMuteChat = onCall(async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireStreamId(data);
  const target = requireString(data.uid, 'uid', 128);
  const minutes = parseMuteMinutes(data.minutes);
  if (minutes === null) throw new HttpsError('invalid-argument', 'minutes must be 0–1440 (0 unmutes).');

  const state = await loadState(streamId);
  const actorRole = await requireRole(streamId, uid, ['host', 'coHost'], state);
  const targetRole = await roleOf(streamId, target, state);
  if (!canMuteChat(actorRole, uid, targetRole, target)) throw new HttpsError('permission-denied', 'You cannot mute this user.');

  const ref = muteRef(streamId, target);
  if (minutes === 0) {
    await ref.delete();
    return { until: 0 };
  }
  const until = muteUntil(Date.now(), minutes);
  await ref.set({ until, by: uid, at: FieldValue.serverTimestamp() });
  return { until };
});

// ─── lsReact ────────────────────────────────────────────────────────────────

async function flushReactions(streamId: string, leaseAt: number, state: StudioState): Promise<void> {
  await sleep(flushDelayMs(leaseAt, Date.now()));
  const totals = await shardTotals(streamId);
  const aggRef = counterDoc(streamId, 'agg');
  const deltas = await db().runTransaction(async (tx) => {
    const snap = await tx.get(aggRef);
    const flushed = snap.get('flushed') as { loves?: number; sparkles?: number } | undefined;
    const d = reactionDeltas(totals, flushed);
    // Monotonic: never move `flushed` backwards if a slower leader commits late.
    tx.set(
      aggRef,
      { flushed: { loves: Math.max(totals.loves, flushed?.loves ?? 0), sparkles: Math.max(totals.sparkles, flushed?.sparkles ?? 0) } },
      { merge: true },
    );
    return d;
  });
  if (deltas.loves === 0 && deltas.sparkles === 0) return;
  const counts: StudioCounts = {
    ...(state.counts ?? { viewers: 0, participants: 0, loves: 0, sparkles: 0, shares: 0 }),
    loves: totals.loves,
    sparkles: totals.sparkles,
    shares: totals.shares,
  };
  await broadcast(
    streamId,
    'react',
    { v: 1, type: 'reaction.agg', loves: deltas.loves, sparkles: deltas.sparkles, totals: counts, ts: Date.now() },
    { lossy: true },
  );
  await maybePatchCountsState(streamId, 'stateReactAt', (cur) => ({
    ...cur,
    loves: totals.loves,
    sparkles: totals.sparkles,
    shares: totals.shares,
  }));
}

export const lsReact = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireStreamId(data);
  const r = parseReaction(data.kind, data.n);
  if (!r.ok) throw new HttpsError('invalid-argument', r.reason);

  const [stateSnap, blockSnap] = await db().getAll(db().doc(Paths.state(streamId)), db().doc(`${Paths.blocks(streamId)}/${uid}`));
  if (!stateSnap.exists) throw new HttpsError('not-found', 'This live does not exist.');
  const state = stateSnap.data() as StudioState;
  if (state.status !== 'live') throw new HttpsError('failed-precondition', 'This live is not on air.');
  if (blockSnap.exists) throw new HttpsError('permission-denied', 'You are blocked from this live.');
  await rateLimit(streamId, uid, 'react', Limits.reactionCallsPerSecond, 1000);

  const field = reactionField(r.kind);
  await shardRefs(streamId)[pickShard(Math.random())].set({ [field]: FieldValue.increment(r.n) }, { merge: true });

  // System line, at most one per user per 10 s.
  const lineLease = await claimLease(db().doc(`${Paths.rate(streamId)}/${uid}_reactline`), 'at', SYSTEM_LINE_USER_INTERVAL_MS);
  if (lineLease !== null) {
    const p = await profileOf(uid);
    await sendSystemLine(streamId, systemKindForReaction(r.kind as ReactionKind), { uid, ...p });
  }

  // Aggregated broadcast: only the window's lease holder flushes.
  const leaseAt = await claimLease(counterDoc(streamId, 'agg'), 'leaseAt', Limits.reactionAggregateWindowMs);
  if (leaseAt !== null) await flushReactions(streamId, leaseAt, state);
  return { ok: true, flushed: leaseAt !== null };
});

// ─── lsShare ────────────────────────────────────────────────────────────────

export const lsShare = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireStreamId(data);
  const state = await loadState(streamId);
  await requireRole(streamId, uid, ['host', 'coHost', 'guest', 'viewer'], state);
  const url = shareUrl(streamId);
  if (state.status !== 'live') return { url };

  // Count and announce at most once per user per 10 s; the link is always returned.
  const lease = await claimLease(db().doc(`${Paths.rate(streamId)}/${uid}_shareline`), 'at', SYSTEM_LINE_USER_INTERVAL_MS);
  if (lease === null) return { url };
  await shardRefs(streamId)[pickShard(Math.random())].set({ shares: FieldValue.increment(1) }, { merge: true });
  const p = await profileOf(uid);
  await sendSystemLine(streamId, 'shared', { uid, ...p });
  await maybePatchCountsState(streamId, 'stateShareAt', async (cur) => ({ ...cur, shares: (await shardTotals(streamId)).shares }));
  return { url };
});

// ─── lsLivekitWebhook ───────────────────────────────────────────────────────

async function participantsOf(streamId: string, state: StudioState): Promise<number> {
  const [coHosts, pending] = await Promise.all([
    db().collection(Paths.members(streamId)).where('role', '==', 'coHost').select().get(),
    db().collection(Paths.requests(streamId)).where('status', '==', 'pending').count().get(),
  ]);
  return computeParticipants(
    stagePublishers(state.stage),
    coHosts.docs.map((d) => d.id),
    pending.data().count,
  );
}

async function handlePresence(
  streamId: string,
  joined: boolean,
  participant: { identity: string; name: string },
  roomNum: number | undefined,
): Promise<void> {
  await shardRefs(streamId)[pickShard(Math.random())].set({ viewers: FieldValue.increment(joined ? 1 : -1) }, { merge: true });
  const presence = counterDoc(streamId, 'presence');

  let viewers: number | undefined;
  const viewersNow = async () => (viewers ??= resolveViewers(roomNum, (await shardTotals(streamId)).viewers));

  if (joined && participant.identity) {
    const n = typeof roomNum === 'number' && roomNum > 0 ? roomNum : await viewersNow();
    const emit = joinLineMode(n) === 'always' || (await claimLease(presence, 'joinLineAt', JOIN_LINE_INTERVAL_MS)) !== null;
    if (emit) {
      const p = await profileOf(participant.identity);
      await sendSystemLine(streamId, 'joined', {
        uid: participant.identity,
        name: participant.name?.trim() || p.name,
        avatarUrl: p.avatarUrl,
      });
    }
  }

  const countsLease = await claimLease(presence, 'countsAt', Limits.countsIntervalMs);
  if (countsLease === null) return;
  const state = await loadState(streamId);
  const next = { viewers: await viewersNow(), participants: await participantsOf(streamId, state) };
  const prev = (await presence.get()).get('last') as { viewers?: number; participants?: number } | undefined;
  if (countsChanged(prev, next)) {
    await presence.set({ last: next }, { merge: true });
    await broadcast(streamId, 'counts', { v: 1, type: 'counts', ...next, ts: Date.now() }, { lossy: true });
  }
  await maybePatchCountsState(streamId, 'statePresenceAt', (cur) => ({ ...cur, ...next }));
}

export const lsLivekitWebhook = onRequest({ secrets: LIVEKIT_SECRETS }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method not allowed');
    return;
  }
  const receiver = new WebhookReceiver(LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
  let event;
  try {
    const body = req.rawBody ? req.rawBody.toString('utf8') : JSON.stringify(req.body ?? {});
    event = await receiver.receive(body, req.get('Authorization') ?? req.get('Authorize'));
  } catch (e) {
    console.warn('[liveStudio] webhook rejected:', (e as Error).message);
    res.status(401).send('Invalid signature');
    return;
  }

  try {
    const streamId = streamIdFromRoom(event.room?.name);
    const p = event.participant;
    // Only standard clients count as viewers (kind 0); skip egress/ingress/agents.
    if (event.event === 'egress_ended' && event.egressInfo) {
      await onEgressEnded(event.egressInfo);
    }
    if (streamId && event.event === 'room_finished') {
      // The room closed (empty timeout / deleted): the live is over.
      await endStudioStream(streamId, 'room_closed');
    }
    if (streamId && p && (p.kind ?? 0) === 0 && (event.event === 'participant_joined' || event.event === 'participant_left')) {
      await onHostPresence(streamId, p.identity, event.event === 'participant_joined');
      await handlePresence(
        streamId,
        event.event === 'participant_joined',
        { identity: p.identity, name: p.name },
        event.room?.numParticipants,
      );
    }
  } catch (e) {
    // Never make LiveKit retry storms: log and acknowledge.
    console.error('[liveStudio] webhook handling failed:', (e as Error).message);
  }
  res.status(200).send('ok');
});

// ─── lsGifSearch ────────────────────────────────────────────────────────────

/**
 * GIF search for comments (GIPHY). `{q?}` → `{gifs: [{id, url, w, h}], enabled}`.
 * Trending when q is empty. The GIPHY key is optional (GIPHY_API_KEY in
 * Secret Manager, read at run time): without it `enabled` is false.
 */
export const lsGifSearch = onCall(async (req) => {
  requireUid(req);
  const q = sanitizeGifQuery(asData(req.data).q);
  const key = await optionalSecret('GIPHY_API_KEY');
  if (!key) return { gifs: [], enabled: false };
  const params = new URLSearchParams({ api_key: key, limit: '24', rating: 'pg-13', bundle: 'messaging_non_clips' });
  if (q) params.set('q', q);
  const url = `https://api.giphy.com/v1/gifs/${q ? 'search' : 'trending'}?${params.toString()}`;
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`GIPHY ${res.status}`);
    const body = (await res.json()) as { data?: unknown[] };
    const gifs = (body.data ?? []).map(fromGiphy).filter((g) => g !== null);
    return { gifs, enabled: true };
  } catch (e) {
    console.warn('[liveStudio] gif search failed:', (e as Error).message);
    throw new HttpsError('unavailable', 'GIF search is not available right now.');
  }
});
