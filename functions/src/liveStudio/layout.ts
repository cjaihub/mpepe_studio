/**
 * LIVE STUDIO v2 — `lsSetLayout(streamId, op, args)` (ARCHITECTURE §5, §8).
 *
 * ops: swap(index) · pin(uid) · unpin · setMode(mode) · rotateIn(uid, index)
 * · autoPromote(uid). Pure transitions live in layout_logic.ts.
 *
 * Writes go through `patchState`, which mutates ONE top-level section per
 * transaction and broadcasts one `state.patch`. `setMode` changes
 * `settings.speakerMode` (section 'settings') and, for hostPinned, may also
 * bring the host back to the center (section 'stage'). Those are two
 * patchState calls: settings first, then stage. Each is atomic on its own and
 * bumps `seq`, so clients apply two ordered patches; the stage transaction
 * re-reads state and re-derives the move, so a concurrent change between the
 * two can never be overwritten with stale data. A combined helper would need
 * an integrator change to shared.ts; this keeps shared.ts untouched.
 *
 * Viewer taps never call this (they open a local pop-out, ARCHITECTURE Q3).
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { Paths, StageMember, StudioRole } from './contracts';
import {
  LIVEKIT_SECRETS,
  db,
  loadState,
  patchState,
  rateLimit,
  requireLive,
  requireRole,
  requireString,
  roomName,
  roomService,
} from './shared';
import {
  LayoutError,
  LayoutOp,
  applyLayoutOp,
  authorizeLayoutOp,
  electLeader,
  parseLayoutOp,
} from './layout_logic';

const toHttps = (e: unknown): never => {
  if (e instanceof LayoutError) throw new HttpsError(e.code, e.message);
  throw e;
};

async function loadRoles(streamId: string): Promise<{ roles: Record<string, StudioRole>; members: StageMember[] }> {
  const snap = await db().collection(Paths.members(streamId)).get();
  const roles: Record<string, StudioRole> = {};
  const members: StageMember[] = [];
  snap.forEach((d) => {
    const m = d.data() as StageMember;
    roles[d.id] = m.role;
    members.push({ ...m, uid: d.id });
  });
  return { roles, members };
}

/** Connected LiveKit identities. On failure, assume the host is present (deny co-host takeover). */
async function connectedIdentities(streamId: string, hostId: string): Promise<Set<string>> {
  try {
    const ps = await roomService().listParticipants(roomName(streamId));
    return new Set(ps.map((p) => p.identity));
  } catch (e) {
    console.warn(`[liveStudio] listParticipants failed for ${streamId}:`, (e as Error).message);
    return new Set([hostId]);
  }
}

export const lsSetLayout = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const data = (req.data ?? {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);

  let op: LayoutOp;
  try {
    op = parseLayoutOp(data);
  } catch (e) {
    return toHttps(e);
  }

  const state = await loadState(streamId);
  requireLive(state);
  const role = await requireRole(streamId, uid, ['host', 'coHost'], state);
  await rateLimit(streamId, uid, 'layout', 10, 1000);

  const { roles, members } = await loadRoles(streamId);
  let leader: string | null = null;
  if (op.op === 'autoPromote') {
    const connected = role === 'host' ? new Set([uid]) : await connectedIdentities(streamId, state.hostId);
    leader = electLeader({ hostId: state.hostId, members, connected, hostAbsentForMs: null });
  }
  try {
    authorizeLayoutOp(op, { uid, role }, leader);
  } catch (e) {
    return toHttps(e);
  }

  const ctxFor = (s: typeof state) => ({
    actorUid: uid,
    nowMs: Date.now(),
    mode: s.settings.speakerMode,
    hostId: s.hostId,
    roles,
  });

  if (op.op === 'setMode') {
    const mode = op.mode;
    await patchState(streamId, 'settings', (s) => {
      try {
        const r = applyLayoutOp(s.stage, op, ctxFor(s));
        return r.mode === undefined ? undefined : { ...s.settings, speakerMode: mode };
      } catch (e) {
        return toHttps(e);
      }
    });
  }

  const next = await patchState(streamId, 'stage', (s) => {
    try {
      // For setMode the settings patch has already landed, so re-derive with
      // the stored mode; only the stage half is applied here.
      return applyLayoutOp(s.stage, op, ctxFor(s)).stage;
    } catch (e) {
      return toHttps(e);
    }
  });

  const finalState = next ?? (await loadState(streamId));
  return { ok: true, seq: finalState.seq, stage: finalState.stage, speakerMode: finalState.settings.speakerMode };
});
