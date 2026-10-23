/**
 * LIVE STUDIO v2 — realtime social, pure logic (workstream #2).
 *
 * No Firestore / LiveKit imports here: everything is deterministic given its
 * inputs (clock values are passed in), so it is unit-tested in
 * `__tests__/social_logic.test.ts`. The I/O lives in `social.ts`.
 */
import { Limits, StudioRole, ReactionKind, SystemLineKind, isManager } from './contracts';

// ─── Comments: normalization ────────────────────────────────────────────────

export type NormalizeResult = { ok: true; text: string } | { ok: false; reason: string };

/**
 * Collapses every whitespace run (including newlines and tabs) to one space,
 * strips control / zero-width characters, trims, and enforces the length cap.
 */
export function normalizeCommentText(raw: unknown, max: number = Limits.commentMaxLength): NormalizeResult {
  if (typeof raw !== 'string') return { ok: false, reason: 'Comment text is required.' };
  const text = raw
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‍⁠﻿]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (text.length === 0) return { ok: false, reason: 'Comment text is required.' };
  if ([...text].length > max) return { ok: false, reason: `Comments are limited to ${max} characters.` };
  return { ok: true, text };
}

/** Client-supplied idempotency key: `[A-Za-z0-9_-]{8,40}`. */
export function isValidClientId(v: unknown): v is string {
  return typeof v === 'string' && /^[A-Za-z0-9_-]{8,40}$/.test(v);
}

/**
 * Deterministic comment id when the client sends a `clientId`, so its
 * optimistic row has the same id as the server echo, and retries are
 * idempotent. Mirrored in Dart (`studioCommentDocId`).
 */
export function commentDocId(uid: string, clientId: string): string {
  return `${uid}_${clientId}`;
}

// ─── Comments: moderation hook ──────────────────────────────────────────────

export interface ModerationVerdict {
  allow: boolean;
  /** User-facing reason when [allow] is false. */
  reason?: string;
  /** Text to persist (a moderator may mask parts of it). */
  text: string;
}

/** A pluggable moderation step. May be async (e.g. a remote classifier). */
export type CommentModerator = (text: string, uid: string) => ModerationVerdict | Promise<ModerationVerdict>;

/** Lower-cases, strips diacritics and maps common leetspeak to letters. */
export function foldForMatching(s: string): string {
  const leet: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', $: 's', '!': 'i' };
  return s
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[013457@$!]/g, (c) => leet[c] ?? c);
}

/**
 * Default terms. Deliberately small: production lists belong in config and
 * are passed to [blockListModerator] (see `social.ts` → `setCommentModerator`).
 */
export const DEFAULT_BLOCKED_TERMS: readonly string[] = ['kill yourself', 'kys', 'go die'];

/** Terms that are masked (replaced with •) instead of rejecting the comment. */
export const DEFAULT_MASKED_TERMS: readonly string[] = [];

const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Basic block-list moderator. Whole-word / whole-phrase match on the folded
 * text: [blocked] terms reject the comment, [masked] terms are replaced with
 * bullets of the same length.
 */
export function blockListModerator(opts: { blocked?: readonly string[]; masked?: readonly string[] } = {}): CommentModerator {
  const build = (terms: readonly string[]) =>
    terms
      .map((t) => foldForMatching(t.trim()))
      .filter((t) => t.length > 0)
      .map((t) => new RegExp(`(^|[^a-z0-9])(${escapeRe(t).replace(/ /g, '\\s+')})(?=$|[^a-z0-9])`, 'g'));
  const blocked = build(opts.blocked ?? DEFAULT_BLOCKED_TERMS);
  const masked = build(opts.masked ?? DEFAULT_MASKED_TERMS);
  return (text) => {
    const folded = foldForMatching(text);
    for (const re of blocked) {
      re.lastIndex = 0;
      if (re.test(folded)) return { allow: false, reason: 'This comment breaks the community guidelines.', text };
    }
    if (masked.length === 0 || folded.length !== text.length) return { allow: true, text };
    // Folding kept the length, so indexes line up with the original text.
    const chars = [...text];
    for (const re of masked) {
      re.lastIndex = 0;
      let m: RegExpExecArray | null;
      while ((m = re.exec(folded)) !== null) {
        const start = m.index + m[1].length;
        for (let i = start; i < start + m[2].length; i++) chars[i] = '•';
      }
    }
    return { allow: true, text: chars.join('') };
  };
}

/** Runs moderators in order; the first rejection wins, masks accumulate. */
export function composeModerators(...mods: CommentModerator[]): CommentModerator {
  return async (text, uid) => {
    let current = text;
    for (const m of mods) {
      const v = await m(current, uid);
      if (!v.allow) return v;
      current = v.text;
    }
    return { allow: true, text: current };
  };
}

let activeModerator: CommentModerator = blockListModerator();

/**
 * Extension point: replace the moderator (e.g. compose the block list with a
 * remote classifier). Called once at module load by whoever wires it.
 */
export function setCommentModerator(m: CommentModerator): void {
  activeModerator = m;
}

/** The moderation hook `lsComment` calls. */
export function moderateComment(text: string, uid: string): Promise<ModerationVerdict> {
  return Promise.resolve(activeModerator(text, uid));
}

// ─── Comments: mute / permissions ───────────────────────────────────────────

export const MAX_MUTE_MINUTES = 24 * 60;

/** Returns minutes as an integer in 0..MAX_MUTE_MINUTES, or null if invalid. 0 = unmute. */
export function parseMuteMinutes(v: unknown): number | null {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  const m = Math.floor(v);
  return m < 0 || m > MAX_MUTE_MINUTES ? null : m;
}

export function muteUntil(nowMs: number, minutes: number): number {
  return nowMs + minutes * 60_000;
}

export function isChatMuted(memberChatMuted: boolean | undefined, muteUntilMs: number | undefined, nowMs: number): boolean {
  return memberChatMuted === true || (typeof muteUntilMs === 'number' && muteUntilMs > nowMs);
}

/** Host/co-host may delete any comment; anyone may delete their own. */
export function canDeleteComment(actorRole: StudioRole, actorUid: string, authorUid: string): boolean {
  return isManager(actorRole) || (actorUid.length > 0 && actorUid === authorUid);
}

/** Host/co-host may mute chat; a co-host cannot mute the host; nobody mutes themselves. */
export function canMuteChat(actorRole: StudioRole, actorUid: string, targetRole: StudioRole, targetUid: string): boolean {
  if (!isManager(actorRole) || actorUid === targetUid) return false;
  if (targetRole === 'host') return false;
  return true;
}

// ─── Comments: broadcast sampling ───────────────────────────────────────────

/** Number of Firestore budget shards for the per-second comment gate. */
export const COMMENT_GATE_SHARDS = 5;

/** Each shard's share of the per-second budget (rounded up, ≥ 1). */
export function shardBudget(total: number = Limits.commentBroadcastPerSecond, shards: number = COMMENT_GATE_SHARDS): number {
  return Math.max(1, Math.ceil(total / shards));
}

export const epochSecond = (nowMs: number) => Math.floor(nowMs / 1000);

/**
 * In-memory fixed 1-second window counter, keyed (e.g. by stream). Best
 * effort: it only sees this instance's traffic. Old keys are pruned lazily.
 */
export class SecondWindowCounter {
  private readonly windows = new Map<string, { sec: number; n: number }>();
  constructor(private readonly maxKeys = 2000) {}

  /** Records one hit and returns the count in the current second (incl. this one). */
  hit(key: string, nowMs: number): number {
    const sec = epochSecond(nowMs);
    const w = this.windows.get(key);
    if (!w || w.sec !== sec) {
      if (this.windows.size >= this.maxKeys) this.prune(sec);
      this.windows.set(key, { sec, n: 1 });
      return 1;
    }
    w.n += 1;
    return w.n;
  }

  count(key: string, nowMs: number): number {
    const w = this.windows.get(key);
    return w && w.sec === epochSecond(nowMs) ? w.n : 0;
  }

  private prune(sec: number) {
    for (const [k, w] of this.windows) if (w.sec !== sec) this.windows.delete(k);
    if (this.windows.size >= this.maxKeys) this.windows.clear();
  }
}

/** Pure decision for one per-second budget window (`{sec, n}` doc state). */
export function gateStep(
  doc: { sec?: number; n?: number } | undefined,
  nowMs: number,
  budget: number,
): { allow: boolean; next: { sec: number; n: number } | null } {
  const sec = epochSecond(nowMs);
  if (!doc || doc.sec !== sec) return { allow: true, next: { sec, n: 1 } };
  const n = doc.n ?? 0;
  if (n >= budget) return { allow: false, next: null };
  return { allow: true, next: { sec, n: n + 1 } };
}

/**
 * The sampling decision for one comment. Host/co-host comments are always
 * broadcast. Others are broadcast while this instance's local count is
 * within budget AND the global (Firestore) gate allows it.
 */
export function shouldBroadcastComment(input: {
  role: StudioRole;
  localCountThisSecond: number;
  globalAllow: boolean | null;
  budget?: number;
}): boolean {
  if (isManager(input.role)) return true;
  const budget = input.budget ?? Limits.commentBroadcastPerSecond;
  if (input.localCountThisSecond > budget) return false;
  return input.globalAllow === true;
}

// ─── Leases / throttles ─────────────────────────────────────────────────────

/** True when an action last done at [lastMs] may run again at [nowMs]. */
export function throttleDue(lastMs: number | undefined, nowMs: number, intervalMs: number): boolean {
  if (typeof lastMs !== 'number' || !Number.isFinite(lastMs)) return true;
  // A clock step backwards (lastMs in the future) beyond one interval resets the lease.
  if (lastMs - nowMs > intervalMs) return true;
  return nowMs - lastMs >= intervalMs;
}

/**
 * Per-instance memo of "not due before T" for leases, so hot paths skip the
 * Firestore read entirely while a lease is known to be held.
 */
export class LeaseMemo {
  private readonly until = new Map<string, number>();
  constructor(private readonly maxKeys = 5000) {}
  blocked(key: string, nowMs: number): boolean {
    const u = this.until.get(key);
    if (u === undefined) return false;
    if (nowMs >= u) {
      this.until.delete(key);
      return false;
    }
    return true;
  }
  hold(key: string, untilMs: number) {
    if (this.until.size >= this.maxKeys) this.until.clear();
    this.until.set(key, untilMs);
  }
}

/** System lines from reactions/shares: at most one per user per this window. */
export const SYSTEM_LINE_USER_INTERVAL_MS = 10_000;
/** studio/state `counts` is patched at most this often. */
export const COUNTS_STATE_INTERVAL_MS = 10_000;
/** Above this many viewers, `joined` lines are sampled. */
export const LARGE_ROOM_VIEWERS = 100;
/** Sampled `joined` lines: at most one per this window per stream. */
export const JOIN_LINE_INTERVAL_MS = 1000;
/** Extra wait after a reaction window closes, to absorb clock skew between instances. */
export const FLUSH_GRACE_MS = 60;

// ─── Reactions ──────────────────────────────────────────────────────────────

export const COUNTER_SHARDS = 10;

export type ReactionInput = { ok: true; kind: ReactionKind; n: number } | { ok: false; reason: string };

export function parseReaction(kind: unknown, n: unknown, max: number = Limits.reactionMaxPerCall): ReactionInput {
  if (kind !== 'love' && kind !== 'sparkles') return { ok: false, reason: 'kind must be love or sparkles.' };
  if (typeof n !== 'number' || !Number.isInteger(n) || n < 1 || n > max) {
    return { ok: false, reason: `n must be an integer from 1 to ${max}.` };
  }
  return { ok: true, kind, n };
}

/** Counter field in the shard docs. */
export const reactionField = (k: ReactionKind): 'loves' | 'sparkles' => (k === 'love' ? 'loves' : 'sparkles');

export const systemKindForReaction = (k: ReactionKind): SystemLineKind => (k === 'love' ? 'love' : 'sparkles');

export const SYSTEM_TEXT: Record<SystemLineKind, string> = {
  joined: 'joined the live',
  love: 'sent love',
  sparkles: 'sent sparkles',
  shared: 'shared this live',
  requested: 'requested to join the stage',
  onStage: 'is on stage',
};

/** Picks a shard index in 0..shards-1 from a random number in [0, 1). */
export function pickShard(rand: number, shards: number = COUNTER_SHARDS): number {
  const i = Math.floor(rand * shards);
  return Math.min(shards - 1, Math.max(0, i));
}

export interface ShardTotals {
  loves: number;
  sparkles: number;
  shares: number;
  viewers: number;
}

const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

/** Sums shard docs (missing docs/fields count as 0). */
export function sumShards(docs: (Record<string, unknown> | undefined)[]): ShardTotals {
  const t: ShardTotals = { loves: 0, sparkles: 0, shares: 0, viewers: 0 };
  for (const d of docs) {
    if (!d) continue;
    t.loves += num(d.loves);
    t.sparkles += num(d.sparkles);
    t.shares += num(d.shares);
    t.viewers += num(d.viewers);
  }
  return t;
}

/**
 * Deltas since the last flush. The flush doc remembers the totals it last
 * broadcast, so nothing is ever lost: increments that land after a flush's
 * read simply show up in the next window's delta.
 */
export function reactionDeltas(
  totals: { loves: number; sparkles: number },
  flushed: { loves?: number; sparkles?: number } | undefined,
): { loves: number; sparkles: number } {
  return {
    loves: Math.max(0, totals.loves - num(flushed?.loves)),
    sparkles: Math.max(0, totals.sparkles - num(flushed?.sparkles)),
  };
}

/** How long the flush leader waits before reading the shards. */
export function flushDelayMs(leaseAtMs: number, nowMs: number, windowMs: number = Limits.reactionAggregateWindowMs): number {
  return Math.max(0, leaseAtMs + windowMs + FLUSH_GRACE_MS - nowMs);
}

/**
 * Simulates the aggregation protocol (used by tests and as the reference
 * for `social.ts`): given call timestamps, returns the flush times. Each call
 * first increments, then tries to claim the window lease; only a claimer
 * schedules a flush at `leaseAt + window`.
 */
export function simulateAggregation(callTimesMs: number[], windowMs: number = Limits.reactionAggregateWindowMs): number[] {
  let leaseAt: number | undefined;
  const flushes: number[] = [];
  for (const t of [...callTimesMs].sort((a, b) => a - b)) {
    if (throttleDue(leaseAt, t, windowMs)) {
      leaseAt = t;
      flushes.push(t + windowMs);
    }
  }
  return flushes;
}

// ─── Presence / counts ──────────────────────────────────────────────────────

/** `studio_<streamId>` → streamId, or null for rooms that are not studio rooms. */
export function streamIdFromRoom(room: string | undefined): string | null {
  if (!room || !room.startsWith('studio_')) return null;
  const id = room.slice('studio_'.length);
  return /^[A-Za-z0-9_-]{1,128}$/.test(id) ? id : null;
}

/**
 * Viewer count. LiveKit's `room.numParticipants` (when the webhook carries
 * it) is authoritative; otherwise the ±1 counter maintained from join/leave
 * webhooks is used, clamped at 0 (webhooks can arrive out of order).
 */
export function resolveViewers(roomNumParticipants: number | undefined, counter: number): number {
  if (typeof roomNumParticipants === 'number' && roomNumParticipants > 0) return roomNumParticipants;
  return Math.max(0, Math.round(counter));
}

/** Participants = stage members + co-hosts + pending requests (ARCHITECTURE Q4). */
export function computeParticipants(stagePublishers: string[], coHostUids: string[], pendingRequests: number): number {
  const s = new Set<string>();
  for (const u of stagePublishers) if (u) s.add(u);
  for (const u of coHostUids) if (u) s.add(u);
  return s.size + Math.max(0, pendingRequests);
}

/** Publishers on stage (center + wall + overflow), from a raw stage object. */
export function stagePublishers(stage: { centerUid?: string; wall?: (string | null)[]; overflow?: string[] } | undefined): string[] {
  if (!stage) return [];
  return [
    ...(stage.centerUid ? [stage.centerUid] : []),
    ...((stage.wall ?? []).filter((u): u is string => typeof u === 'string' && u.length > 0)),
    ...((stage.overflow ?? []).filter((u) => typeof u === 'string' && u.length > 0)),
  ];
}

export function countsChanged(
  prev: { viewers?: number; participants?: number } | undefined,
  next: { viewers: number; participants: number },
): boolean {
  return !prev || prev.viewers !== next.viewers || prev.participants !== next.participants;
}

/**
 * Whether a `joined` line should be emitted. Small rooms: always. Large
 * rooms: only when the per-stream 1/s lease is due (the caller then claims it).
 */
export function joinLineMode(viewers: number, threshold: number = LARGE_ROOM_VIEWERS): 'always' | 'sampled' {
  return viewers <= threshold ? 'always' : 'sampled';
}

/** Random-ish id for broadcast-only system lines. */
export function systemLineId(nowMs: number, rand: number): string {
  return `sys_${nowMs.toString(36)}_${Math.floor(rand * 36 ** 6).toString(36).padStart(6, '0')}`;
}

/** Display name from a users/{uid} doc (same order as the Dart repositories). */
export function displayNameOf(d: Record<string, unknown> | undefined, fallback = 'Someone'): string {
  for (const k of ['fullName', 'displayName', 'username', 'name']) {
    const v = d?.[k];
    if (typeof v === 'string' && v.trim().length > 0) return v.trim().slice(0, 60);
  }
  return fallback;
}

export function avatarOf(d: Record<string, unknown> | undefined): string {
  for (const k of ['avatarUrl', 'photoUrl', 'photoURL']) {
    const v = d?.[k];
    if (typeof v === 'string' && v.length > 0) return v;
  }
  return '';
}
