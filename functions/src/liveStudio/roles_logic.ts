/**
 * LIVE STUDIO v2 — roles, join requests and moderation: pure logic
 * (workstream #4). No Firestore / LiveKit imports, so everything here is
 * unit-tested in __tests__/roles_logic.test.ts.
 *
 * Permission matrix: docs/live-studio/ARCHITECTURE.md §6.
 */
import {
  ACCENT_PALETTE,
  JoinRequestStatus,
  Limits,
  ModerationAction,
  StageLayout,
  StageMember,
  StudioRole,
  StudioStatus,
} from './contracts';
import { PublishSource, grantForRole } from './media_logic';

// ─── Actions ─────────────────────────────────────────────────────────────────

/**
 * `lsModerate` actions. The contract's [ModerationAction] lacks the co-host
 * promotions; they are added locally until the integrator extends the
 * contract (requested change).
 */
export type StudioModerationAction = ModerationAction | 'promoteCoHost' | 'demoteCoHost';

export const MODERATION_ACTIONS: readonly StudioModerationAction[] = [
  'mute',
  'removeFromStage',
  'block',
  'promoteCoHost',
  'demoteCoHost',
];

/** Every action this module authorizes. */
export type RolesAction = 'requestJoin' | 'cancelRequest' | 'respondRequest' | 'leaveStage' | StudioModerationAction;

/** Rate limit for lsRequestJoin: 1 call per 10 s per user. */
export const REQUEST_JOIN_MAX = 1;
export const REQUEST_JOIN_WINDOW_MS = 10_000;

export type RolesErrorCode = 'invalid-argument' | 'permission-denied' | 'failed-precondition' | 'not-found';

export class RolesError extends Error {
  constructor(public readonly code: RolesErrorCode, message: string) {
    super(message);
  }
}

export type Decision = { ok: true } | { ok: false; code: RolesErrorCode; message: string };

const OK: Decision = { ok: true };
const deny = (code: RolesErrorCode, message: string): Decision => ({ ok: false, code, message });

/** Throws [RolesError] for a refused decision. */
export function assertDecision(d: Decision): void {
  if (!d.ok) throw new RolesError(d.code, d.message);
}

// ─── §6 matrix: which actor roles may attempt each action ────────────────────

/**
 * Actor side of ARCHITECTURE §6 for the actions owned here. Target-specific
 * restrictions (co-hosts cannot act on the host, cannot block co-hosts, …)
 * are in [authorizeModeration].
 */
export const ACTOR_MATRIX: Readonly<Record<RolesAction, readonly StudioRole[]>> = {
  requestJoin: ['viewer'],
  cancelRequest: ['viewer'],
  respondRequest: ['host', 'coHost'],
  mute: ['host', 'coHost'],
  removeFromStage: ['host', 'coHost'],
  block: ['host', 'coHost'],
  promoteCoHost: ['host'],
  demoteCoHost: ['host'],
  leaveStage: ['coHost', 'guest'],
};

export const actorAllowed = (action: RolesAction, role: StudioRole): boolean => ACTOR_MATRIX[action].includes(role);

export const isOnStageRole = (r: StudioRole | undefined): boolean => r === 'host' || r === 'coHost' || r === 'guest';

// ─── Arg parsing ─────────────────────────────────────────────────────────────

const isUid = (v: unknown): v is string =>
  typeof v === 'string' && v.length > 0 && v.length <= 128 && !v.includes('/');

export function parseTargetUid(v: unknown): string {
  if (!isUid(v)) throw new RolesError('invalid-argument', 'uid is required.');
  return v;
}

export function parseModerationAction(v: unknown): StudioModerationAction {
  if (typeof v === 'string' && (MODERATION_ACTIONS as readonly string[]).includes(v)) {
    return v as StudioModerationAction;
  }
  throw new RolesError('invalid-argument', `Unknown moderation action "${String(v)}".`);
}

export function parseRespondArgs(data: unknown): { uid: string; approve: boolean } {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const uid = parseTargetUid(d.uid);
  if (typeof d.approve !== 'boolean') throw new RolesError('invalid-argument', 'approve must be a boolean.');
  return { uid, approve: d.approve };
}

export function parseModerateArgs(data: unknown): { uid: string; action: StudioModerationAction } {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  return { uid: parseTargetUid(d.uid), action: parseModerationAction(d.action) };
}

// ─── Decisions ───────────────────────────────────────────────────────────────

/** lsRequestJoin: a viewer, not blocked, on a live stream that allows requests. */
export function requestJoinDecision(a: {
  role: StudioRole;
  blocked: boolean;
  status: StudioStatus;
  allowGuestRequests: boolean;
  existing?: JoinRequestStatus | null;
}): Decision {
  if (a.blocked) return deny('permission-denied', 'You are blocked from this live.');
  if (a.status !== 'live') return deny('failed-precondition', 'This live is not on air.');
  if (!actorAllowed('requestJoin', a.role)) return deny('failed-precondition', 'You are already on stage.');
  if (!a.allowGuestRequests) return deny('failed-precondition', 'The host is not taking requests.');
  return OK;
}

/** lsCancelRequest: the requester's own doc, still pending. */
export function cancelDecision(existing: JoinRequestStatus | null | undefined): Decision {
  if (!existing) return deny('not-found', 'No request to cancel.');
  if (existing !== 'pending') return deny('failed-precondition', 'This request was already answered.');
  return OK;
}

/** lsRespondRequest: a manager answering a pending request of a viewer. */
export function respondDecision(a: {
  actorRole: StudioRole;
  requestStatus: JoinRequestStatus | null | undefined;
  targetRole: StudioRole;
  targetBlocked: boolean;
}): Decision {
  if (!actorAllowed('respondRequest', a.actorRole)) return deny('permission-denied', 'Only the host or a co-host can answer.');
  if (!a.requestStatus) return deny('not-found', 'Request not found.');
  if (a.requestStatus !== 'pending') return deny('failed-precondition', 'This request was already answered.');
  if (a.targetBlocked) return deny('failed-precondition', 'This user is blocked.');
  if (a.targetRole !== 'viewer') return deny('failed-precondition', 'This user is already on stage.');
  return OK;
}

/** lsLeaveStage: a guest or co-host leaves (the host ends the live instead). */
export function leaveDecision(role: StudioRole): Decision {
  if (role === 'host') return deny('failed-precondition', 'The host ends the live instead of leaving the stage.');
  if (!actorAllowed('leaveStage', role)) return deny('failed-precondition', 'You are not on stage.');
  return OK;
}

/**
 * lsModerate: actor/target rules of ARCHITECTURE §6.
 * - host/coHost only; promote/demote are host only;
 * - nobody targets themselves (use lsLeaveStage);
 * - a co-host never acts on the host, and never blocks a co-host;
 * - mute/remove need someone on stage, promote needs a guest, demote a co-host.
 */
export function authorizeModeration(a: {
  action: StudioModerationAction;
  actorUid: string;
  actorRole: StudioRole;
  targetUid: string;
  targetRole: StudioRole;
  targetOnStage: boolean;
}): Decision {
  if (!actorAllowed(a.action, a.actorRole)) {
    return deny('permission-denied', a.action === 'promoteCoHost' || a.action === 'demoteCoHost'
      ? 'Only the host can change co-hosts.'
      : 'Only the host or a co-host can moderate.');
  }
  if (a.actorUid === a.targetUid) return deny('invalid-argument', 'You cannot moderate yourself.');
  if (a.targetRole === 'host') return deny('permission-denied', 'Nobody can moderate the host.');
  switch (a.action) {
    case 'mute':
      if (!a.targetOnStage && !isOnStageRole(a.targetRole)) return deny('failed-precondition', 'This user is not on stage.');
      return OK;
    case 'removeFromStage':
      if (!a.targetOnStage && !isOnStageRole(a.targetRole)) return deny('failed-precondition', 'This user is not on stage.');
      return OK;
    case 'block':
      if (a.actorRole === 'coHost' && a.targetRole === 'coHost') {
        return deny('permission-denied', 'Co-hosts cannot block other co-hosts.');
      }
      return OK;
    case 'promoteCoHost':
      if (a.targetRole !== 'guest') return deny('failed-precondition', 'Only a guest on stage can become a co-host.');
      return OK;
    case 'demoteCoHost':
      if (a.targetRole !== 'coHost') return deny('failed-precondition', 'This user is not a co-host.');
      return OK;
  }
}

// ─── Stage layout ────────────────────────────────────────────────────────────

export type Placement = { kind: 'wall'; index: number } | { kind: 'overflow' } | { kind: 'already' };

const onLayout = (s: StageLayout, uid: string) =>
  s.centerUid === uid || s.wall.includes(uid) || s.overflow.includes(uid);

const normWall = (wall: (string | null)[]): (string | null)[] =>
  Array.from({ length: Limits.wallSlots }, (_, i) => wall[i] ?? null);

/** Puts [uid] in the first free wall index, or overflow when the wall is full. */
export function placeOnStage(
  stage: StageLayout,
  uid: string,
  nowMs: number,
  by: string,
): { stage: StageLayout; placement: Placement } {
  if (onLayout(stage, uid)) return { stage, placement: { kind: 'already' } };
  const wall = normWall(stage.wall);
  const index = wall.findIndex((u) => !u);
  if (index >= 0) {
    wall[index] = uid;
    return {
      stage: { ...stage, wall, updatedAtMs: nowMs, updatedBy: by },
      placement: { kind: 'wall', index },
    };
  }
  return {
    stage: { ...stage, wall, overflow: [...stage.overflow, uid], updatedAtMs: nowMs, updatedBy: by },
    placement: { kind: 'overflow' },
  };
}

/**
 * Removes [uid] from the center, wall and overflow. If they were in the
 * center the host returns to the center (and leaves their own wall/overflow
 * spot). A freed wall slot is refilled from the head of overflow. A pin on
 * [uid] is cleared. Returns `undefined` when [uid] was not on the layout.
 */
export function removeFromLayout(
  stage: StageLayout,
  uid: string,
  hostId: string,
  nowMs: number,
  by: string,
): StageLayout | undefined {
  if (!onLayout(stage, uid) && stage.pinnedUid !== uid) return undefined;
  let centerUid = stage.centerUid;
  const gone = new Set([uid]);
  if (centerUid === uid) {
    centerUid = hostId;
    gone.add(hostId);
  }
  const wall = normWall(stage.wall).map((u) => (u && gone.has(u) ? null : u));
  const overflow = stage.overflow.filter((u) => !gone.has(u));
  for (let i = 0; i < wall.length && overflow.length > 0; i++) {
    if (!wall[i]) wall[i] = overflow.shift()!;
  }
  return {
    ...stage,
    centerUid,
    wall,
    overflow,
    pinnedUid: stage.pinnedUid === uid ? null : stage.pinnedUid,
    updatedAtMs: nowMs,
    updatedBy: by,
  };
}

// ─── Members ─────────────────────────────────────────────────────────────────

/**
 * First palette accent not used by the current on-stage members (by join
 * order). When every accent is taken, cycles by the number of members.
 */
export function pickAccent(
  members: Pick<StageMember, 'uid' | 'accent' | 'role' | 'joinedAtMs'>[],
  forUid?: string,
  palette: readonly string[] = ACCENT_PALETTE,
): string {
  const current = members
    .filter((m) => m.uid !== forUid && isOnStageRole(m.role))
    .sort((a, b) => (a.joinedAtMs ?? 0) - (b.joinedAtMs ?? 0));
  const used = new Set(current.map((m) => (m.accent ?? '').toUpperCase()));
  const free = palette.find((c) => !used.has(c.toUpperCase()));
  return free ?? palette[current.length % palette.length];
}

/** Members doc fields written on approval (chatMuted is preserved by merge). */
export function guestMemberPatch(a: {
  uid: string;
  displayName: string;
  avatarUrl: string;
  accent: string;
  nowMs: number;
}): Omit<StageMember, 'chatMuted'> {
  return {
    uid: a.uid,
    displayName: a.displayName,
    avatarUrl: a.avatarUrl,
    accent: a.accent,
    role: 'guest',
    micOn: true,
    camOn: true,
    joinedAtMs: a.nowMs,
  };
}

/** Members doc fields written when someone leaves or is removed from the stage. */
export const offStagePatch = (): Pick<StageMember, 'role' | 'micOn' | 'camOn'> => ({
  role: 'viewer',
  micOn: false,
  camOn: false,
});

// ─── LiveKit ─────────────────────────────────────────────────────────────────

/** LiveKit ParticipantPermission for [role] (string sources; mapped to TrackSource in roles.ts). */
export function permissionForRole(role: StudioRole): {
  canPublish: boolean;
  canSubscribe: true;
  canPublishData: false;
  canPublishSources: PublishSource[];
} {
  const g = grantForRole(role, '');
  return {
    canPublish: g.canPublish,
    canSubscribe: true,
    canPublishData: false,
    canPublishSources: g.canPublishSources,
  };
}

/** Sids of published microphone tracks (by source, or by track name `mic` as a fallback). */
export function micTrackSids(
  tracks: { sid: string; source?: number; name?: string }[],
  micSource: number,
  micName = 'mic',
): string[] {
  return tracks.filter((t) => t.sid && (t.source === micSource || t.name === micName)).map((t) => t.sid);
}

/** `allowGuestRequests` on the stream doc; defaults to true (v1 default). */
export const allowsGuestRequests = (streamDoc: Record<string, unknown> | undefined): boolean =>
  streamDoc?.allowGuestRequests !== false;
