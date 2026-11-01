/**
 * LIVE STUDIO v2 — "Watch together" layer: pure logic (no Firestore, no fetch).
 *
 * The host (or a co-host) puts a YouTube video or a web page on a shared
 * layer above the stage. Their camera keeps streaming; nothing is re-streamed
 * into LiveKit. Every viewer plays the same thing locally (YouTube through the
 * official IFrame player) and follows `live_streams/{id}/studio/watch`:
 *
 *   target = positionMs + (serverNow − anchorServerMs) × rate   (while playing)
 *
 * Unit-tested in __tests__/watch_logic.test.ts; watch.ts does the I/O.
 */
import { analyzeUrl } from '../guard/linkSafety';

export type WatchKind = 'youtube' | 'browser';
export type WatchPlayback = 'playing' | 'paused' | 'ended';

export interface WatchYouTube {
  videoId: string;
  title: string;
  channel: string;
  thumbUrl: string;
}

export interface WatchBrowser {
  url: string;
}

/** `live_streams/{id}/studio/watch`. `kind: null` = nothing on the layer. */
export interface WatchDoc {
  kind: WatchKind | null;
  youtube: WatchYouTube | null;
  browser: WatchBrowser | null;
  state: WatchPlayback;
  positionMs: number;
  rate: number;
  /** Server time at which [positionMs] was true. */
  anchorServerMs: number;
  by: string;
  rev: number;
  updatedAtMs: number;
}

export const EMPTY_WATCH: WatchDoc = {
  kind: null,
  youtube: null,
  browser: null,
  state: 'paused',
  positionMs: 0,
  rate: 1,
  anchorServerMs: 0,
  by: '',
  rev: 0,
  updatedAtMs: 0,
};

export class WatchError extends Error {
  constructor(public readonly code: 'invalid-argument' | 'failed-precondition', message: string) {
    super(message);
  }
}

export type WatchOp =
  | { op: 'youtube'; video: WatchYouTube }
  | { op: 'browser'; url: string }
  | { op: 'play' | 'pause' | 'seek'; positionMs: number }
  | { op: 'rate'; rate: number }
  | { op: 'ended' }
  | { op: 'stop' };

export const MAX_POSITION_MS = 24 * 60 * 60 * 1000;
export const RATES = [0.5, 0.75, 1, 1.25, 1.5, 2] as const;
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const MAX_URL = 2000;

const str = (v: unknown, max: number): string => (typeof v === 'string' ? v.trim().slice(0, max) : '');

export function isVideoId(v: unknown): v is string {
  return typeof v === 'string' && VIDEO_ID.test(v);
}

function position(v: unknown): number {
  if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > MAX_POSITION_MS) {
    throw new WatchError('invalid-argument', 'positionMs must be a number of milliseconds.');
  }
  return Math.round(v);
}

/** Only https://i.ytimg.com thumbnails are kept (they come from our search). */
function thumb(v: unknown): string {
  const s = str(v, 300);
  return /^https:\/\/i\d?\.ytimg\.com\//.test(s) ? s : '';
}

/**
 * Validates a page for the shared browser: https only, a real public host
 * (no IP, localhost or private names), not a look-alike / phishing address.
 * Returns the normalized URL.
 */
export function validateBrowserUrl(raw: unknown): string {
  const s = str(raw, MAX_URL + 1);
  if (!s || s.length > MAX_URL) throw new WatchError('invalid-argument', 'Enter a web address.');
  let u: URL;
  try {
    u = new URL(s);
  } catch {
    throw new WatchError('invalid-argument', 'That is not a web address.');
  }
  if (u.protocol !== 'https:') throw new WatchError('invalid-argument', 'Only secure (https) pages can be shared.');
  if (u.username || u.password) throw new WatchError('invalid-argument', 'Addresses with a login inside cannot be shared.');
  const host = u.hostname.toLowerCase();
  if (
    !host.includes('.') ||
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host.endsWith('.internal') ||
    /^\d{1,3}(\.\d{1,3}){3}$/.test(host) ||
    host.startsWith('[')
  ) {
    throw new WatchError('invalid-argument', 'Only public websites can be shared.');
  }
  const finding = analyzeUrl(u.toString());
  if (finding && finding.points >= 40) {
    throw new WatchError('failed-precondition', `This page cannot be shared: ${finding.reasons[0] ?? 'it looks unsafe'}.`);
  }
  return u.toString();
}

/** Parses an `lsWatch` request body (everything except streamId). */
export function parseWatchOp(data: Record<string, unknown>): WatchOp {
  switch (data.op) {
    case 'youtube': {
      if (!isVideoId(data.videoId)) throw new WatchError('invalid-argument', 'videoId must be a YouTube video id.');
      return {
        op: 'youtube',
        video: {
          videoId: data.videoId,
          title: str(data.title, 200),
          channel: str(data.channel, 100),
          thumbUrl: thumb(data.thumbUrl),
        },
      };
    }
    case 'browser':
      return { op: 'browser', url: validateBrowserUrl(data.url) };
    case 'play':
    case 'pause':
    case 'seek':
      return { op: data.op, positionMs: position(data.positionMs) };
    case 'rate': {
      const r = data.rate;
      if (typeof r !== 'number' || !(RATES as readonly number[]).includes(r)) {
        throw new WatchError('invalid-argument', `rate must be one of ${RATES.join(', ')}.`);
      }
      return { op: 'rate', rate: r };
    }
    case 'ended':
      return { op: 'ended' };
    case 'stop':
      return { op: 'stop' };
    default:
      throw new WatchError('invalid-argument', 'Unknown watch op.');
  }
}

/** Where playback is at [nowMs] (server clock). */
export function targetPositionMs(w: Pick<WatchDoc, 'state' | 'positionMs' | 'anchorServerMs' | 'rate'>, nowMs: number): number {
  if (w.state !== 'playing') return w.positionMs;
  return Math.max(0, w.positionMs + Math.round((nowMs - w.anchorServerMs) * w.rate));
}

/** Normalizes a stored doc (missing / older shape → [EMPTY_WATCH] fields). */
export function normalizeWatch(raw: Record<string, unknown> | null | undefined): WatchDoc {
  if (!raw) return { ...EMPTY_WATCH };
  const kind = raw.kind === 'youtube' || raw.kind === 'browser' ? raw.kind : null;
  const yt = raw.youtube as Record<string, unknown> | null | undefined;
  const br = raw.browser as Record<string, unknown> | null | undefined;
  const state = raw.state === 'playing' || raw.state === 'ended' ? raw.state : 'paused';
  const num = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : d);
  return {
    kind,
    youtube: yt && isVideoId(yt.videoId)
      ? { videoId: yt.videoId, title: str(yt.title, 200), channel: str(yt.channel, 100), thumbUrl: thumb(yt.thumbUrl) }
      : null,
    browser: br && typeof br.url === 'string' ? { url: br.url } : null,
    state,
    positionMs: num(raw.positionMs, 0),
    rate: num(raw.rate, 1),
    anchorServerMs: num(raw.anchorServerMs, 0),
    by: str(raw.by, 128),
    rev: num(raw.rev, 0),
    updatedAtMs: num(raw.updatedAtMs, 0),
  };
}

/** Applies [op] by [by] at server time [nowMs]. Returns the new doc. */
export function applyWatchOp(cur: WatchDoc, op: WatchOp, by: string, nowMs: number): WatchDoc {
  const stamp = (next: Partial<WatchDoc>): WatchDoc => ({
    ...cur,
    ...next,
    by,
    rev: cur.rev + 1,
    updatedAtMs: nowMs,
  });
  switch (op.op) {
    case 'youtube':
      // Starts playing from 0: viewers seek to the moving target as they load.
      return stamp({
        kind: 'youtube',
        youtube: op.video,
        browser: null,
        state: 'playing',
        positionMs: 0,
        rate: 1,
        anchorServerMs: nowMs,
      });
    case 'browser':
      return stamp({ kind: 'browser', browser: { url: op.url }, youtube: null, state: 'paused', positionMs: 0, anchorServerMs: nowMs });
    case 'stop':
      return stamp({ ...EMPTY_WATCH, rev: cur.rev + 1 });
    default:
      break;
  }
  if (cur.kind !== 'youtube') throw new WatchError('failed-precondition', 'No video is playing.');
  switch (op.op) {
    case 'play':
      return stamp({ state: 'playing', positionMs: op.positionMs, anchorServerMs: nowMs });
    case 'pause':
      return stamp({ state: 'paused', positionMs: op.positionMs, anchorServerMs: nowMs });
    case 'seek':
      return stamp({ positionMs: op.positionMs, anchorServerMs: nowMs });
    case 'rate':
      return stamp({ rate: op.rate, positionMs: targetPositionMs(cur, nowMs), anchorServerMs: nowMs });
    case 'ended':
      return stamp({ state: 'ended', positionMs: targetPositionMs(cur, nowMs), anchorServerMs: nowMs });
  }
}

// ─── YouTube search ──────────────────────────────────────────────────────────

export interface YouTubeHit {
  videoId: string;
  title: string;
  channel: string;
  thumbUrl: string;
  live: boolean;
}

export function sanitizeYouTubeQuery(v: unknown): string {
  return str(v, 100).replace(/[\u0000-\u001f]/g, ' ');
}

const decodeEntities = (s: string) =>
  s
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');

/** Maps one `search.list` item (YouTube Data API v3) to a hit; null when unusable. */
export function fromYouTubeItem(raw: unknown): YouTubeHit | null {
  const item = raw as {
    id?: { videoId?: unknown };
    snippet?: {
      title?: unknown;
      channelTitle?: unknown;
      liveBroadcastContent?: unknown;
      thumbnails?: Record<string, { url?: unknown }>;
    };
  } | null;
  const videoId = item?.id?.videoId;
  if (!isVideoId(videoId)) return null;
  const sn = item?.snippet ?? {};
  const th = sn.thumbnails ?? {};
  const url = th.high?.url ?? th.medium?.url ?? th.default?.url;
  return {
    videoId,
    title: decodeEntities(str(sn.title, 200)),
    channel: decodeEntities(str(sn.channelTitle, 100)),
    thumbUrl: thumb(url),
    live: sn.liveBroadcastContent === 'live',
  };
}
