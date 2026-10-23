/**
 * LIVE STUDIO v2 — server helpers shared by every liveStudio/* module
 * (integrator-owned). Auth, role lookup, state transactions and LiveKit
 * fan-out live here so the authorization rules are written once.
 */
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import { getFirestore, FieldValue, Transaction, DocumentReference } from 'firebase-admin/firestore';
import { RoomServiceClient, DataPacket_Kind } from 'livekit-server-sdk';
import { Paths, StudioRole, StudioState, StageMember, StudioEvent } from './contracts';

export const LIVEKIT_API_KEY = defineSecret('LIVEKIT_API_KEY');
export const LIVEKIT_API_SECRET = defineSecret('LIVEKIT_API_SECRET');
export const LIVEKIT_URL = defineString('LIVEKIT_URL', { default: 'wss://unset.livekit.cloud' });

/** Secrets every callable that talks to LiveKit must declare. */
export const LIVEKIT_SECRETS = [LIVEKIT_API_KEY, LIVEKIT_API_SECRET];

export const db = () => getFirestore();

/**
 * Security hook: refused / rate-limited calls are reported to the attack
 * detectors (security.ts registers itself on load; avoids an import cycle).
 * Never throws and never masks the original error.
 */
type StudioDenialHook = (streamId: string, uid: string, err: unknown, bucket?: string) => void;
let denialHook: StudioDenialHook | null = null;
export function setStudioDenialHook(fn: StudioDenialHook) {
  denialHook = fn;
}
function reportDenial(streamId: string, uid: string, err: unknown, bucket?: string) {
  try {
    denialHook?.(streamId, uid, err, bucket);
  } catch {
    /* never mask the real error */
  }
}

/** LiveKit room name for a stream (1:1). */
export const roomName = (streamId: string) => `studio_${streamId}`;

export function roomService(): RoomServiceClient {
  const url = LIVEKIT_URL.value().replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
  return new RoomServiceClient(url, LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
}

export function requireUid(req: CallableRequest<unknown>): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

export function requireString(v: unknown, name: string, max = 200): string {
  if (typeof v !== 'string' || v.trim().length === 0 || v.length > max) {
    throw new HttpsError('invalid-argument', `${name} is required (≤ ${max} chars).`);
  }
  return v.trim();
}

export async function loadState(streamId: string, tx?: Transaction): Promise<StudioState> {
  const ref = db().doc(Paths.state(streamId));
  const snap = tx ? await tx.get(ref) : await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'This live does not exist.');
  return snap.data() as StudioState;
}

export async function isBlocked(streamId: string, uid: string): Promise<boolean> {
  return (await db().doc(`${Paths.blocks(streamId)}/${uid}`).get()).exists;
}

/** Role of [uid] in [streamId]: host from state, others from members/. */
export async function roleOf(streamId: string, uid: string, state?: StudioState): Promise<StudioRole> {
  const s = state ?? (await loadState(streamId));
  if (s.hostId === uid) return 'host';
  const m = await db().doc(`${Paths.members(streamId)}/${uid}`).get();
  return m.exists ? ((m.data() as StageMember).role ?? 'viewer') : 'viewer';
}

/** Throws unless [uid] has one of [allowed] roles and is not blocked. */
export async function requireRole(
  streamId: string,
  uid: string,
  allowed: StudioRole[],
  state?: StudioState,
): Promise<StudioRole> {
  if (await isBlocked(streamId, uid)) {
    const err = new HttpsError('permission-denied', 'You are blocked from this live.');
    reportDenial(streamId, uid, err, 'role');
    throw err;
  }
  const r = await roleOf(streamId, uid, state);
  if (!allowed.includes(r)) {
    const err = new HttpsError('permission-denied', `Requires role: ${allowed.join(' or ')}.`);
    reportDenial(streamId, uid, err, 'role');
    throw err;
  }
  return r;
}

export function requireLive(s: StudioState) {
  if (s.status === 'ended') throw new HttpsError('failed-precondition', 'This live has ended.');
}

/**
 * Atomically mutates one top-level section of studio/state, bumps `seq`,
 * then broadcasts a `state.patch`. [mutate] returns the new section value,
 * or `undefined` for "no change" (nothing is written or sent).
 */
export async function patchState<K extends keyof StudioState>(
  streamId: string,
  path: K,
  mutate: (s: StudioState, tx: Transaction) => Promise<StudioState[K] | undefined> | StudioState[K] | undefined,
): Promise<StudioState | null> {
  const ref = db().doc(Paths.state(streamId));
  const result = await db().runTransaction(async (tx) => {
    const s = await loadState(streamId, tx);
    const value = await mutate(s, tx);
    if (value === undefined) return null;
    const seq = (s.seq ?? 0) + 1;
    tx.update(ref, { [path]: value, seq, updatedAt: FieldValue.serverTimestamp() });
    return { ...s, [path]: value, seq } as StudioState;
  });
  if (result) {
    await broadcast(streamId, 'studio.state', {
      v: 1, type: 'state.patch', seq: result.seq, path, value: result[path], ts: Date.now(),
    });
  }
  return result;
}

/**
 * Sends a data message to everyone in the room (or [to] identities only).
 * Failures are logged, never thrown: Firestore stays the source of record and
 * clients resync with `lsStateFull` when they see a `seq` gap.
 */
export async function broadcast(
  streamId: string,
  topic: string,
  event: StudioEvent,
  opts: { to?: string[]; lossy?: boolean } = {},
): Promise<void> {
  try {
    const data = new TextEncoder().encode(JSON.stringify(event));
    await roomService().sendData(
      roomName(streamId),
      data,
      opts.lossy ? DataPacket_Kind.LOSSY : DataPacket_Kind.RELIABLE,
      { topic, destinationIdentities: opts.to },
    );
  } catch (e) {
    console.warn(`[liveStudio] broadcast ${topic} failed for ${streamId}:`, (e as Error).message);
  }
}

/**
 * Fixed-window rate limiter stored in Firestore
 * (`studio_rate/{uid}_{bucket}`). Throws `resource-exhausted` when exceeded.
 */
export async function rateLimit(streamId: string, uid: string, bucket: string, max: number, windowMs: number) {
  const ref = db().doc(`${Paths.rate(streamId)}/${uid}_${bucket}`);
  try {
    await rateLimitTx(ref, max, windowMs);
  } catch (e) {
    reportDenial(streamId, uid, e, bucket);
    throw e;
  }
}

async function rateLimitTx(ref: DocumentReference, max: number, windowMs: number) {
  await db().runTransaction(async (tx) => {
    const now = Date.now();
    const snap = await tx.get(ref);
    const d = snap.exists ? (snap.data() as { start: number; count: number }) : { start: now, count: 0 };
    const fresh = now - d.start >= windowMs;
    const next = fresh ? { start: now, count: 1 } : { start: d.start, count: d.count + 1 };
    if (!fresh && next.count > max) throw new HttpsError('resource-exhausted', 'Slow down a little.');
    tx.set(ref, next);
  });
}
