/**
 * LIVE STUDIO v2 — pure layout transitions for `lsSetLayout`
 * (ARCHITECTURE §5, §8). No Firestore / LiveKit imports: unit-tested in
 * __tests__/layout_logic.test.ts.
 */
import { Limits, SpeakerMode, StageLayout, StageMember, StudioRole } from './contracts';

export type LayoutOp =
  | { op: 'swap'; index: number }
  | { op: 'pin'; uid: string }
  | { op: 'unpin' }
  | { op: 'setMode'; mode: SpeakerMode }
  | { op: 'rotateIn'; uid: string; index: number }
  | { op: 'autoPromote'; uid: string };

export type LayoutErrorCode = 'invalid-argument' | 'permission-denied' | 'failed-precondition';

export class LayoutError extends Error {
  constructor(public readonly code: LayoutErrorCode, message: string) {
    super(message);
  }
}

const MODES: SpeakerMode[] = ['hostPinned', 'autoActiveSpeaker', 'manual'];

const isUid = (v: unknown): v is string => typeof v === 'string' && v.length > 0 && v.length <= 128;
const isIndex = (v: unknown): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < Limits.wallSlots;

/** Validates raw callable args into a typed op. */
export function parseLayoutOp(raw: Record<string, unknown>): LayoutOp {
  const op = raw.op;
  switch (op) {
    case 'swap':
      if (!isIndex(raw.index)) throw new LayoutError('invalid-argument', 'index must be 0–5.');
      return { op, index: raw.index };
    case 'pin':
    case 'autoPromote':
      if (!isUid(raw.uid)) throw new LayoutError('invalid-argument', 'uid is required.');
      return { op, uid: raw.uid };
    case 'unpin':
      return { op };
    case 'setMode':
      if (!MODES.includes(raw.mode as SpeakerMode)) throw new LayoutError('invalid-argument', 'Unknown speaker mode.');
      return { op, mode: raw.mode as SpeakerMode };
    case 'rotateIn':
      if (!isUid(raw.uid)) throw new LayoutError('invalid-argument', 'uid is required.');
      if (!isIndex(raw.index)) throw new LayoutError('invalid-argument', 'index must be 0–5.');
      return { op, uid: raw.uid, index: raw.index };
    default:
      throw new LayoutError('invalid-argument', `Unknown layout op "${String(op)}".`);
  }
}

/** A member doc counts as "on stage" when it can publish. */
export const isStageRole = (r: StudioRole | undefined) => r === 'host' || r === 'coHost' || r === 'guest';

/**
 * Leader election, mirrored from the Dart `electLayoutLeader`:
 * the host while connected; otherwise (host gone ≥ leaderFailoverMs, or
 * never seen) the longest-serving connected coHost; nobody in between.
 */
export function electLeader(args: {
  hostId: string;
  members: Pick<StageMember, 'uid' | 'role' | 'joinedAtMs'>[];
  connected: Set<string>;
  hostAbsentForMs: number | null; // null = unknown → treat as absent long enough
}): string | null {
  const { hostId, members, connected, hostAbsentForMs } = args;
  if (connected.has(hostId)) return hostId;
  if (hostAbsentForMs !== null && hostAbsentForMs < Limits.leaderFailoverMs) return null;
  const cos = members
    .filter((m) => m.role === 'coHost' && m.uid !== hostId && connected.has(m.uid))
    .sort((a, b) => (a.joinedAtMs ?? 0) - (b.joinedAtMs ?? 0) || (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
  return cos.length ? cos[0].uid : null;
}

/**
 * Who may send [op]. Every op except autoPromote: host/coHost. autoPromote:
 * only the current leader ([leaderUid], computed by the caller).
 */
export function authorizeLayoutOp(op: LayoutOp, actor: { uid: string; role: StudioRole }, leaderUid: string | null) {
  if (op.op === 'autoPromote') {
    if (actor.uid !== leaderUid) throw new LayoutError('permission-denied', 'Only the layout leader can auto-promote.');
    if (actor.role !== 'host' && actor.role !== 'coHost') {
      throw new LayoutError('permission-denied', 'Only the host or a co-host can lead the layout.');
    }
    return;
  }
  if (actor.role !== 'host' && actor.role !== 'coHost') {
    throw new LayoutError('permission-denied', 'Only the host or a co-host can change the layout.');
  }
}

export interface LayoutContext {
  actorUid: string;
  nowMs: number;
  mode: SpeakerMode;
  hostId: string;
  /** uid → role for member docs; used to validate that uids are stage members. */
  roles: Record<string, StudioRole | undefined>;
}

export interface LayoutResult {
  /** New stage section, or undefined = unchanged. */
  stage?: StageLayout;
  /** New settings.speakerMode, or undefined = unchanged. */
  mode?: SpeakerMode;
}

const normalize = (s: StageLayout): StageLayout => ({
  centerUid: s.centerUid ?? '',
  wall: Array.from({ length: Limits.wallSlots }, (_, i) => s.wall?.[i] ?? null),
  overflow: [...(s.overflow ?? [])],
  pinnedUid: s.pinnedUid ?? null,
  updatedAtMs: s.updatedAtMs ?? 0,
  updatedBy: s.updatedBy ?? '',
});

function requireMember(ctx: LayoutContext, uid: string) {
  const role = uid === ctx.hostId ? 'host' : ctx.roles[uid];
  if (!isStageRole(role)) throw new LayoutError('failed-precondition', 'That person is not on stage.');
}

/** Swap [uid] (on the wall or in overflow) with the center. */
function bringToCenter(s: StageLayout, uid: string): StageLayout {
  if (s.centerUid === uid) return s;
  const wi = s.wall.indexOf(uid);
  const oi = s.overflow.indexOf(uid);
  if (wi < 0 && oi < 0) throw new LayoutError('failed-precondition', 'That person is not on the stage layout.');
  const wall = [...s.wall];
  const overflow = [...s.overflow];
  const prev = s.centerUid || null;
  if (wi >= 0) wall[wi] = prev;
  else if (prev) overflow[oi] = prev;
  else overflow.splice(oi, 1);
  return { ...s, centerUid: uid, wall, overflow };
}

const stamp = (s: StageLayout, ctx: LayoutContext): StageLayout => ({
  ...s,
  updatedAtMs: ctx.nowMs,
  updatedBy: ctx.actorUid,
});

/** The pure transition. Throws [LayoutError] on any rejected op. */
export function applyLayoutOp(stageIn: StageLayout, op: LayoutOp, ctx: LayoutContext): LayoutResult {
  const s = normalize(stageIn);
  switch (op.op) {
    case 'swap': {
      const uid = s.wall[op.index];
      if (!uid) throw new LayoutError('failed-precondition', 'That wall slot is empty.');
      requireMember(ctx, uid);
      return { stage: stamp(bringToCenter(s, uid), ctx) };
    }
    case 'pin': {
      requireMember(ctx, op.uid);
      const moved = s.centerUid === op.uid ? s : bringToCenter(s, op.uid);
      if (moved === s && s.pinnedUid === op.uid) return {};
      return { stage: stamp({ ...moved, pinnedUid: op.uid }, ctx) };
    }
    case 'unpin':
      if (s.pinnedUid === null) return {};
      return { stage: stamp({ ...s, pinnedUid: null }, ctx) };
    case 'setMode': {
      const res: LayoutResult = {};
      if (op.mode !== ctx.mode) res.mode = op.mode;
      // hostPinned means "the host stays in the center": bring them back.
      if (op.mode === 'hostPinned' && s.centerUid !== ctx.hostId) {
        const onLayout = s.wall.includes(ctx.hostId) || s.overflow.includes(ctx.hostId);
        if (onLayout) res.stage = stamp(bringToCenter(s, ctx.hostId), ctx);
      }
      return res;
    }
    case 'rotateIn': {
      requireMember(ctx, op.uid);
      const oi = s.overflow.indexOf(op.uid);
      if (oi < 0) throw new LayoutError('failed-precondition', 'Only overflow members can rotate onto the wall.');
      const wall = [...s.wall];
      const overflow = [...s.overflow];
      const out = wall[op.index];
      wall[op.index] = op.uid;
      if (out) overflow[oi] = out;
      else overflow.splice(oi, 1);
      return { stage: stamp({ ...s, wall, overflow }, ctx) };
    }
    case 'autoPromote': {
      if (ctx.mode !== 'autoActiveSpeaker') throw new LayoutError('failed-precondition', 'Auto speaker mode is off.');
      if (s.pinnedUid) throw new LayoutError('failed-precondition', 'The center is pinned.');
      if (ctx.nowMs - s.updatedAtMs < Limits.minCenterHoldMs) {
        throw new LayoutError('failed-precondition', 'The center is still in its minimum hold.');
      }
      if (s.centerUid === op.uid) return {};
      requireMember(ctx, op.uid);
      return { stage: stamp(bringToCenter(s, op.uid), ctx) };
    }
  }
}
