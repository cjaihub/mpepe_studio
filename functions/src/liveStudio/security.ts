/**
 * LIVE STUDIO v2 — security (security workstream).
 *
 *  - `recordStudioSignal()` / `noteStudioDenial()`: attack detection. Other
 *    modules report signals; detectors in security_logic.ts turn them into
 *    incidents at `live_streams/{id}/studio_security/{incidentId}`
 *    (function-only writes). Critical per-account incidents are forwarded to
 *    the existing Ova Guard (`recordSecurityEvent` in ../security.ts).
 *  - `lsSecOnIncident`: AI live-health monitor. On a new warn/critical
 *    incident, at most once per 60 s per stream, it asks Gemini (same
 *    Vertex AI client as the AI gateway / guardExplainEvent)
 *    for a short assessment and 1–3 actions from a FIXED allow-list, validates
 *    the answer strictly and falls back to rules. The advisory goes to the
 *    host and co-hosts only (topic `security`) and is persisted.
 *  - Media E2EE keys: `mediaKeyForToken()` (used by lsStart / lsToken),
 *    `lsMediaKey` (refetch after rotation), and rotation triggers on blocks
 *    and stage removals. See the WHAT E2EE PROTECTS note in security_logic.ts.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { defineString } from 'firebase-functions/params';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue } from 'firebase-admin/firestore';
import { vertexAi } from '../vertexAi';
import { Paths, StageMember, StudioEvent, StudioState } from './contracts';
import * as shared from './shared';
import { LIVEKIT_SECRETS, broadcast, db, isBlocked, loadState, rateLimit, requireString, requireUid } from './shared';
import {
  DETECTORS,
  DetectorSpec,
  HealthMetrics,
  Hit,
  MONITOR_LOOKBACK_MS,
  MONITOR_SYSTEM_PROMPT,
  MediaKeyDoc,
  NEW_ACCOUNT_MS,
  SECURITY_TOPIC,
  STREAM_SHARDS,
  SignalDetail,
  SignalKind,
  StudioAdvisory,
  StudioIncident,
  buildAdvisory,
  buildHealthSummary,
  buildIncident,
  bucketStart,
  bucketsFor,
  countLog,
  detectorsFor,
  e2eeEnabled,
  fallbackAdvice,
  guardMapping,
  isValidKeyDoc,
  keyPayload,
  keyUpdateEvent,
  memberChangeNeedsRotation,
  monitorShouldRun,
  newMediaKey,
  rotateMediaKey,
  signalForFailure,
  slideLog,
  streamCounterId,
  sumBuckets,
  validateModelOutput,
} from './security_logic';

/** Server switch for media E2EE (default on). `LIVE_STUDIO_E2EE=false` turns it off. */
export const LIVE_STUDIO_E2EE = defineString('LIVE_STUDIO_E2EE', { default: 'true' });

/**
 * The AI part of the live-health monitor is opt-in per deployment: set
 * LIVE_STUDIO_AI_MONITOR=true in functions/.env.<project> (Gemini runs on
 * Vertex AI as the function's service account, so no key is needed).
 * Without it the monitor still runs with the rule-based advice
 * (fallbackAdvice), using the same action allow-list.
 */
const AI_MONITOR = process.env.LIVE_STUDIO_AI_MONITOR === 'true';
const MONITOR_SECRETS = [...LIVEKIT_SECRETS];

/**
 * The Ova Guard module (../security.ts) defines its own secrets at load time,
 * so it is loaded lazily, only when a critical incident is forwarded.
 */
async function forwardToGuard(uid: string, type: string, details: unknown): Promise<void> {
  const guard = await import('../security');
  await (guard.recordSecurityEvent as (u: string, t: never, o: { details: unknown }) => Promise<unknown>)(uid, type as never, { details });
}

export const SecPaths = {
  incidents: (id: string) => `live_streams/${id}/studio_security`,
  advisories: (id: string) => `live_streams/${id}/studio_security_advisories`,
  counters: (id: string) => `live_streams/${id}/studio_security_counters`,
  mediaKey: (id: string) => `live_streams/${id}/studio_secrets/media_key`,
  account: (uid: string) => `studio_security_uid/${uid}`,
} as const;

const warn = (what: string, e: unknown) => console.warn(`[liveStudio.security] ${what}:`, (e as Error)?.message ?? e);

// ─── Attack detection ──────────────────────────────────────────────────────

/** Per-instance throttle for stream-wide evaluations (reads are the cost). */
const lastStreamEval = new Map<string, number>();
const STREAM_EVAL_EVERY_MS = 2_000;

/**
 * Reports one security-relevant signal. Never throws and never blocks the
 * caller's decision: detection is best effort, enforcement stays with the
 * callables. Safe to call from any ls* callable.
 */
export async function recordStudioSignal(
  streamId: string,
  uid: string,
  kind: SignalKind,
  detail: SignalDetail = {},
): Promise<void> {
  if (!streamId || !uid) return;
  const now = Date.now();
  await Promise.all(
    detectorsFor(kind, detail).map((spec) =>
      evaluate(spec, streamId, uid, detail, now).catch((e) => warn(`detector ${spec.id}`, e)),
    ),
  );
}

/**
 * Hook for shared.ts: call when `rateLimit` / `requireRole` throws.
 * `bucket` is the rate-limit bucket (or a short callable tag).
 */
export function noteStudioDenial(streamId: string, uid: string, err: unknown, bucket?: string): void {
  const code = err instanceof HttpsError ? err.code : (err as { code?: string } | null)?.code;
  const s = typeof code === 'string' ? signalForFailure(code, bucket) : null;
  if (s) void recordStudioSignal(streamId, uid, s.kind, s.detail);
}

/**
 * Wraps a callable step: on failure, reports it, then rethrows unchanged.
 * Usable by any module without touching shared.ts.
 */
export async function withStudioSecurity<T>(streamId: string, uid: string, bucket: string, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    noteStudioDenial(streamId, uid, e, bucket);
    throw e;
  }
}

// Register with shared.ts once the integrator adds `setStudioDenialHook`
// (requested). Avoids an import cycle: shared.ts never imports this file.
const hookSetter = (shared as unknown as { setStudioDenialHook?: (fn: typeof noteStudioDenial) => void }).setStudioDenialHook;
if (typeof hookSetter === 'function') hookSetter(noteStudioDenial);

async function evaluate(spec: DetectorSpec, streamId: string, uid: string, detail: SignalDetail, now: number) {
  let count: number;
  if (spec.scope === 'stream') {
    const c = await bumpStream(spec, streamId, now);
    if (c === null) return;
    count = c;
  } else {
    const ref =
      spec.scope === 'account'
        ? db().doc(SecPaths.account(uid))
        : db().doc(`${SecPaths.counters(streamId)}/${spec.id}_${uid}`);
    const field = spec.scope === 'account' ? spec.id : 'log';
    const value = spec.distinct === 'streamId' ? streamId : spec.distinct === 'fingerprint' ? detail.fingerprint : undefined;
    const cap = Math.min(200, spec.distinct ? spec.criticalAt * 8 : spec.criticalAt + 1);
    count = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const hit: Hit = value !== undefined ? { t: now, v: value } : { t: now };
      const log = slideLog(snap.exists ? (snap.get(field) as Hit[] | undefined) : undefined, hit, spec.windowMs, cap);
      tx.set(ref, { [field]: log, updatedAtMs: now }, { merge: true });
      return countLog(log, !!spec.distinct);
    });
  }
  const incident = buildIncident({ spec, streamId, uid, count, now });
  if (incident) await persistIncident(incident);
}

/** Increments a sharded bucket; returns the window sum when due for evaluation. */
async function bumpStream(spec: DetectorSpec, streamId: string, now: number): Promise<number | null> {
  const bucket = bucketStart(now);
  const shard = Math.floor(Math.random() * STREAM_SHARDS);
  await db()
    .doc(`${SecPaths.counters(streamId)}/${streamCounterId(spec.id, bucket, shard)}`)
    .set({ detector: spec.id, bucket, count: FieldValue.increment(1) }, { merge: true });
  const key = `${streamId}:${spec.id}`;
  if (now - (lastStreamEval.get(key) ?? 0) < STREAM_EVAL_EVERY_MS) return null;
  lastStreamEval.set(key, now);
  if (lastStreamEval.size > 5000) lastStreamEval.clear();
  const refs = bucketsFor(now, spec.windowMs).flatMap((b) =>
    Array.from({ length: STREAM_SHARDS }, (_, s) => db().doc(`${SecPaths.counters(streamId)}/${streamCounterId(spec.id, b, s)}`)),
  );
  const snaps = await db().getAll(...refs);
  return sumBuckets(
    snaps.filter((s) => s.exists).map((s) => ({ bucket: Number(s.get('bucket')), count: Number(s.get('count')) })),
    now,
    spec.windowMs,
  );
}

/** `create()` dedupes concurrent instances: the id embeds the cooldown slot. */
async function persistIncident(i: StudioIncident): Promise<void> {
  try {
    await db().doc(`${SecPaths.incidents(i.streamId)}/${i.id}`).create({ ...i, at: FieldValue.serverTimestamp() });
  } catch (e) {
    if ((e as { code?: number }).code === 6) return; // ALREADY_EXISTS: same alert in this slot
    throw e;
  }
  const g = guardMapping(i);
  if (g && i.uid) {
    try {
      await forwardToGuard(i.uid, g.type, g.details);
    } catch (e) {
      warn('guard forward', e);
    }
  }
}

/**
 * lsToken signal: account age (raid detection) and a session fingerprint
 * (duplicate-identity joins). The fingerprint is a hash of the ID token's
 * `auth_time` (one value per sign-in session/device); no raw data is stored.
 */
export async function recordTokenSignal(streamId: string, uid: string, req: CallableRequest<unknown>): Promise<void> {
  try {
    let newAccount = false;
    try {
      const created = Date.parse((await getAuth().getUser(uid)).metadata.creationTime);
      newAccount = Number.isFinite(created) && Date.now() - created < NEW_ACCOUNT_MS;
    } catch (e) {
      warn('account age', e);
    }
    const authTime = String((req.auth?.token as { auth_time?: unknown } | undefined)?.auth_time ?? '');
    const fingerprint = authTime ? crypto.createHash('sha256').update(`${uid}|${authTime}`).digest('hex').slice(0, 16) : undefined;
    await recordStudioSignal(streamId, uid, 'token', { newAccount, fingerprint });
  } catch (e) {
    warn('token signal', e);
  }
}

// ─── AI live-health monitor ────────────────────────────────────────────────

/** Members whose role is coHost (host comes from state). */
async function managerUids(streamId: string, state: StudioState): Promise<string[]> {
  const q = await db().collection(Paths.members(streamId)).where('role', '==', 'coHost').get();
  return [...new Set([state.hostId, ...q.docs.map((d) => d.id)])].filter(Boolean);
}

/** Throttle: one run per stream per MONITOR_MIN_INTERVAL_MS, across instances. */
async function claimMonitorRun(streamId: string, now: number): Promise<boolean> {
  const ref = db().doc(`${SecPaths.counters(streamId)}/_monitor`);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!monitorShouldRun(snap.exists ? Number(snap.get('lastRunAtMs')) : undefined, now)) return false;
    tx.set(ref, { lastRunAtMs: now }, { merge: true });
    return true;
  });
}

async function askModel(summary: unknown): Promise<string | null> {
  if (!AI_MONITOR) return null;
  const ai = vertexAi();
  const call = ai.models.generateContent({
    model: 'gemini-2.5-flash',
    contents: [{ role: 'user', parts: [{ text: JSON.stringify(summary) }] }],
    config: {
      systemInstruction: MONITOR_SYSTEM_PROMPT,
      responseMimeType: 'application/json',
      maxOutputTokens: 300,
      temperature: 0.1,
    },
  });
  const timeout = new Promise<null>((r) => setTimeout(() => r(null), 8_000));
  const res = await Promise.race([call, timeout]);
  return res ? String(res.text ?? '') : null;
}

/** Runs the monitor for one stream now (exported for an admin/manual trigger). */
export async function runLiveHealthMonitor(streamId: string, now = Date.now()): Promise<StudioAdvisory | null> {
  const state = await loadState(streamId);
  if (state.status === 'ended') return null;
  const incSnap = await db()
    .collection(SecPaths.incidents(streamId))
    .where('atMs', '>=', now - MONITOR_LOOKBACK_MS)
    .orderBy('atMs', 'desc')
    .limit(20)
    .get();
  const incidents = incSnap.docs.map((d) => d.data() as StudioIncident);
  if (!incidents.some((i) => i.severity !== 'info')) return null;

  // People in incidents: role + on-stage (for validation) and a display name
  // (host UI only; never sent to the model).
  const uids = [...new Set(incidents.map((i) => i.uid).filter((u): u is string => !!u))].slice(0, 20);
  const st = state.stage;
  const onStage = (u: string) => st.centerUid === u || st.wall.includes(u) || st.overflow.includes(u);
  const memberSnaps = uids.length ? await db().getAll(...uids.map((u) => db().doc(`${Paths.members(streamId)}/${u}`))) : [];
  const people: Record<string, { onStage: boolean; role: string; name: string }> = {};
  for (const s of memberSnaps) {
    const m = s.exists ? (s.data() as Partial<StageMember>) : {};
    people[s.id] = { onStage: onStage(s.id), role: state.hostId === s.id ? 'host' : (m.role ?? 'viewer'), name: m.displayName ?? '' };
  }

  // Chat rate + short samples from flagged accounts (one single-field query).
  const recent = await db()
    .collection(Paths.comments(streamId))
    .where('ts', '>=', now - 60_000)
    .orderBy('ts', 'desc')
    .limit(200)
    .get();
  const flagged = new Set(uids);
  const samples: Record<string, string[]> = {};
  for (const d of recent.docs) {
    const u = String(d.get('uid') ?? '');
    if (!flagged.has(u) || d.get('kind')) continue;
    const list = (samples[u] ??= []);
    if (list.length < 2) list.push(String(d.get('text') ?? ''));
  }
  const metrics: HealthMetrics = {
    viewers: state.counts?.viewers ?? 0,
    participants: state.counts?.participants ?? 0,
    chatPerMin: recent.size,
    qos: null, // QoS samples go to telemetry, not Firestore; not available server-side yet.
  };

  // PRIVACY: the summary has aliases instead of uids, no names, and at most
  // 3 sanitized samples of ≤ 60 chars (see buildHealthSummary).
  const { summary, aliases } = buildHealthSummary({ incidents, metrics, now, people, samples });

  let source: 'ai' | 'rules' = 'rules';
  let advice = null as { assessment: string; actions: StudioAdvisory['actions'] } | null;
  try {
    const raw = await askModel(summary);
    advice = raw ? validateModelOutput(raw, { summary, aliases }) : null;
    if (advice) source = 'ai';
  } catch (e) {
    warn('model', e);
  }
  advice ??= fallbackAdvice(incidents, people);

  const advisory = buildAdvisory({ streamId, now, incidents, source, ...advice });
  const withNames = {
    ...advisory,
    actions: advisory.actions.map((a) => (a.targetUid ? { ...a, targetName: people[a.targetUid]?.name ?? '' } : a)),
  };
  await db().doc(`${SecPaths.advisories(streamId)}/${advisory.id}`).set({ ...withNames, at: FieldValue.serverTimestamp() });
  const to = await managerUids(streamId, state);
  await broadcast(streamId, SECURITY_TOPIC, { v: 1, type: 'security.advisory', advisory: withNames, ts: now } as unknown as StudioEvent, { to });
  return withNames;
}

/** New incident → maybe a live-health advisory (warn/critical, ≤ 1/min/stream). */
export const lsSecOnIncident = onDocumentCreated(
  { document: 'live_streams/{streamId}/studio_security/{incidentId}', secrets: MONITOR_SECRETS },
  async (event) => {
    const severity = event.data?.get('severity');
    if (severity !== 'warn' && severity !== 'critical') return;
    const streamId = event.params.streamId;
    const now = Date.now();
    try {
      if (!(await claimMonitorRun(streamId, now))) return;
      await runLiveHealthMonitor(streamId, now);
    } catch (e) {
      warn(`monitor ${streamId}`, e);
    }
  },
);

// ─── Media E2EE keys ───────────────────────────────────────────────────────

const random = (n: number) => new Uint8Array(crypto.randomBytes(n));

export function studioE2eeEnabled(): boolean {
  try {
    return e2eeEnabled(LIVE_STUDIO_E2EE.value());
  } catch {
    return true;
  }
}

/**
 * The stream's shared media key, created on first use. Returns null when
 * E2EE is off. The key doc is function-only (no client rules access).
 */
export async function mediaKeyForToken(streamId: string): Promise<{ key: string; keyIndex: number } | null> {
  if (!studioE2eeEnabled()) return null;
  const ref = db().doc(SecPaths.mediaKey(streamId));
  const doc = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = snap.exists ? snap.data() : undefined;
    if (isValidKeyDoc(cur)) return cur;
    const fresh = newMediaKey(random, Date.now());
    tx.set(ref, fresh);
    return fresh;
  });
  return keyPayload(doc);
}

/**
 * Rotates the key (new random 32 bytes, next ring index) and tells the room
 * on topic `security`. The data message carries ONLY the index: it travels
 * through the SFU, so clients fetch the key itself over HTTPS (lsMediaKey).
 */
export async function rotateStudioMediaKey(streamId: string, reason: string): Promise<MediaKeyDoc | null> {
  if (!studioE2eeEnabled()) return null;
  const ref = db().doc(SecPaths.mediaKey(streamId));
  const next = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null; // no E2EE live yet (or a v1 stream): nothing to rotate
    const cur = snap.data();
    const n = rotateMediaKey(isValidKeyDoc(cur) ? cur : null, random, Date.now(), reason);
    tx.set(ref, n);
    return n;
  });
  if (next) await broadcast(streamId, SECURITY_TOPIC, keyUpdateEvent(next.keyIndex, Date.now()) as unknown as StudioEvent);
  return next;
}

/** Someone was blocked → rotate (they keep no usable key). */
export const lsSecOnBlock = onDocumentCreated(
  { document: 'live_streams/{streamId}/studio_blocks/{uid}', secrets: LIVEKIT_SECRETS },
  async (event) => {
    try {
      await rotateStudioMediaKey(event.params.streamId, 'blocked');
    } catch (e) {
      warn('rotate on block', e);
    }
  },
);

/** A publisher left / was removed from the stage → rotate. */
export const lsSecOnMemberWrite = onDocumentWritten(
  { document: 'live_streams/{streamId}/members/{uid}', secrets: LIVEKIT_SECRETS },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!memberChangeNeedsRotation(before, after)) return;
    try {
      await rotateStudioMediaKey(event.params.streamId, 'stage_removed');
    } catch (e) {
      warn('rotate on stage removal', e);
    }
  },
);

/** Current media key for an allowed client (after a `key.update`). Returns `{enabled, key?, keyIndex?}`. */
export const lsMediaKey = onCall(async (req) => {
  const uid = requireUid(req);
  const streamId = requireString((req.data as { streamId?: unknown } | null)?.streamId, 'streamId', 128);
  if (!studioE2eeEnabled()) return { enabled: false };
  const state = await loadState(streamId);
  if (state.status === 'ended') throw new HttpsError('failed-precondition', 'This live has ended.');
  if (await isBlocked(streamId, uid)) {
    void recordStudioSignal(streamId, uid, 'blocked_token');
    throw new HttpsError('permission-denied', 'You are blocked from this live.');
  }
  await withStudioSecurity(streamId, uid, 'mediakey', () => rateLimit(streamId, uid, 'mediakey', 10, 60_000));
  const k = await mediaKeyForToken(streamId);
  return k ? { enabled: true, ...k } : { enabled: false };
});

/** Exposed for tests / tooling: the detector table. */
export const STUDIO_DETECTORS = DETECTORS;
