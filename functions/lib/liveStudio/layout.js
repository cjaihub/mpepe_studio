"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsSetLayout = void 0;
/**
 * LIVE STUDIO v2 — `lsSetLayout(streamId, op, args)` (ARCHITECTURE §5, §8).
 *
 * ops: swap(index) · pin(uid) · unpin · setMode(mode) · rotateIn(uid, index)
 * · autoPromote(uid). Pure transitions live in layout_logic.ts.
 *
 * Writes go through `patchState`, which mutates ONE top-level section per
 * transaction and broadcasts one `state.patch`. `setMode` changes
 * `settings.speakerMode` (section 'settings') and, for hostPinned, may also
 * bring the host back to the center (section 'stage'). Those are two
 * patchState calls: settings first, then stage. Each is atomic on its own and
 * bumps `seq`, so clients apply two ordered patches; the stage transaction
 * re-reads state and re-derives the move, so a concurrent change between the
 * two can never be overwritten with stale data. A combined helper would need
 * an integrator change to shared.ts; this keeps shared.ts untouched.
 *
 * Viewer taps never call this (they open a local pop-out, ARCHITECTURE Q3).
 */
const https_1 = require("firebase-functions/v2/https");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const layout_logic_1 = require("./layout_logic");
const toHttps = (e) => {
    if (e instanceof layout_logic_1.LayoutError)
        throw new https_1.HttpsError(e.code, e.message);
    throw e;
};
async function loadRoles(streamId) {
    const snap = await (0, shared_1.db)().collection(contracts_1.Paths.members(streamId)).get();
    const roles = {};
    const members = [];
    snap.forEach((d) => {
        const m = d.data();
        roles[d.id] = m.role;
        members.push(Object.assign(Object.assign({}, m), { uid: d.id }));
    });
    return { roles, members };
}
/** Connected LiveKit identities. On failure, assume the host is present (deny co-host takeover). */
async function connectedIdentities(streamId, hostId) {
    try {
        const ps = await (0, shared_1.roomService)().listParticipants((0, shared_1.roomName)(streamId));
        return new Set(ps.map((p) => p.identity));
    }
    catch (e) {
        console.warn(`[liveStudio] listParticipants failed for ${streamId}:`, e.message);
        return new Set([hostId]);
    }
}
exports.lsSetLayout = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    var _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const data = ((_b = req.data) !== null && _b !== void 0 ? _b : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    let op;
    try {
        op = (0, layout_logic_1.parseLayoutOp)(data);
    }
    catch (e) {
        return toHttps(e);
    }
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    const role = await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    await (0, shared_1.rateLimit)(streamId, uid, 'layout', 10, 1000);
    const { roles, members } = await loadRoles(streamId);
    let leader = null;
    if (op.op === 'autoPromote') {
        const connected = role === 'host' ? new Set([uid]) : await connectedIdentities(streamId, state.hostId);
        leader = (0, layout_logic_1.electLeader)({ hostId: state.hostId, members, connected, hostAbsentForMs: null });
    }
    try {
        (0, layout_logic_1.authorizeLayoutOp)(op, { uid, role }, leader);
    }
    catch (e) {
        return toHttps(e);
    }
    const ctxFor = (s) => ({
        actorUid: uid,
        nowMs: Date.now(),
        mode: s.settings.speakerMode,
        hostId: s.hostId,
        roles,
    });
    if (op.op === 'setMode') {
        const mode = op.mode;
        await (0, shared_1.patchState)(streamId, 'settings', (s) => {
            try {
                const r = (0, layout_logic_1.applyLayoutOp)(s.stage, op, ctxFor(s));
                return r.mode === undefined ? undefined : Object.assign(Object.assign({}, s.settings), { speakerMode: mode });
            }
            catch (e) {
                return toHttps(e);
            }
        });
    }
    const next = await (0, shared_1.patchState)(streamId, 'stage', (s) => {
        try {
            // For setMode the settings patch has already landed, so re-derive with
            // the stored mode; only the stage half is applied here.
            return (0, layout_logic_1.applyLayoutOp)(s.stage, op, ctxFor(s)).stage;
        }
        catch (e) {
            return toHttps(e);
        }
    });
    const finalState = next !== null && next !== void 0 ? next : (await (0, shared_1.loadState)(streamId));
    return { ok: true, seq: finalState.seq, stage: finalState.stage, speakerMode: finalState.settings.speakerMode };
});
//# sourceMappingURL=layout.js.map