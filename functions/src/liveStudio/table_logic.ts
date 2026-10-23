/**
 * LIVE STUDIO v2 — pure "On the table" logic (workstream #5).
 *
 * No Firestore / LiveKit imports: everything here is unit-tested in
 * __tests__/table_logic.test.ts. table.ts loads documents and calls these.
 */
import {
  GoodsRef,
  GoodsSource,
  PlaybackState,
  ScreenRef,
  StudioRole,
  TABLE_SCREEN_TRACK,
  TableMode,
  TableState,
  WatchParty,
} from './contracts';

export type TableErrorCode =
  | 'invalid-argument'
  | 'permission-denied'
  | 'not-found'
  | 'failed-precondition';

export class TableError extends Error {
  constructor(public readonly code: TableErrorCode, message: string) {
    super(message);
  }
}

const MODES: TableMode[] = ['goods', 'screen', 'match', 'movie'];
const SOURCES: GoodsSource[] = ['biz', 'stream'];
const PLAYBACK: PlaybackState[] = ['playing', 'paused', 'ended'];

/** 24 h: anything past this is not a real position. */
export const MAX_POSITION_MS = 24 * 60 * 60 * 1000;
const MAX_ID = 128;

export const isWatchMode = (m: TableMode) => m === 'match' || m === 'movie';

const id = (v: unknown, name: string): string => {
  if (typeof v !== 'string' || v.trim().length === 0 || v.length > MAX_ID || v.includes('/')) {
    throw new TableError('invalid-argument', `${name} must be a document id.`);
  }
  return v.trim();
};

// ─── lsSetTable request ──────────────────────────────────────────────────────

export type SetTableRequest =
  | { mode: 'goods'; goods: GoodsRef | null }
  | { mode: 'screen'; publisherUid: string | null }
  | { mode: 'match' | 'movie'; catalogId: string | null };

/**
 * Parses `{mode, ref?}`. `ref` by mode:
 * - goods: `{source: 'biz'|'stream', productId}` (omit → server picks: Biz first, then stream);
 * - screen: `{publisherUid}` (omit → the caller);
 * - match/movie: `{catalogId}` (omit → first currently valid entry of that kind, or none).
 */
export function parseSetTable(data: Record<string, unknown>): SetTableRequest {
  const mode = data.mode as TableMode;
  if (!MODES.includes(mode)) throw new TableError('invalid-argument', `mode must be one of ${MODES.join(', ')}.`);
  const raw = data.ref;
  if (raw !== undefined && raw !== null && (typeof raw !== 'object' || Array.isArray(raw))) {
    throw new TableError('invalid-argument', 'ref must be an object.');
  }
  const ref = (raw ?? null) as Record<string, unknown> | null;
  switch (mode) {
    case 'goods': {
      if (!ref) return { mode, goods: null };
      const source = ref.source as GoodsSource;
      if (!SOURCES.includes(source)) throw new TableError('invalid-argument', 'ref.source must be biz or stream.');
      return { mode, goods: { source, productId: id(ref.productId, 'ref.productId') } };
    }
    case 'screen':
      return { mode, publisherUid: ref && ref.publisherUid !== undefined ? id(ref.publisherUid, 'ref.publisherUid') : null };
    default:
      return { mode, catalogId: ref && ref.catalogId !== undefined ? id(ref.catalogId, 'ref.catalogId') : null };
  }
}

// ─── Authorization ───────────────────────────────────────────────────────────

/** Only host / co-host may change the table (ARCHITECTURE §6). */
export function authorizeSetTable(role: StudioRole) {
  if (role !== 'host' && role !== 'coHost') {
    throw new TableError('permission-denied', 'Only the host or a co-host can change the table.');
  }
}

/**
 * Screen share publisher: the caller by default; a manager may name another
 * uid. The publisher must be on stage (host, co-host or guest).
 */
export function resolveScreenPublisher(
  requested: string | null,
  ctx: { callerUid: string; hostId: string; roles: Record<string, StudioRole> },
): ScreenRef {
  const uid = requested ?? ctx.callerUid;
  const onStage = uid === ctx.hostId || ['coHost', 'guest'].includes(ctx.roles[uid] ?? 'viewer');
  if (!onStage) throw new TableError('failed-precondition', 'The screen publisher must be on stage.');
  return { publisherUid: uid, trackName: TABLE_SCREEN_TRACK };
}

// ─── Goods ───────────────────────────────────────────────────────────────────

/** Owner fields used by the `products` rules (`ownsData`). */
export const OWNER_FIELDS = ['ownerId', 'userId', 'uid', 'createdBy', 'authorId'] as const;

export function productOwnedBy(doc: Record<string, unknown>, uid: string): boolean {
  return OWNER_FIELDS.some((f) => doc[f] === uid);
}

/**
 * Validates a goods ref against the loaded document (`null` = missing).
 * Biz products must belong to the host; stream products exist under the stream.
 */
export function validateGoods(ref: GoodsRef, doc: Record<string, unknown> | null, hostId: string): GoodsRef {
  if (!doc) throw new TableError('not-found', 'That product does not exist.');
  if (ref.source === 'biz' && !productOwnedBy(doc, hostId)) {
    throw new TableError('permission-denied', "That product is not in the host's catalog.");
  }
  return { source: ref.source, productId: ref.productId };
}

// ─── Watch catalog ───────────────────────────────────────────────────────────

export interface WatchCatalogEntry {
  id: string;
  kind: 'match' | 'movie';
  title: string;
  subtitle: string;
  posterUrl: string;
  hlsUrl: string;
  rightsHolder: string;
  territories: string[];
  validFromMs: number | null;
  validUntilMs: number | null;
}

/** Epoch ms from a number, a Firestore Timestamp-like value, an ISO string or a Date. */
export function toMillis(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'string') {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : t;
  }
  if (typeof v === 'object') {
    const o = v as { toMillis?: () => number; seconds?: number; _seconds?: number; nanoseconds?: number };
    if (typeof o.toMillis === 'function') return o.toMillis();
    const s = o.seconds ?? o._seconds;
    if (typeof s === 'number') return s * 1000 + Math.floor((o.nanoseconds ?? 0) / 1e6);
  }
  return null;
}

/** Parses a `live_watch_catalog` document; throws when it is unusable. */
export function parseCatalogEntry(docId: string, d: Record<string, unknown> | null): WatchCatalogEntry {
  if (!d) throw new TableError('not-found', 'That content is not in the watch catalog.');
  const kind = d.kind;
  if (kind !== 'match' && kind !== 'movie') throw new TableError('failed-precondition', 'Catalog entry has no valid kind.');
  const hlsUrl = typeof d.hlsUrl === 'string' ? d.hlsUrl.trim() : '';
  if (!/^https:\/\/\S+$/i.test(hlsUrl)) throw new TableError('failed-precondition', 'Catalog entry has no HTTPS stream.');
  const rightsHolder = typeof d.rightsHolder === 'string' ? d.rightsHolder.trim() : '';
  if (!rightsHolder) throw new TableError('failed-precondition', 'Catalog entry has no rights holder.');
  const territories = Array.isArray(d.territories) ? d.territories.filter((t): t is string => typeof t === 'string') : [];
  return {
    id: docId,
    kind,
    title: typeof d.title === 'string' ? d.title : '',
    subtitle: typeof d.subtitle === 'string' ? d.subtitle : '',
    posterUrl: typeof d.posterUrl === 'string' ? d.posterUrl : '',
    hlsUrl,
    rightsHolder,
    territories,
    validFromMs: toMillis(d.validFrom),
    validUntilMs: toMillis(d.validUntil),
  };
}

/** Throws unless [e] is of kind [mode] and inside its validity window at [nowMs]. */
export function validateCatalogEntry(e: WatchCatalogEntry, mode: 'match' | 'movie', nowMs: number): WatchCatalogEntry {
  if (e.kind !== mode) throw new TableError('failed-precondition', `That entry is a ${e.kind}, not a ${mode}.`);
  if (e.validFromMs !== null && nowMs < e.validFromMs) {
    throw new TableError('failed-precondition', 'That content is not available yet.');
  }
  if (e.validUntilMs !== null && nowMs >= e.validUntilMs) {
    throw new TableError('failed-precondition', 'That content is no longer available.');
  }
  if (e.territories.length === 0) throw new TableError('failed-precondition', 'That content has no licensed territories.');
  return e;
}

/** First entry of [mode] valid at [nowMs] (input order), or null. */
export function pickCatalogEntry(
  docs: Array<{ id: string; data: Record<string, unknown> }>,
  mode: 'match' | 'movie',
  nowMs: number,
): WatchCatalogEntry | null {
  for (const d of docs) {
    try {
      return validateCatalogEntry(parseCatalogEntry(d.id, d.data), mode, nowMs);
    } catch {
      // skip unusable entries
    }
  }
  return null;
}

export const newWatchParty = (catalogId: string, nowMs: number): WatchParty => ({
  catalogId,
  state: 'paused',
  positionMs: 0,
  rate: 1,
  anchorServerMs: nowMs,
});

// ─── Next table state ────────────────────────────────────────────────────────

export const emptyTable = (): TableState => ({ mode: 'goods', goods: null, screen: null, watch: null });

export function normalizeTable(t: Partial<TableState> | undefined | null): TableState {
  return {
    mode: MODES.includes(t?.mode as TableMode) ? (t!.mode as TableMode) : 'goods',
    goods: t?.goods ?? null,
    screen: t?.screen ?? null,
    watch: t?.watch ?? null,
  };
}

export type ResolvedTable =
  | { mode: 'goods'; goods: GoodsRef | null }
  | { mode: 'screen'; screen: ScreenRef }
  | { mode: 'match' | 'movie'; catalogId: string | null };

/**
 * The new table section, or `undefined` when nothing changes. Other modes'
 * refs are kept so switching back restores them. A new watch entry starts a
 * fresh WatchParty paused at 0; re-picking the same entry keeps playback.
 */
export function nextTable(cur: TableState, r: ResolvedTable, nowMs: number): TableState | undefined {
  const c = normalizeTable(cur);
  let next: TableState;
  switch (r.mode) {
    case 'goods':
      next = { ...c, mode: 'goods', goods: r.goods };
      break;
    case 'screen':
      next = { ...c, mode: 'screen', screen: r.screen };
      break;
    default: {
      const keep = c.watch && r.catalogId !== null && c.watch.catalogId === r.catalogId && c.mode === r.mode;
      next = {
        ...c,
        mode: r.mode,
        watch: r.catalogId === null ? null : keep ? c.watch : newWatchParty(r.catalogId, nowMs),
      };
    }
  }
  return JSON.stringify(next) === JSON.stringify(c) ? undefined : next;
}

// ─── lsPlayback ──────────────────────────────────────────────────────────────

export interface PlaybackRequest { state: PlaybackState; positionMs: number; }

export function parsePlayback(data: Record<string, unknown>): PlaybackRequest {
  const state = data.state as PlaybackState;
  if (!PLAYBACK.includes(state)) throw new TableError('invalid-argument', 'state must be playing, paused or ended.');
  const p = data.positionMs;
  if (typeof p !== 'number' || !Number.isFinite(p) || p < 0 || p > MAX_POSITION_MS) {
    throw new TableError('invalid-argument', `positionMs must be between 0 and ${MAX_POSITION_MS}.`);
  }
  return { state, positionMs: Math.round(p) };
}

/** Re-anchors the watch party at [nowMs] (server time). */
export function applyPlayback(cur: TableState, req: PlaybackRequest, nowMs: number): TableState {
  const c = normalizeTable(cur);
  if (!isWatchMode(c.mode)) throw new TableError('failed-precondition', 'Playback only works in Match or Movie mode.');
  if (!c.watch) throw new TableError('failed-precondition', 'Nothing is playing on the table.');
  return {
    ...c,
    watch: { ...c.watch, state: req.state, positionMs: req.positionMs, anchorServerMs: nowMs },
  };
}
