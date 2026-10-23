"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsPlayback = exports.lsSetTable = void 0;
/**
 * LIVE STUDIO v2 — "On the table" callables (workstream #5, ARCHITECTURE §9).
 *
 * - `lsSetTable({streamId, mode, ref?})` → `{ok, seq, table}`
 * - `lsPlayback({streamId, state, positionMs})` → `{ok, seq, table}`
 *
 * Both are host/co-host only and write the `table` section through
 * `patchState` (one transaction + one `state.patch` broadcast). Pure
 * validation lives in table_logic.ts.
 *
 * Watch content comes ONLY from the admin-curated `live_watch_catalog`
 * (ARCHITECTURE Q7). No free-form URLs are accepted.
 */
const https_1 = require("firebase-functions/v2/https");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const table_logic_1 = require("./table_logic");
const toHttps = (e) => {
    if (e instanceof table_logic_1.TableError)
        throw new https_1.HttpsError(e.code, e.message);
    throw e;
};
const guard = (fn) => {
    try {
        return fn();
    }
    catch (e) {
        return toHttps(e);
    }
};
async function loadRoles(streamId) {
    const snap = await (0, shared_1.db)().collection(contracts_1.Paths.members(streamId)).get();
    const roles = {};
    snap.forEach((d) => {
        var _a;
        roles[d.id] = (_a = d.data().role) !== null && _a !== void 0 ? _a : 'viewer';
    });
    return roles;
}
/** Goods per decision Q5: the host's Biz products first, then the stream list. */
async function defaultGoods(streamId, hostId) {
    const biz = await (0, shared_1.db)().collection('products').where('ownerId', '==', hostId).limit(1).get();
    if (!biz.empty)
        return { source: 'biz', productId: biz.docs[0].id };
    const own = await (0, shared_1.db)().collection(`${contracts_1.Paths.streams}/${streamId}/products`).orderBy('sortOrder').limit(1).get();
    if (!own.empty)
        return { source: 'stream', productId: own.docs[0].id };
    return null;
}
async function loadProduct(streamId, ref) {
    const path = ref.source === 'biz'
        ? `products/${ref.productId}`
        : `${contracts_1.Paths.streams}/${streamId}/products/${ref.productId}`;
    const snap = await (0, shared_1.db)().doc(path).get();
    return snap.exists ? snap.data() : null;
}
exports.lsSetTable = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    var _b, _c;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const data = ((_b = req.data) !== null && _b !== void 0 ? _b : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const request = guard(() => (0, table_logic_1.parseSetTable)(data));
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    const role = await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    guard(() => (0, table_logic_1.authorizeSetTable)(role));
    await (0, shared_1.rateLimit)(streamId, uid, 'table', 5, 1000);
    const nowMs = Date.now();
    let resolved;
    switch (request.mode) {
        case 'goods': {
            if (request.goods) {
                const doc = await loadProduct(streamId, request.goods);
                resolved = { mode: 'goods', goods: guard(() => (0, table_logic_1.validateGoods)(request.goods, doc, state.hostId)) };
            }
            else {
                resolved = { mode: 'goods', goods: await defaultGoods(streamId, state.hostId) };
            }
            break;
        }
        case 'screen': {
            const roles = await loadRoles(streamId);
            const screen = guard(() => (0, table_logic_1.resolveScreenPublisher)(request.publisherUid, { callerUid: uid, hostId: state.hostId, roles }));
            resolved = { mode: 'screen', screen };
            break;
        }
        default: {
            const mode = request.mode;
            if (request.catalogId) {
                const snap = await (0, shared_1.db)().doc(`${contracts_1.Paths.watchCatalog}/${request.catalogId}`).get();
                const entry = guard(() => (0, table_logic_1.validateCatalogEntry)((0, table_logic_1.parseCatalogEntry)(request.catalogId, snap.exists ? snap.data() : null), mode, nowMs));
                resolved = { mode, catalogId: entry.id };
            }
            else {
                const q = await (0, shared_1.db)().collection(contracts_1.Paths.watchCatalog).where('kind', '==', mode).limit(25).get();
                const entry = (0, table_logic_1.pickCatalogEntry)(q.docs.map((d) => ({ id: d.id, data: d.data() })), mode, nowMs);
                resolved = { mode, catalogId: (_c = entry === null || entry === void 0 ? void 0 : entry.id) !== null && _c !== void 0 ? _c : null };
            }
        }
    }
    const next = await (0, shared_1.patchState)(streamId, 'table', (s) => (0, table_logic_1.nextTable)((0, table_logic_1.normalizeTable)(s.table), resolved, Date.now()));
    const finalState = next !== null && next !== void 0 ? next : (await (0, shared_1.loadState)(streamId));
    return { ok: true, seq: finalState.seq, table: (0, table_logic_1.normalizeTable)(finalState.table) };
});
exports.lsPlayback = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    var _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const data = ((_b = req.data) !== null && _b !== void 0 ? _b : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const request = guard(() => (0, table_logic_1.parsePlayback)(data));
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    await (0, shared_1.rateLimit)(streamId, uid, 'playback', 5, 1000);
    const next = await (0, shared_1.patchState)(streamId, 'table', (s) => guard(() => (0, table_logic_1.applyPlayback)((0, table_logic_1.normalizeTable)(s.table), request, Date.now())));
    const finalState = next !== null && next !== void 0 ? next : (await (0, shared_1.loadState)(streamId));
    return { ok: true, seq: finalState.seq, table: (0, table_logic_1.normalizeTable)(finalState.table) };
});
//# sourceMappingURL=table.js.map