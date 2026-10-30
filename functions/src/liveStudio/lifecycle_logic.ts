/**
 * LIVE STUDIO v2 — live lifecycle rules (pure; no Firebase imports).
 *
 * - Setup-wizard extras accepted by lsStart (category, cover, audience, join requests).
 * - When a live is orphaned (host app killed / network gone) so the sweeper
 *   (lifecycle.ts) closes it server-side and it never hangs.
 */

/** The host app pings lsHeartbeat this often while live. */
export const HEARTBEAT_INTERVAL_MS = 20_000;

/** No heartbeat for this long → the host is gone (covers ~4 missed pings + a short reconnect). */
export const HEARTBEAT_STALE_MS = 90_000;

/** LiveKit saw the host leave the room and they did not come back within this grace. */
export const HOST_LEFT_GRACE_MS = 60_000;

/** A live with no heartbeat at all (older app builds) is closed after this long. */
export const NO_HEARTBEAT_MAX_MS = 12 * 60 * 60 * 1000;

/** A live with no heartbeat yet gets this long to send its first one before
 *  the host-left signal alone can end it. */
export const FIRST_HEARTBEAT_GRACE_MS = 2 * 60 * 1000;

export type EndReason = 'host' | 'timeout' | 'host_left' | 'room_closed';

export const CATEGORY_MAX_LENGTH = 40;
/** `private` is accepted for older clients but treated like `public` (no invite list yet). */
export const AUDIENCE_MODES = ['public', 'followers', 'private'] as const;
export type AudienceMode = (typeof AUDIENCE_MODES)[number];

export interface StartExtras {
  category: string | null;
  coverUrl: string | null;
  audienceMode: AudienceMode;
  allowGuestRequests: boolean;
}

const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

/**
 * Optional setup-wizard fields of lsStart. Invalid values fall back to the
 * defaults instead of failing the start (older clients send none of them).
 */
export function parseStartExtras(data: unknown): StartExtras {
  const d = (data && typeof data === 'object' && !Array.isArray(data) ? data : {}) as Record<string, unknown>;
  const cat = typeof d.category === 'string' ? d.category.trim() : '';
  const category = cat && cat.length <= CATEGORY_MAX_LENGTH && !CONTROL_CHARS.test(cat) ? cat : null;
  const cover = typeof d.coverUrl === 'string' ? d.coverUrl.trim() : '';
  const coverUrl = cover.startsWith('https://') && cover.length <= 2048 ? cover : null;
  const audienceMode = (AUDIENCE_MODES as readonly string[]).includes(d.audienceMode as string)
    ? (d.audienceMode as AudienceMode)
    : 'public';
  const allowGuestRequests = typeof d.allowGuestRequests === 'boolean' ? d.allowGuestRequests : true;
  return { category, coverUrl, audienceMode, allowGuestRequests };
}

export interface LiveTimes {
  status: unknown;
  createdMs: number | null;
  heartbeatMs: number | null;
  hostLeftMs: number | null;
}

/** Why [live] should be closed now, or null when it is healthy (or already ended). */
export function orphanReason(live: LiveTimes, nowMs: number): EndReason | null {
  if (live.status !== 'live') return null;
  if (live.hostLeftMs !== null && nowMs - live.hostLeftMs >= HOST_LEFT_GRACE_MS) {
    // A fresh heartbeat after the leave means the host is back on another connection.
    if (live.heartbeatMs === null || live.heartbeatMs < live.hostLeftMs) {
      if (live.heartbeatMs !== null || live.createdMs === null || nowMs - live.createdMs >= FIRST_HEARTBEAT_GRACE_MS) {
        return 'host_left';
      }
    }
  }
  if (live.heartbeatMs !== null) {
    return nowMs - live.heartbeatMs >= HEARTBEAT_STALE_MS ? 'timeout' : null;
  }
  if (live.createdMs !== null && nowMs - live.createdMs >= NO_HEARTBEAT_MAX_MS) return 'timeout';
  return null;
}

/** Milliseconds of a Firestore Timestamp / Date / number, else null. */
export function toMs(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (v instanceof Date) return v.getTime();
  if (v && typeof v === 'object' && typeof (v as { toMillis?: unknown }).toMillis === 'function') {
    return (v as { toMillis: () => number }).toMillis();
  }
  return null;
}
