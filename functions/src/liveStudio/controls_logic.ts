/**
 * LIVE STUDIO v2 — chat mode and join-request controls (pure logic).
 * Used by the security advisories' one-tap actions (security.ts) and the host.
 */
import { StudioRole, isManager } from './contracts';

export type ChatMode = 'open' | 'slow' | 'followers';

export interface ChatModeState {
  mode: ChatMode;
  /** Minimum seconds between two comments from one viewer in slow mode. */
  slowSeconds: number;
}

export const DEFAULT_CHAT_MODE: ChatModeState = { mode: 'open', slowSeconds: 0 };
export const SLOW_MIN_S = 5;
export const SLOW_MAX_S = 300;
export const SLOW_DEFAULT_S = 15;

export type Parsed<T> = { ok: true; value: T } | { ok: false; reason: string };

export function parseChatMode(data: Record<string, unknown>): Parsed<ChatModeState> {
  const mode = data.mode;
  if (mode !== 'open' && mode !== 'slow' && mode !== 'followers') {
    return { ok: false, reason: "mode must be 'open', 'slow' or 'followers'." };
  }
  if (mode !== 'slow') return { ok: true, value: { mode, slowSeconds: 0 } };
  const raw = data.slowSeconds === undefined ? SLOW_DEFAULT_S : data.slowSeconds;
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return { ok: false, reason: 'slowSeconds must be a number.' };
  return { ok: true, value: { mode, slowSeconds: Math.min(SLOW_MAX_S, Math.max(SLOW_MIN_S, Math.round(raw))) } };
}

export function readChatMode(raw: unknown): ChatModeState {
  if (!raw || typeof raw !== 'object') return DEFAULT_CHAT_MODE;
  const r = raw as Record<string, unknown>;
  const p = parseChatMode(r);
  return p.ok ? p.value : DEFAULT_CHAT_MODE;
}

/** Host and co-hosts are never limited by chat mode. */
export function chatModeApplies(role: StudioRole): boolean {
  return !isManager(role);
}

/** What lsComment must check for a non-manager under [mode]. */
export function chatModeRequirement(
  mode: ChatModeState,
  role: StudioRole,
): { kind: 'none' } | { kind: 'slow'; seconds: number } | { kind: 'follower' } {
  if (!chatModeApplies(role)) return { kind: 'none' };
  if (mode.mode === 'slow') return { kind: 'slow', seconds: mode.slowSeconds };
  if (mode.mode === 'followers') return { kind: 'follower' };
  return { kind: 'none' };
}

/** relationships/{follower}_{host} with status accepted (RelationshipRepository). */
export const followDocId = (followerUid: string, hostId: string) => `${followerUid}_${hostId}`;
export const isAcceptedFollow = (status: unknown) => status === 'accepted';
