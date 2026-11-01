/**
 * LIVE STUDIO v2 — live lifecycle: clean endings, no hanging lives.
 *   lsHeartbeat({streamId})  host app pings every 20 s while live
 *   lsSweepOrphanLives       every minute: closes lives whose host is gone
 * endStudioStream() is shared by lsEnd, the sweeper and the LiveKit webhook
 * (room_finished / host left). Pure rules: lifecycle_logic.ts.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { FieldValue } from 'firebase-admin/firestore';
import { Paths } from './contracts';
import { LIVEKIT_SECRETS, db, patchState, requireString, requireUid, roomName, roomService } from './shared';
import { EndReason, orphanReason, toMs } from './lifecycle_logic';
import { stopStreamEgress } from './broadcast';

/**
 * Closes [streamId] everywhere: studio/state status (broadcast to viewers as a
 * state.patch), the stream doc, and the LiveKit room (which disconnects
 * everyone still inside). Idempotent; never throws for a missing state doc.
 */
export async function endStudioStream(streamId: string, reason: EndReason): Promise<boolean> {
  const ref = db().doc(`${Paths.streams}/${streamId}`);
  const ended = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get('status') === 'ended') return false;
    tx.set(
      ref,
      { status: 'ended', endedAt: FieldValue.serverTimestamp(), endedReason: reason, hostLeftAt: FieldValue.delete() },
      { merge: true },
    );
    return true;
  });
  // Viewers get the `ended` patch while the recording / restream finishes
  // (in parallel); the room is deleted after egress so the MP4 closes cleanly.
  await Promise.all([
    patchState(streamId, 'status', (s) => (s.status === 'ended' ? undefined : 'ended')).catch((e) => {
      // v1 lives have no studio/state doc.
      console.warn(`[liveStudio] end state ${streamId}:`, (e as Error).message);
    }),
    stopStreamEgress(streamId),
  ]);
  try {
    await roomService().deleteRoom(roomName(streamId));
  } catch (e) {
    console.warn(`[liveStudio] deleteRoom ${streamId}:`, (e as Error).message);
  }
  return ended;
}

/** Host keep-alive. Returns `{ok, ended}`; `ended` tells the host app the live was closed. */
export const lsHeartbeat = onCall(async (req) => {
  const uid = requireUid(req);
  const streamId = requireString((req.data as { streamId?: unknown } | null)?.streamId, 'streamId', 128);
  const ref = db().doc(`${Paths.streams}/${streamId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'This live does not exist.');
  if (snap.get('hostId') !== uid) throw new HttpsError('permission-denied', 'Only the host sends heartbeats.');
  if (snap.get('status') === 'ended') return { ok: false, ended: true };
  await ref.set({ hostHeartbeatAt: FieldValue.serverTimestamp(), hostLeftAt: FieldValue.delete() }, { merge: true });
  return { ok: true, ended: false };
});

/** Closes every live whose host stopped heartbeating or left the room. */
export const lsSweepOrphanLives = onSchedule({ schedule: 'every 1 minutes', secrets: LIVEKIT_SECRETS }, async () => {
  const now = Date.now();
  const lives = await db().collection(Paths.streams).where('status', '==', 'live').limit(500).get();
  let closed = 0;
  for (const d of lives.docs) {
    const reason = orphanReason(
      {
        status: d.get('status'),
        createdMs: toMs(d.get('createdAt')) ?? toMs(d.get('startedAt')),
        heartbeatMs: toMs(d.get('hostHeartbeatAt')),
        hostLeftMs: toMs(d.get('hostLeftAt')),
      },
      now,
    );
    if (!reason) continue;
    try {
      if (await endStudioStream(d.id, reason)) closed++;
    } catch (e) {
      console.error(`[liveStudio] sweep ${d.id}:`, (e as Error).message);
    }
  }
  if (closed) console.log(`[liveStudio] swept ${closed} orphaned live(s)`);
});

/** Webhook hook: the host's LiveKit connection joined / left the room. */
export async function onHostPresence(streamId: string, identity: string, joined: boolean): Promise<void> {
  const ref = db().doc(`${Paths.streams}/${streamId}`);
  const snap = await ref.get();
  if (!snap.exists || snap.get('hostId') !== identity || snap.get('status') !== 'live') return;
  await ref.set({ hostLeftAt: joined ? FieldValue.delete() : FieldValue.serverTimestamp() }, { merge: true });
}
