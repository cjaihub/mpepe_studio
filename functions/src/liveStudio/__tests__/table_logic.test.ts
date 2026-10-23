import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { StudioRole, TableState } from '../contracts';
import {
  MAX_POSITION_MS,
  TableError,
  applyPlayback,
  authorizeSetTable,
  emptyTable,
  newWatchParty,
  nextTable,
  normalizeTable,
  parseCatalogEntry,
  parsePlayback,
  parseSetTable,
  pickCatalogEntry,
  productOwnedBy,
  resolveScreenPublisher,
  toMillis,
  validateCatalogEntry,
  validateGoods,
} from '../table_logic';

const NOW = 1_700_000_000_000;
const rejects = (fn: () => unknown, code: string) =>
  assert.throws(fn, (e: unknown) => e instanceof TableError && e.code === code);

const entry = (over: Record<string, unknown> = {}) => ({
  kind: 'match',
  title: 'Home vs Away',
  subtitle: 'Football',
  posterUrl: 'https://cdn/p.jpg',
  hlsUrl: 'https://cdn/m.m3u8',
  rightsHolder: 'League',
  territories: ['TZ', 'KE'],
  validFrom: NOW - 1000,
  validUntil: NOW + 1000,
  ...over,
});

// ─── parseSetTable ──────────────────────────────────────────────────────────

test('parseSetTable: modes and refs', () => {
  assert.deepEqual(parseSetTable({ mode: 'goods' }), { mode: 'goods', goods: null });
  assert.deepEqual(parseSetTable({ mode: 'goods', ref: { source: 'stream', productId: ' p1 ' } }),
    { mode: 'goods', goods: { source: 'stream', productId: 'p1' } });
  assert.deepEqual(parseSetTable({ mode: 'screen' }), { mode: 'screen', publisherUid: null });
  assert.deepEqual(parseSetTable({ mode: 'screen', ref: { publisherUid: 'g1' } }), { mode: 'screen', publisherUid: 'g1' });
  assert.deepEqual(parseSetTable({ mode: 'movie', ref: { catalogId: 'c1' } }), { mode: 'movie', catalogId: 'c1' });
  assert.deepEqual(parseSetTable({ mode: 'match', ref: null }), { mode: 'match', catalogId: null });
});

test('parseSetTable: rejects bad input (no free-form URLs)', () => {
  rejects(() => parseSetTable({ mode: 'tv' }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'goods', ref: 'x' }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'goods', ref: [] }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'goods', ref: { source: 'ebay', productId: 'p' } }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'goods', ref: { source: 'biz', productId: '' } }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'goods', ref: { source: 'biz', productId: 'a/b' } }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'movie', ref: { catalogId: 'https://evil/x.m3u8' } }), 'invalid-argument');
  rejects(() => parseSetTable({ mode: 'movie', ref: { catalogId: 'x'.repeat(129) } }), 'invalid-argument');
});

// ─── authorization / screen ──────────────────────────────────────────────────

test('authorizeSetTable: managers only', () => {
  authorizeSetTable('host');
  authorizeSetTable('coHost');
  rejects(() => authorizeSetTable('guest'), 'permission-denied');
  rejects(() => authorizeSetTable('viewer'), 'permission-denied');
});

test('resolveScreenPublisher: caller by default, must be on stage', () => {
  const roles: Record<string, StudioRole> = { c1: 'coHost', g1: 'guest', v1: 'viewer' };
  const ctx = (callerUid: string) => ({ callerUid, hostId: 'host', roles });
  assert.deepEqual(resolveScreenPublisher(null, ctx('host')), { publisherUid: 'host', trackName: 'table_screen' });
  assert.equal(resolveScreenPublisher(null, ctx('c1')).publisherUid, 'c1');
  assert.equal(resolveScreenPublisher('g1', ctx('host')).publisherUid, 'g1');
  assert.equal(resolveScreenPublisher('host', ctx('c1')).publisherUid, 'host');
  rejects(() => resolveScreenPublisher('v1', ctx('host')), 'failed-precondition');
  rejects(() => resolveScreenPublisher('nobody', ctx('host')), 'failed-precondition');
});

// ─── goods ──────────────────────────────────────────────────────────────────

test('productOwnedBy checks every owner field', () => {
  for (const f of ['ownerId', 'userId', 'uid', 'createdBy', 'authorId']) {
    assert.equal(productOwnedBy({ [f]: 'host' }, 'host'), true, f);
  }
  assert.equal(productOwnedBy({ ownerId: 'other' }, 'host'), false);
  assert.equal(productOwnedBy({}, 'host'), false);
});

test('validateGoods: biz must be the host\'s, stream must exist', () => {
  const biz = { source: 'biz' as const, productId: 'p1' };
  assert.deepEqual(validateGoods(biz, { ownerId: 'host', name: 'Mic' }, 'host'), biz);
  rejects(() => validateGoods(biz, { ownerId: 'someone' }, 'host'), 'permission-denied');
  rejects(() => validateGoods(biz, null, 'host'), 'not-found');
  const stream = { source: 'stream' as const, productId: 's1' };
  assert.deepEqual(validateGoods(stream, { name: 'Tee' }, 'host'), stream);
  rejects(() => validateGoods(stream, null, 'host'), 'not-found');
});

// ─── catalog ────────────────────────────────────────────────────────────────

test('toMillis handles numbers, timestamps, ISO and Date', () => {
  assert.equal(toMillis(5), 5);
  assert.equal(toMillis({ toMillis: () => 7 }), 7);
  assert.equal(toMillis({ seconds: 2, nanoseconds: 5_000_000 }), 2005);
  assert.equal(toMillis({ _seconds: 3 }), 3000);
  assert.equal(toMillis('1970-01-01T00:00:01.000Z'), 1000);
  assert.equal(toMillis(new Date(9)), 9);
  assert.equal(toMillis(null), null);
  assert.equal(toMillis('nope'), null);
  assert.equal(toMillis(Number.NaN), null);
});

test('parseCatalogEntry requires kind, https HLS and a rights holder', () => {
  const e = parseCatalogEntry('c1', entry());
  assert.equal(e.id, 'c1');
  assert.equal(e.kind, 'match');
  assert.deepEqual(e.territories, ['TZ', 'KE']);
  assert.equal(e.validFromMs, NOW - 1000);
  rejects(() => parseCatalogEntry('c1', null), 'not-found');
  rejects(() => parseCatalogEntry('c1', entry({ kind: 'tv' })), 'failed-precondition');
  rejects(() => parseCatalogEntry('c1', entry({ hlsUrl: 'http://cdn/m.m3u8' })), 'failed-precondition');
  rejects(() => parseCatalogEntry('c1', entry({ hlsUrl: '' })), 'failed-precondition');
  rejects(() => parseCatalogEntry('c1', entry({ rightsHolder: ' ' })), 'failed-precondition');
});

test('validateCatalogEntry: kind, validity window, territories', () => {
  const ok = parseCatalogEntry('c1', entry());
  assert.equal(validateCatalogEntry(ok, 'match', NOW).id, 'c1');
  rejects(() => validateCatalogEntry(ok, 'movie', NOW), 'failed-precondition');
  rejects(() => validateCatalogEntry(ok, 'match', NOW - 1001), 'failed-precondition'); // not yet valid
  rejects(() => validateCatalogEntry(ok, 'match', NOW + 1000), 'failed-precondition'); // expired (exclusive)
  assert.ok(validateCatalogEntry(ok, 'match', NOW - 1000)); // validFrom inclusive
  const open = parseCatalogEntry('c2', entry({ validFrom: null, validUntil: undefined }));
  assert.ok(validateCatalogEntry(open, 'match', 0));
  const noTerr = parseCatalogEntry('c3', entry({ territories: [] }));
  rejects(() => validateCatalogEntry(noTerr, 'match', NOW), 'failed-precondition');
});

test('pickCatalogEntry skips expired / wrong-kind / broken entries', () => {
  const docs = [
    { id: 'old', data: entry({ validUntil: NOW - 1 }) },
    { id: 'movie', data: entry({ kind: 'movie' }) },
    { id: 'broken', data: entry({ hlsUrl: 'ftp://x' }) },
    { id: 'good', data: entry() },
  ];
  assert.equal(pickCatalogEntry(docs, 'match', NOW)?.id, 'good');
  assert.equal(pickCatalogEntry(docs, 'movie', NOW)?.id, 'movie');
  assert.equal(pickCatalogEntry([], 'match', NOW), null);
});

// ─── nextTable ──────────────────────────────────────────────────────────────

test('nextTable: goods / screen keep the other refs', () => {
  const cur: TableState = { ...emptyTable(), watch: newWatchParty('c1', 5) };
  const g = nextTable(cur, { mode: 'goods', goods: { source: 'biz', productId: 'p1' } }, NOW)!;
  assert.equal(g.mode, 'goods');
  assert.deepEqual(g.goods, { source: 'biz', productId: 'p1' });
  assert.deepEqual(g.watch, cur.watch);
  const s = nextTable(g, { mode: 'screen', screen: { publisherUid: 'host', trackName: 'table_screen' } }, NOW)!;
  assert.equal(s.mode, 'screen');
  assert.deepEqual(s.goods, g.goods);
  assert.equal(nextTable(s, { mode: 'screen', screen: { publisherUid: 'host', trackName: 'table_screen' } }, NOW), undefined);
});

test('nextTable: new watch entry starts paused at 0 anchored now', () => {
  const t = nextTable(emptyTable(), { mode: 'match', catalogId: 'c1' }, NOW)!;
  assert.equal(t.mode, 'match');
  assert.deepEqual(t.watch, { catalogId: 'c1', state: 'paused', positionMs: 0, rate: 1, anchorServerMs: NOW });
});

test('nextTable: same entry and mode is a no-op; other mode restarts', () => {
  const playing: TableState = {
    ...emptyTable(), mode: 'match',
    watch: { catalogId: 'c1', state: 'playing', positionMs: 9000, rate: 1, anchorServerMs: 1 },
  };
  assert.equal(nextTable(playing, { mode: 'match', catalogId: 'c1' }, NOW), undefined);
  const movie = nextTable(playing, { mode: 'movie', catalogId: 'c1' }, NOW)!;
  assert.equal(movie.watch!.positionMs, 0);
  assert.equal(movie.watch!.state, 'paused');
});

test('nextTable: empty catalog sets the mode with no watch party', () => {
  const t = nextTable(emptyTable(), { mode: 'movie', catalogId: null }, NOW)!;
  assert.equal(t.mode, 'movie');
  assert.equal(t.watch, null);
});

test('normalizeTable fills missing fields', () => {
  assert.deepEqual(normalizeTable(undefined), emptyTable());
  assert.deepEqual(normalizeTable({ mode: 'bogus' as never }), emptyTable());
  assert.equal(normalizeTable({ mode: 'movie' }).mode, 'movie');
});

// ─── playback ────────────────────────────────────────────────────────────────

test('parsePlayback validates state and position', () => {
  assert.deepEqual(parsePlayback({ state: 'playing', positionMs: 1234.6 }), { state: 'playing', positionMs: 1235 });
  assert.deepEqual(parsePlayback({ state: 'ended', positionMs: 0 }), { state: 'ended', positionMs: 0 });
  rejects(() => parsePlayback({ state: 'rewind', positionMs: 0 }), 'invalid-argument');
  rejects(() => parsePlayback({ state: 'paused', positionMs: -1 }), 'invalid-argument');
  rejects(() => parsePlayback({ state: 'paused', positionMs: '5' }), 'invalid-argument');
  rejects(() => parsePlayback({ state: 'paused', positionMs: MAX_POSITION_MS + 1 }), 'invalid-argument');
  rejects(() => parsePlayback({ state: 'paused', positionMs: Infinity }), 'invalid-argument');
});

test('applyPlayback re-anchors at server now and keeps rate/catalog', () => {
  const cur: TableState = {
    ...emptyTable(), mode: 'movie',
    watch: { catalogId: 'c9', state: 'paused', positionMs: 0, rate: 1.5, anchorServerMs: 1 },
  };
  const t = applyPlayback(cur, { state: 'playing', positionMs: 4000 }, NOW);
  assert.deepEqual(t.watch, { catalogId: 'c9', state: 'playing', positionMs: 4000, rate: 1.5, anchorServerMs: NOW });
  assert.equal(t.mode, 'movie');
});

test('applyPlayback only in watch modes with a party', () => {
  rejects(() => applyPlayback(emptyTable(), { state: 'playing', positionMs: 0 }, NOW), 'failed-precondition');
  rejects(() => applyPlayback({ ...emptyTable(), mode: 'screen', watch: newWatchParty('c', 0) },
    { state: 'playing', positionMs: 0 }, NOW), 'failed-precondition');
  rejects(() => applyPlayback({ ...emptyTable(), mode: 'match' }, { state: 'playing', positionMs: 0 }, NOW),
    'failed-precondition');
});
