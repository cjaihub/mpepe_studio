"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert/strict"));
const table_logic_1 = require("../table_logic");
const NOW = 1700000000000;
const rejects = (fn, code) => assert.throws(fn, (e) => e instanceof table_logic_1.TableError && e.code === code);
const entry = (over = {}) => (Object.assign({ kind: 'match', title: 'Home vs Away', subtitle: 'Football', posterUrl: 'https://cdn/p.jpg', hlsUrl: 'https://cdn/m.m3u8', rightsHolder: 'League', territories: ['TZ', 'KE'], validFrom: NOW - 1000, validUntil: NOW + 1000 }, over));
// ─── parseSetTable ──────────────────────────────────────────────────────────
(0, node_test_1.test)('parseSetTable: modes and refs', () => {
    assert.deepEqual((0, table_logic_1.parseSetTable)({ mode: 'goods' }), { mode: 'goods', goods: null });
    assert.deepEqual((0, table_logic_1.parseSetTable)({ mode: 'goods', ref: { source: 'stream', productId: ' p1 ' } }), { mode: 'goods', goods: { source: 'stream', productId: 'p1' } });
    assert.deepEqual((0, table_logic_1.parseSetTable)({ mode: 'screen' }), { mode: 'screen', publisherUid: null });
    assert.deepEqual((0, table_logic_1.parseSetTable)({ mode: 'screen', ref: { publisherUid: 'g1' } }), { mode: 'screen', publisherUid: 'g1' });
    assert.deepEqual((0, table_logic_1.parseSetTable)({ mode: 'movie', ref: { catalogId: 'c1' } }), { mode: 'movie', catalogId: 'c1' });
    assert.deepEqual((0, table_logic_1.parseSetTable)({ mode: 'match', ref: null }), { mode: 'match', catalogId: null });
});
(0, node_test_1.test)('parseSetTable: rejects bad input (no free-form URLs)', () => {
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'tv' }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'goods', ref: 'x' }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'goods', ref: [] }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'goods', ref: { source: 'ebay', productId: 'p' } }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'goods', ref: { source: 'biz', productId: '' } }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'goods', ref: { source: 'biz', productId: 'a/b' } }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'movie', ref: { catalogId: 'https://evil/x.m3u8' } }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parseSetTable)({ mode: 'movie', ref: { catalogId: 'x'.repeat(129) } }), 'invalid-argument');
});
// ─── authorization / screen ──────────────────────────────────────────────────
(0, node_test_1.test)('authorizeSetTable: managers only', () => {
    (0, table_logic_1.authorizeSetTable)('host');
    (0, table_logic_1.authorizeSetTable)('coHost');
    rejects(() => (0, table_logic_1.authorizeSetTable)('guest'), 'permission-denied');
    rejects(() => (0, table_logic_1.authorizeSetTable)('viewer'), 'permission-denied');
});
(0, node_test_1.test)('resolveScreenPublisher: caller by default, must be on stage', () => {
    const roles = { c1: 'coHost', g1: 'guest', v1: 'viewer' };
    const ctx = (callerUid) => ({ callerUid, hostId: 'host', roles });
    assert.deepEqual((0, table_logic_1.resolveScreenPublisher)(null, ctx('host')), { publisherUid: 'host', trackName: 'table_screen' });
    assert.equal((0, table_logic_1.resolveScreenPublisher)(null, ctx('c1')).publisherUid, 'c1');
    assert.equal((0, table_logic_1.resolveScreenPublisher)('g1', ctx('host')).publisherUid, 'g1');
    assert.equal((0, table_logic_1.resolveScreenPublisher)('host', ctx('c1')).publisherUid, 'host');
    rejects(() => (0, table_logic_1.resolveScreenPublisher)('v1', ctx('host')), 'failed-precondition');
    rejects(() => (0, table_logic_1.resolveScreenPublisher)('nobody', ctx('host')), 'failed-precondition');
});
// ─── goods ──────────────────────────────────────────────────────────────────
(0, node_test_1.test)('productOwnedBy checks every owner field', () => {
    for (const f of ['ownerId', 'userId', 'uid', 'createdBy', 'authorId']) {
        assert.equal((0, table_logic_1.productOwnedBy)({ [f]: 'host' }, 'host'), true, f);
    }
    assert.equal((0, table_logic_1.productOwnedBy)({ ownerId: 'other' }, 'host'), false);
    assert.equal((0, table_logic_1.productOwnedBy)({}, 'host'), false);
});
(0, node_test_1.test)('validateGoods: biz must be the host\'s, stream must exist', () => {
    const biz = { source: 'biz', productId: 'p1' };
    assert.deepEqual((0, table_logic_1.validateGoods)(biz, { ownerId: 'host', name: 'Mic' }, 'host'), biz);
    rejects(() => (0, table_logic_1.validateGoods)(biz, { ownerId: 'someone' }, 'host'), 'permission-denied');
    rejects(() => (0, table_logic_1.validateGoods)(biz, null, 'host'), 'not-found');
    const stream = { source: 'stream', productId: 's1' };
    assert.deepEqual((0, table_logic_1.validateGoods)(stream, { name: 'Tee' }, 'host'), stream);
    rejects(() => (0, table_logic_1.validateGoods)(stream, null, 'host'), 'not-found');
});
// ─── catalog ────────────────────────────────────────────────────────────────
(0, node_test_1.test)('toMillis handles numbers, timestamps, ISO and Date', () => {
    assert.equal((0, table_logic_1.toMillis)(5), 5);
    assert.equal((0, table_logic_1.toMillis)({ toMillis: () => 7 }), 7);
    assert.equal((0, table_logic_1.toMillis)({ seconds: 2, nanoseconds: 5000000 }), 2005);
    assert.equal((0, table_logic_1.toMillis)({ _seconds: 3 }), 3000);
    assert.equal((0, table_logic_1.toMillis)('1970-01-01T00:00:01.000Z'), 1000);
    assert.equal((0, table_logic_1.toMillis)(new Date(9)), 9);
    assert.equal((0, table_logic_1.toMillis)(null), null);
    assert.equal((0, table_logic_1.toMillis)('nope'), null);
    assert.equal((0, table_logic_1.toMillis)(Number.NaN), null);
});
(0, node_test_1.test)('parseCatalogEntry requires kind, https HLS and a rights holder', () => {
    const e = (0, table_logic_1.parseCatalogEntry)('c1', entry());
    assert.equal(e.id, 'c1');
    assert.equal(e.kind, 'match');
    assert.deepEqual(e.territories, ['TZ', 'KE']);
    assert.equal(e.validFromMs, NOW - 1000);
    rejects(() => (0, table_logic_1.parseCatalogEntry)('c1', null), 'not-found');
    rejects(() => (0, table_logic_1.parseCatalogEntry)('c1', entry({ kind: 'tv' })), 'failed-precondition');
    rejects(() => (0, table_logic_1.parseCatalogEntry)('c1', entry({ hlsUrl: 'http://cdn/m.m3u8' })), 'failed-precondition');
    rejects(() => (0, table_logic_1.parseCatalogEntry)('c1', entry({ hlsUrl: '' })), 'failed-precondition');
    rejects(() => (0, table_logic_1.parseCatalogEntry)('c1', entry({ rightsHolder: ' ' })), 'failed-precondition');
});
(0, node_test_1.test)('validateCatalogEntry: kind, validity window, territories', () => {
    const ok = (0, table_logic_1.parseCatalogEntry)('c1', entry());
    assert.equal((0, table_logic_1.validateCatalogEntry)(ok, 'match', NOW).id, 'c1');
    rejects(() => (0, table_logic_1.validateCatalogEntry)(ok, 'movie', NOW), 'failed-precondition');
    rejects(() => (0, table_logic_1.validateCatalogEntry)(ok, 'match', NOW - 1001), 'failed-precondition'); // not yet valid
    rejects(() => (0, table_logic_1.validateCatalogEntry)(ok, 'match', NOW + 1000), 'failed-precondition'); // expired (exclusive)
    assert.ok((0, table_logic_1.validateCatalogEntry)(ok, 'match', NOW - 1000)); // validFrom inclusive
    const open = (0, table_logic_1.parseCatalogEntry)('c2', entry({ validFrom: null, validUntil: undefined }));
    assert.ok((0, table_logic_1.validateCatalogEntry)(open, 'match', 0));
    const noTerr = (0, table_logic_1.parseCatalogEntry)('c3', entry({ territories: [] }));
    rejects(() => (0, table_logic_1.validateCatalogEntry)(noTerr, 'match', NOW), 'failed-precondition');
});
(0, node_test_1.test)('pickCatalogEntry skips expired / wrong-kind / broken entries', () => {
    var _a, _b;
    const docs = [
        { id: 'old', data: entry({ validUntil: NOW - 1 }) },
        { id: 'movie', data: entry({ kind: 'movie' }) },
        { id: 'broken', data: entry({ hlsUrl: 'ftp://x' }) },
        { id: 'good', data: entry() },
    ];
    assert.equal((_a = (0, table_logic_1.pickCatalogEntry)(docs, 'match', NOW)) === null || _a === void 0 ? void 0 : _a.id, 'good');
    assert.equal((_b = (0, table_logic_1.pickCatalogEntry)(docs, 'movie', NOW)) === null || _b === void 0 ? void 0 : _b.id, 'movie');
    assert.equal((0, table_logic_1.pickCatalogEntry)([], 'match', NOW), null);
});
// ─── nextTable ──────────────────────────────────────────────────────────────
(0, node_test_1.test)('nextTable: goods / screen keep the other refs', () => {
    const cur = Object.assign(Object.assign({}, (0, table_logic_1.emptyTable)()), { watch: (0, table_logic_1.newWatchParty)('c1', 5) });
    const g = (0, table_logic_1.nextTable)(cur, { mode: 'goods', goods: { source: 'biz', productId: 'p1' } }, NOW);
    assert.equal(g.mode, 'goods');
    assert.deepEqual(g.goods, { source: 'biz', productId: 'p1' });
    assert.deepEqual(g.watch, cur.watch);
    const s = (0, table_logic_1.nextTable)(g, { mode: 'screen', screen: { publisherUid: 'host', trackName: 'table_screen' } }, NOW);
    assert.equal(s.mode, 'screen');
    assert.deepEqual(s.goods, g.goods);
    assert.equal((0, table_logic_1.nextTable)(s, { mode: 'screen', screen: { publisherUid: 'host', trackName: 'table_screen' } }, NOW), undefined);
});
(0, node_test_1.test)('nextTable: new watch entry starts paused at 0 anchored now', () => {
    const t = (0, table_logic_1.nextTable)((0, table_logic_1.emptyTable)(), { mode: 'match', catalogId: 'c1' }, NOW);
    assert.equal(t.mode, 'match');
    assert.deepEqual(t.watch, { catalogId: 'c1', state: 'paused', positionMs: 0, rate: 1, anchorServerMs: NOW });
});
(0, node_test_1.test)('nextTable: same entry and mode is a no-op; other mode restarts', () => {
    const playing = Object.assign(Object.assign({}, (0, table_logic_1.emptyTable)()), { mode: 'match', watch: { catalogId: 'c1', state: 'playing', positionMs: 9000, rate: 1, anchorServerMs: 1 } });
    assert.equal((0, table_logic_1.nextTable)(playing, { mode: 'match', catalogId: 'c1' }, NOW), undefined);
    const movie = (0, table_logic_1.nextTable)(playing, { mode: 'movie', catalogId: 'c1' }, NOW);
    assert.equal(movie.watch.positionMs, 0);
    assert.equal(movie.watch.state, 'paused');
});
(0, node_test_1.test)('nextTable: empty catalog sets the mode with no watch party', () => {
    const t = (0, table_logic_1.nextTable)((0, table_logic_1.emptyTable)(), { mode: 'movie', catalogId: null }, NOW);
    assert.equal(t.mode, 'movie');
    assert.equal(t.watch, null);
});
(0, node_test_1.test)('normalizeTable fills missing fields', () => {
    assert.deepEqual((0, table_logic_1.normalizeTable)(undefined), (0, table_logic_1.emptyTable)());
    assert.deepEqual((0, table_logic_1.normalizeTable)({ mode: 'bogus' }), (0, table_logic_1.emptyTable)());
    assert.equal((0, table_logic_1.normalizeTable)({ mode: 'movie' }).mode, 'movie');
});
// ─── playback ────────────────────────────────────────────────────────────────
(0, node_test_1.test)('parsePlayback validates state and position', () => {
    assert.deepEqual((0, table_logic_1.parsePlayback)({ state: 'playing', positionMs: 1234.6 }), { state: 'playing', positionMs: 1235 });
    assert.deepEqual((0, table_logic_1.parsePlayback)({ state: 'ended', positionMs: 0 }), { state: 'ended', positionMs: 0 });
    rejects(() => (0, table_logic_1.parsePlayback)({ state: 'rewind', positionMs: 0 }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parsePlayback)({ state: 'paused', positionMs: -1 }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parsePlayback)({ state: 'paused', positionMs: '5' }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parsePlayback)({ state: 'paused', positionMs: table_logic_1.MAX_POSITION_MS + 1 }), 'invalid-argument');
    rejects(() => (0, table_logic_1.parsePlayback)({ state: 'paused', positionMs: Infinity }), 'invalid-argument');
});
(0, node_test_1.test)('applyPlayback re-anchors at server now and keeps rate/catalog', () => {
    const cur = Object.assign(Object.assign({}, (0, table_logic_1.emptyTable)()), { mode: 'movie', watch: { catalogId: 'c9', state: 'paused', positionMs: 0, rate: 1.5, anchorServerMs: 1 } });
    const t = (0, table_logic_1.applyPlayback)(cur, { state: 'playing', positionMs: 4000 }, NOW);
    assert.deepEqual(t.watch, { catalogId: 'c9', state: 'playing', positionMs: 4000, rate: 1.5, anchorServerMs: NOW });
    assert.equal(t.mode, 'movie');
});
(0, node_test_1.test)('applyPlayback only in watch modes with a party', () => {
    rejects(() => (0, table_logic_1.applyPlayback)((0, table_logic_1.emptyTable)(), { state: 'playing', positionMs: 0 }, NOW), 'failed-precondition');
    rejects(() => (0, table_logic_1.applyPlayback)(Object.assign(Object.assign({}, (0, table_logic_1.emptyTable)()), { mode: 'screen', watch: (0, table_logic_1.newWatchParty)('c', 0) }), { state: 'playing', positionMs: 0 }, NOW), 'failed-precondition');
    rejects(() => (0, table_logic_1.applyPlayback)(Object.assign(Object.assign({}, (0, table_logic_1.emptyTable)()), { mode: 'match' }), { state: 'playing', positionMs: 0 }, NOW), 'failed-precondition');
});
//# sourceMappingURL=table_logic.test.js.map