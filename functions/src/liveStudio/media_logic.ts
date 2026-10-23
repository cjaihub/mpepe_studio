/**
 * LIVE STUDIO v2 — media pure logic (workstream #1, realtime media).
 * No Firestore / LiveKit imports so everything here is unit-testable.
 * See docs/live-studio/ARCHITECTURE.md §6–§7.
 */
import {
  ACCENT_PALETTE,
  SCHEMA_VERSION,
  StageMember,
  StudioRole,
  StudioSettings,
  StudioState,
  StudioStatus,
  emptyStage,
} from './contracts';

/** Token lifetime: one long live plus margin (~6 h). */
export const TOKEN_TTL_SECONDS = 6 * 60 * 60;

/** LiveKit closes an empty room after ~10 min (host app restarts survive). */
export const ROOM_EMPTY_TIMEOUT_SECONDS = 10 * 60;

/** Track sources a publisher may use. String names, mapped to LiveKit's TrackSource in media.ts. */
export type PublishSource = 'camera' | 'microphone' | 'screen_share';
export const PUBLISH_SOURCES: PublishSource[] = ['camera', 'microphone', 'screen_share'];

/** The LiveKit VideoGrant subset we issue (same field names as livekit-server-sdk). */
export interface StudioGrant {
  room: string;
  roomJoin: true;
  canSubscribe: true;
  canPublish: boolean;
  canPublishData: false;
  canPublishSources: PublishSource[];
  canUpdateOwnMetadata: false;
}

/**
 * Role → grant mapping (ARCHITECTURE §6).
 * - everyone joins and subscribes;
 * - only host / coHost / guest publish, and only camera, mic and screen share;
 * - `canPublishData` is false for everyone: all data goes through callables.
 */
export function grantForRole(role: StudioRole, room: string): StudioGrant {
  const publish = role === 'host' || role === 'coHost' || role === 'guest';
  return {
    room,
    roomJoin: true,
    canSubscribe: true,
    canPublish: publish,
    canPublishData: false,
    canPublishSources: publish ? [...PUBLISH_SOURCES] : [],
    canUpdateOwnMetadata: false,
  };
}

export type TokenRefusal =
  | { ok: false; code: 'failed-precondition'; message: string }
  | { ok: false; code: 'permission-denied'; message: string };

/** Decides whether a token may be minted. Blocked users and ended streams are refused. */
export function tokenDecision(input: { status: StudioStatus; blocked: boolean }): { ok: true } | TokenRefusal {
  if (input.blocked) return { ok: false, code: 'permission-denied', message: 'You are blocked from this live.' };
  if (input.status === 'ended') return { ok: false, code: 'failed-precondition', message: 'This live has ended.' };
  return { ok: true };
}

/**
 * Settings for a new live: the host's saved settings with the (partial) lsStart
 * argument on top, then normalized by settings_logic (the settings workstream
 * owns validation).
 */
export function mergeStartSettings(saved: unknown, arg: unknown): Record<string, unknown> {
  const obj = (v: unknown) => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
  return { ...obj(saved), ...obj(arg) };
}

/** Initial `studio/state` for a new live: host in the center, empty wall, goods table. */
export function buildInitialState(a: {
  streamId: string;
  hostId: string;
  title: string;
  settings: StudioSettings;
  nowMs: number;
}): StudioState {
  return {
    schemaVersion: SCHEMA_VERSION,
    streamId: a.streamId,
    hostId: a.hostId,
    title: a.title,
    status: 'live',
    seq: 0,
    settings: a.settings,
    stage: { ...emptyStage(a.hostId), updatedAtMs: a.nowMs, updatedBy: a.hostId },
    table: { mode: 'goods', goods: null, screen: null, watch: null },
    counts: { viewers: 0, participants: 1, loves: 0, sparkles: 0, shares: 0 },
  };
}

export interface Profile {
  displayName: string;
  avatarUrl: string;
}

/** Display name / avatar from a `users/{uid}` doc, falling back to auth token claims. */
export function profileFrom(user: Record<string, unknown> | undefined, token?: { name?: unknown; picture?: unknown }): Profile {
  const s = (v: unknown) => (typeof v === 'string' && v.trim().length > 0 ? v.trim() : '');
  const u = user ?? {};
  return {
    displayName: (s(u.displayName) || s(u.username) || s(token?.name) || 'Oneova creator').slice(0, 80),
    avatarUrl: s(u.avatarUrl) || s(u.photoUrl) || s(u.photoURL) || s(token?.picture),
  };
}

export function buildHostMember(uid: string, p: Profile, nowMs: number): StageMember {
  return {
    uid,
    displayName: p.displayName,
    avatarUrl: p.avatarUrl,
    accent: ACCENT_PALETTE[0],
    role: 'host',
    micOn: true,
    camOn: true,
    chatMuted: false,
    joinedAtMs: nowMs,
  };
}

/** Fields of `live_streams/{id}` required by the v1 rules + the v2 markers. */
export function buildStreamDoc(a: { streamId: string; hostId: string; title: string; profile: Profile }) {
  return {
    id: a.streamId,
    hostId: a.hostId,
    hostDisplayName: a.profile.displayName,
    hostAvatarUrl: a.profile.avatarUrl,
    title: a.title,
    status: 'live' as const,
    layoutMode: 'studio' as const,
    studioVersion: 2,
    audienceMode: 'public' as const,
    viewerCount: 0,
    totalLikes: 0,
    totalComments: 0,
  };
}

/** Everyone on stage (center, wall, overflow). */
export function stagePublishers(s: StudioState): string[] {
  return [s.stage.centerUid, ...s.stage.wall.filter((u): u is string => !!u), ...s.stage.overflow].filter(
    (u) => !!u,
  );
}

/** lsSetOwnMedia precondition: a publishing role AND currently on stage. */
export function canSetOwnMedia(role: StudioRole, uid: string, s: StudioState): boolean {
  if (role === 'viewer') return false;
  return stagePublishers(s).includes(uid);
}

/** Validates the two booleans of lsSetOwnMedia. Returns null when invalid. */
export function parseOwnMedia(data: unknown): { micOn: boolean; camOn: boolean } | null {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  if (typeof d.micOn !== 'boolean' || typeof d.camOn !== 'boolean') return null;
  return { micOn: d.micOn, camOn: d.camOn };
}

/** Strips Firestore-only fields (Timestamps) so the state is JSON-safe for callables. */
export function wireState(raw: Record<string, unknown>): StudioState {
  const { updatedAt, createdAt, ...rest } = raw;
  return rest as unknown as StudioState;
}
