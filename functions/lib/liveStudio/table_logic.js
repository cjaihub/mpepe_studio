"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.emptyTable = exports.newWatchParty = exports.OWNER_FIELDS = exports.isWatchMode = exports.MAX_POSITION_MS = exports.TableError = void 0;
exports.parseSetTable = parseSetTable;
exports.authorizeSetTable = authorizeSetTable;
exports.resolveScreenPublisher = resolveScreenPublisher;
exports.productOwnedBy = productOwnedBy;
exports.validateGoods = validateGoods;
exports.toMillis = toMillis;
exports.parseCatalogEntry = parseCatalogEntry;
exports.validateCatalogEntry = validateCatalogEntry;
exports.pickCatalogEntry = pickCatalogEntry;
exports.normalizeTable = normalizeTable;
exports.nextTable = nextTable;
exports.parsePlayback = parsePlayback;
exports.applyPlayback = applyPlayback;
/**
 * LIVE STUDIO v2 — pure "On the table" logic (workstream #5).
 *
 * No Firestore / LiveKit imports: everything here is unit-tested in
 * __tests__/table_logic.test.ts. table.ts loads documents and calls these.
 */
const contracts_1 = require("./contracts");
class TableError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
}
exports.TableError = TableError;
const MODES = ['goods', 'screen', 'match', 'movie'];
const SOURCES = ['biz', 'stream'];
const PLAYBACK = ['playing', 'paused', 'ended'];
/** 24 h: anything past this is not a real position. */
exports.MAX_POSITION_MS = 24 * 60 * 60 * 1000;
const MAX_ID = 128;
const isWatchMode = (m) => m === 'match' || m === 'movie';
exports.isWatchMode = isWatchMode;
const id = (v, name) => {
    if (typeof v !== 'string' || v.trim().length === 0 || v.length > MAX_ID || v.includes('/')) {
        throw new TableError('invalid-argument', `${name} must be a document id.`);
    }
    return v.trim();
};
/**
 * Parses `{mode, ref?}`. `ref` by mode:
 * - goods: `{source: 'biz'|'stream', productId}` (omit → server picks: Biz first, then stream);
 * - screen: `{publisherUid}` (omit → the caller);
 * - match/movie: `{catalogId}` (omit → first currently valid entry of that kind, or none).
 */
function parseSetTable(data) {
    const mode = data.mode;
    if (!MODES.includes(mode))
        throw new TableError('invalid-argument', `mode must be one of ${MODES.join(', ')}.`);
    const raw = data.ref;
    if (raw !== undefined && raw !== null && (typeof raw !== 'object' || Array.isArray(raw))) {
        throw new TableError('invalid-argument', 'ref must be an object.');
    }
    const ref = (raw !== null && raw !== void 0 ? raw : null);
    switch (mode) {
        case 'goods': {
            if (!ref)
                return { mode, goods: null };
            const source = ref.source;
            if (!SOURCES.includes(source))
                throw new TableError('invalid-argument', 'ref.source must be biz or stream.');
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
function authorizeSetTable(role) {
    if (role !== 'host' && role !== 'coHost') {
        throw new TableError('permission-denied', 'Only the host or a co-host can change the table.');
    }
}
/**
 * Screen share publisher: the caller by default; a manager may name another
 * uid. The publisher must be on stage (host, co-host or guest).
 */
function resolveScreenPublisher(requested, ctx) {
    var _a;
    const uid = requested !== null && requested !== void 0 ? requested : ctx.callerUid;
    const onStage = uid === ctx.hostId || ['coHost', 'guest'].includes((_a = ctx.roles[uid]) !== null && _a !== void 0 ? _a : 'viewer');
    if (!onStage)
        throw new TableError('failed-precondition', 'The screen publisher must be on stage.');
    return { publisherUid: uid, trackName: contracts_1.TABLE_SCREEN_TRACK };
}
// ─── Goods ───────────────────────────────────────────────────────────────────
/** Owner fields used by the `products` rules (`ownsData`). */
exports.OWNER_FIELDS = ['ownerId', 'userId', 'uid', 'createdBy', 'authorId'];
function productOwnedBy(doc, uid) {
    return exports.OWNER_FIELDS.some((f) => doc[f] === uid);
}
/**
 * Validates a goods ref against the loaded document (`null` = missing).
 * Biz products must belong to the host; stream products exist under the stream.
 */
function validateGoods(ref, doc, hostId) {
    if (!doc)
        throw new TableError('not-found', 'That product does not exist.');
    if (ref.source === 'biz' && !productOwnedBy(doc, hostId)) {
        throw new TableError('permission-denied', "That product is not in the host's catalog.");
    }
    return { source: ref.source, productId: ref.productId };
}
/** Epoch ms from a number, a Firestore Timestamp-like value, an ISO string or a Date. */
function toMillis(v) {
    var _a, _b;
    if (v === null || v === undefined)
        return null;
    if (typeof v === 'number' && Number.isFinite(v))
        return v;
    if (v instanceof Date)
        return v.getTime();
    if (typeof v === 'string') {
        const t = Date.parse(v);
        return Number.isNaN(t) ? null : t;
    }
    if (typeof v === 'object') {
        const o = v;
        if (typeof o.toMillis === 'function')
            return o.toMillis();
        const s = (_a = o.seconds) !== null && _a !== void 0 ? _a : o._seconds;
        if (typeof s === 'number')
            return s * 1000 + Math.floor(((_b = o.nanoseconds) !== null && _b !== void 0 ? _b : 0) / 1e6);
    }
    return null;
}
/** Parses a `live_watch_catalog` document; throws when it is unusable. */
function parseCatalogEntry(docId, d) {
    if (!d)
        throw new TableError('not-found', 'That content is not in the watch catalog.');
    const kind = d.kind;
    if (kind !== 'match' && kind !== 'movie')
        throw new TableError('failed-precondition', 'Catalog entry has no valid kind.');
    const hlsUrl = typeof d.hlsUrl === 'string' ? d.hlsUrl.trim() : '';
    if (!/^https:\/\/\S+$/i.test(hlsUrl))
        throw new TableError('failed-precondition', 'Catalog entry has no HTTPS stream.');
    const rightsHolder = typeof d.rightsHolder === 'string' ? d.rightsHolder.trim() : '';
    if (!rightsHolder)
        throw new TableError('failed-precondition', 'Catalog entry has no rights holder.');
    const territories = Array.isArray(d.territories) ? d.territories.filter((t) => typeof t === 'string') : [];
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
function validateCatalogEntry(e, mode, nowMs) {
    if (e.kind !== mode)
        throw new TableError('failed-precondition', `That entry is a ${e.kind}, not a ${mode}.`);
    if (e.validFromMs !== null && nowMs < e.validFromMs) {
        throw new TableError('failed-precondition', 'That content is not available yet.');
    }
    if (e.validUntilMs !== null && nowMs >= e.validUntilMs) {
        throw new TableError('failed-precondition', 'That content is no longer available.');
    }
    if (e.territories.length === 0)
        throw new TableError('failed-precondition', 'That content has no licensed territories.');
    return e;
}
/** First entry of [mode] valid at [nowMs] (input order), or null. */
function pickCatalogEntry(docs, mode, nowMs) {
    for (const d of docs) {
        try {
            return validateCatalogEntry(parseCatalogEntry(d.id, d.data), mode, nowMs);
        }
        catch (_a) {
            // skip unusable entries
        }
    }
    return null;
}
const newWatchParty = (catalogId, nowMs) => ({
    catalogId,
    state: 'paused',
    positionMs: 0,
    rate: 1,
    anchorServerMs: nowMs,
});
exports.newWatchParty = newWatchParty;
// ─── Next table state ────────────────────────────────────────────────────────
const emptyTable = () => ({ mode: 'goods', goods: null, screen: null, watch: null });
exports.emptyTable = emptyTable;
function normalizeTable(t) {
    var _a, _b, _c;
    return {
        mode: MODES.includes(t === null || t === void 0 ? void 0 : t.mode) ? t.mode : 'goods',
        goods: (_a = t === null || t === void 0 ? void 0 : t.goods) !== null && _a !== void 0 ? _a : null,
        screen: (_b = t === null || t === void 0 ? void 0 : t.screen) !== null && _b !== void 0 ? _b : null,
        watch: (_c = t === null || t === void 0 ? void 0 : t.watch) !== null && _c !== void 0 ? _c : null,
    };
}
/**
 * The new table section, or `undefined` when nothing changes. Other modes'
 * refs are kept so switching back restores them. A new watch entry starts a
 * fresh WatchParty paused at 0; re-picking the same entry keeps playback.
 */
function nextTable(cur, r, nowMs) {
    const c = normalizeTable(cur);
    let next;
    switch (r.mode) {
        case 'goods':
            next = Object.assign(Object.assign({}, c), { mode: 'goods', goods: r.goods });
            break;
        case 'screen':
            next = Object.assign(Object.assign({}, c), { mode: 'screen', screen: r.screen });
            break;
        default: {
            const keep = c.watch && r.catalogId !== null && c.watch.catalogId === r.catalogId && c.mode === r.mode;
            next = Object.assign(Object.assign({}, c), { mode: r.mode, watch: r.catalogId === null ? null : keep ? c.watch : (0, exports.newWatchParty)(r.catalogId, nowMs) });
        }
    }
    return JSON.stringify(next) === JSON.stringify(c) ? undefined : next;
}
function parsePlayback(data) {
    const state = data.state;
    if (!PLAYBACK.includes(state))
        throw new TableError('invalid-argument', 'state must be playing, paused or ended.');
    const p = data.positionMs;
    if (typeof p !== 'number' || !Number.isFinite(p) || p < 0 || p > exports.MAX_POSITION_MS) {
        throw new TableError('invalid-argument', `positionMs must be between 0 and ${exports.MAX_POSITION_MS}.`);
    }
    return { state, positionMs: Math.round(p) };
}
/** Re-anchors the watch party at [nowMs] (server time). */
function applyPlayback(cur, req, nowMs) {
    const c = normalizeTable(cur);
    if (!(0, exports.isWatchMode)(c.mode))
        throw new TableError('failed-precondition', 'Playback only works in Match or Movie mode.');
    if (!c.watch)
        throw new TableError('failed-precondition', 'Nothing is playing on the table.');
    return Object.assign(Object.assign({}, c), { watch: Object.assign(Object.assign({}, c.watch), { state: req.state, positionMs: req.positionMs, anchorServerMs: nowMs }) });
}
//# sourceMappingURL=table_logic.js.map