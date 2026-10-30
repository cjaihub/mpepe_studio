/**
 * LIVE STUDIO v2 — host entertainment: `lsFun({streamId, op, ...})`.
 *   host / co-host: pollStart {question, options[2..4], seconds} · pollEnd
 *                   timerStart {label?, seconds} · timerStop
 *                   spotlight {text} | {commentId} · spotlightClear
 *                   celebrate {kind: confetti|hearts|fireworks} · raffle
 *   everyone:       pollVote {option}  (one vote per person, can change it)
 * State: `live_streams/{id}/studio/fun` (clients listen). Pure rules: fun_logic.ts.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { Paths, StageMember } from './contracts';
import { LIVEKIT_SECRETS, broadcast, db, isBlocked, loadState, rateLimit, requireLive, requireRole, requireString, requireUid } from './shared';
import {
  FUN_LIMITS,
  FunError,
  FunState,
  ManagerOp,
  applyVote,
  emptyFun,
  newPoll,
  newTimer,
  parseCelebration,
  parseOp,
  parseSpotlightText,
  pickWinner,
  pollAccepting,
  raffleEntrants,
} from './fun_logic';

const funPath = (streamId: string) => `${Paths.streams}/${streamId}/studio/fun`;
const votePath = (streamId: string, pollId: string, uid: string) =>
  `${Paths.streams}/${streamId}/studio_fun_votes/${pollId}_${uid}`;

function guard<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof FunError) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }
}

async function readFun(streamId: string): Promise<FunState> {
  const snap = await db().doc(funPath(streamId)).get();
  return { ...emptyFun(), ...((snap.data() as Partial<FunState> | undefined) ?? {}) };
}

export const lsFun = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = (req.data && typeof req.data === 'object' ? req.data : {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  const op = guard(() => parseOp(data.op));
  const state = await loadState(streamId);
  requireLive(state);
  const ref = db().doc(funPath(streamId));
  const now = Date.now();

  if (op === 'pollVote') {
    if (await isBlocked(streamId, uid)) throw new HttpsError('permission-denied', 'You are blocked from this live.');
    await rateLimit(streamId, uid, 'fun_vote', 6, 10_000);
    const option = typeof data.option === 'number' ? data.option : -1;
    const counts = await db().runTransaction(async (tx) => {
      const funSnap = await tx.get(ref);
      const fun = { ...emptyFun(), ...((funSnap.data() as Partial<FunState> | undefined) ?? {}) };
      if (!pollAccepting(fun.poll, now)) throw new HttpsError('failed-precondition', 'This poll is closed.');
      const poll = fun.poll;
      const vRef = db().doc(votePath(streamId, poll.id, uid));
      const vSnap = await tx.get(vRef);
      const prev = vSnap.exists ? (vSnap.get('option') as number) : null;
      const next = guard(() => applyVote(poll, prev, option));
      tx.set(ref, { poll: next, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      tx.set(vRef, { uid, pollId: poll.id, option, at: now });
      return next.counts;
    });
    return { ok: true, option, counts };
  }

  await requireRole(streamId, uid, ['host', 'coHost'], state);
  await rateLimit(streamId, uid, 'fun_ctl', 20, 60_000);
  const patch: Partial<FunState> = {};
  switch (op as ManagerOp) {
    case 'pollStart':
      patch.poll = guard(() => newPoll(data, `p${now.toString(36)}`, now));
      break;
    case 'pollEnd': {
      const fun = await readFun(streamId);
      if (fun.poll) patch.poll = { ...fun.poll, open: false, endsAtMs: Math.min(fun.poll.endsAtMs, now) };
      break;
    }
    case 'timerStart':
      patch.timer = guard(() => newTimer(data, now));
      break;
    case 'timerStop':
      patch.timer = null;
      break;
    case 'spotlight': {
      if (typeof data.commentId === 'string' && data.commentId) {
        const c = await db().doc(`${Paths.comments(streamId)}/${data.commentId}`).get();
        if (!c.exists) throw new HttpsError('not-found', 'That comment is gone.');
        patch.spotlight = {
          text: String(c.get('text') ?? '').slice(0, FUN_LIMITS.spotlightMax),
          uid: String(c.get('uid') ?? ''),
          name: String(c.get('name') ?? ''),
          avatarUrl: String(c.get('avatarUrl') ?? ''),
          atMs: now,
        };
      } else {
        const host = await db().doc(`${Paths.members(streamId)}/${uid}`).get();
        const m = host.data() as Partial<StageMember> | undefined;
        patch.spotlight = {
          text: guard(() => parseSpotlightText(data.text)),
          uid,
          name: m?.displayName ?? '',
          avatarUrl: m?.avatarUrl ?? '',
          atMs: now,
        };
      }
      break;
    }
    case 'spotlightClear':
      patch.spotlight = null;
      break;
    case 'celebrate':
      patch.celebrate = { kind: parseCelebration(data.kind), atMs: now };
      break;
    case 'raffle': {
      const recent = await db()
        .collection(Paths.comments(streamId))
        .where('ts', '>=', now - FUN_LIMITS.raffleWindowMs)
        .orderBy('ts', 'desc')
        .limit(500)
        .get();
      const entrants = raffleEntrants(
        recent.docs.map((d) => ({
          uid: String(d.get('uid') ?? ''),
          name: String(d.get('name') ?? ''),
          avatarUrl: String(d.get('avatarUrl') ?? ''),
          ts: Number(d.get('ts') ?? 0),
        })),
        now,
        [state.hostId],
      );
      const w = pickWinner(entrants, Math.random());
      if (!w) throw new HttpsError('failed-precondition', 'Nobody has commented in the last 10 minutes yet.');
      patch.raffle = { winnerUid: w.uid, winnerName: w.name, winnerAvatarUrl: w.avatarUrl, entrants: entrants.length, atMs: now };
      break;
    }
  }
  await ref.set({ ...patch, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  // Instant nudge for celebrations / winners; Firestore stays the source of record.
  await broadcast(streamId, 'studio.fun', { v: 1, type: 'fun', op, ts: now } as never, { lossy: true });
  return { ok: true, op };
});
