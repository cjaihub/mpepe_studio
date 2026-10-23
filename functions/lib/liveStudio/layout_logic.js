"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isStageRole = exports.LayoutError = void 0;
exports.parseLayoutOp = parseLayoutOp;
exports.electLeader = electLeader;
exports.authorizeLayoutOp = authorizeLayoutOp;
exports.applyLayoutOp = applyLayoutOp;
/**
 * LIVE STUDIO v2 — pure layout transitions for `lsSetLayout`
 * (ARCHITECTURE §5, §8). No Firestore / LiveKit imports: unit-tested in
 * __tests__/layout_logic.test.ts.
 */
const contracts_1 = require("./contracts");
class LayoutError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
}
exports.LayoutError = LayoutError;
const MODES = ['hostPinned', 'autoActiveSpeaker', 'manual'];
const isUid = (v) => typeof v === 'string' && v.length > 0 && v.length <= 128;
const isIndex = (v) => typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < contracts_1.Limits.wallSlots;
/** Validates raw callable args into a typed op. */
function parseLayoutOp(raw) {
    const op = raw.op;
    switch (op) {
        case 'swap':
            if (!isIndex(raw.index))
                throw new LayoutError('invalid-argument', 'index must be 0–5.');
            return { op, index: raw.index };
        case 'pin':
        case 'autoPromote':
            if (!isUid(raw.uid))
                throw new LayoutError('invalid-argument', 'uid is required.');
            return { op, uid: raw.uid };
        case 'unpin':
            return { op };
        case 'setMode':
            if (!MODES.includes(raw.mode))
                throw new LayoutError('invalid-argument', 'Unknown speaker mode.');
            return { op, mode: raw.mode };
        case 'rotateIn':
            if (!isUid(raw.uid))
                throw new LayoutError('invalid-argument', 'uid is required.');
            if (!isIndex(raw.index))
                throw new LayoutError('invalid-argument', 'index must be 0–5.');
            return { op, uid: raw.uid, index: raw.index };
        default:
            throw new LayoutError('invalid-argument', `Unknown layout op "${String(op)}".`);
    }
}
/** A member doc counts as "on stage" when it can publish. */
const isStageRole = (r) => r === 'host' || r === 'coHost' || r === 'guest';
exports.isStageRole = isStageRole;
/**
 * Leader election, mirrored from the Dart `electLayoutLeader`:
 * the host while connected; otherwise (host gone ≥ leaderFailoverMs, or
 * never seen) the longest-serving connected coHost; nobody in between.
 */
function electLeader(args) {
    const { hostId, members, connected, hostAbsentForMs } = args;
    if (connected.has(hostId))
        return hostId;
    if (hostAbsentForMs !== null && hostAbsentForMs < contracts_1.Limits.leaderFailoverMs)
        return null;
    const cos = members
        .filter((m) => m.role === 'coHost' && m.uid !== hostId && connected.has(m.uid))
        .sort((a, b) => { var _a, _b; return ((_a = a.joinedAtMs) !== null && _a !== void 0 ? _a : 0) - ((_b = b.joinedAtMs) !== null && _b !== void 0 ? _b : 0) || (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0); });
    return cos.length ? cos[0].uid : null;
}
/**
 * Who may send [op]. Every op except autoPromote: host/coHost. autoPromote:
 * only the current leader ([leaderUid], computed by the caller).
 */
function authorizeLayoutOp(op, actor, leaderUid) {
    if (op.op === 'autoPromote') {
        if (actor.uid !== leaderUid)
            throw new LayoutError('permission-denied', 'Only the layout leader can auto-promote.');
        if (actor.role !== 'host' && actor.role !== 'coHost') {
            throw new LayoutError('permission-denied', 'Only the host or a co-host can lead the layout.');
        }
        return;
    }
    if (actor.role !== 'host' && actor.role !== 'coHost') {
        throw new LayoutError('permission-denied', 'Only the host or a co-host can change the layout.');
    }
}
const normalize = (s) => { var _a, _b, _c, _d, _e; return ({
    centerUid: (_a = s.centerUid) !== null && _a !== void 0 ? _a : '',
    wall: Array.from({ length: contracts_1.Limits.wallSlots }, (_, i) => { var _a; var _b; return (_b = (_a = s.wall) === null || _a === void 0 ? void 0 : _a[i]) !== null && _b !== void 0 ? _b : null; }),
    overflow: [...((_b = s.overflow) !== null && _b !== void 0 ? _b : [])],
    pinnedUid: (_c = s.pinnedUid) !== null && _c !== void 0 ? _c : null,
    updatedAtMs: (_d = s.updatedAtMs) !== null && _d !== void 0 ? _d : 0,
    updatedBy: (_e = s.updatedBy) !== null && _e !== void 0 ? _e : '',
}); };
function requireMember(ctx, uid) {
    const role = uid === ctx.hostId ? 'host' : ctx.roles[uid];
    if (!(0, exports.isStageRole)(role))
        throw new LayoutError('failed-precondition', 'That person is not on stage.');
}
/** Swap [uid] (on the wall or in overflow) with the center. */
function bringToCenter(s, uid) {
    if (s.centerUid === uid)
        return s;
    const wi = s.wall.indexOf(uid);
    const oi = s.overflow.indexOf(uid);
    if (wi < 0 && oi < 0)
        throw new LayoutError('failed-precondition', 'That person is not on the stage layout.');
    const wall = [...s.wall];
    const overflow = [...s.overflow];
    const prev = s.centerUid || null;
    if (wi >= 0)
        wall[wi] = prev;
    else if (prev)
        overflow[oi] = prev;
    else
        overflow.splice(oi, 1);
    return Object.assign(Object.assign({}, s), { centerUid: uid, wall, overflow });
}
const stamp = (s, ctx) => (Object.assign(Object.assign({}, s), { updatedAtMs: ctx.nowMs, updatedBy: ctx.actorUid }));
/** The pure transition. Throws [LayoutError] on any rejected op. */
function applyLayoutOp(stageIn, op, ctx) {
    const s = normalize(stageIn);
    switch (op.op) {
        case 'swap': {
            const uid = s.wall[op.index];
            if (!uid)
                throw new LayoutError('failed-precondition', 'That wall slot is empty.');
            requireMember(ctx, uid);
            return { stage: stamp(bringToCenter(s, uid), ctx) };
        }
        case 'pin': {
            requireMember(ctx, op.uid);
            const moved = s.centerUid === op.uid ? s : bringToCenter(s, op.uid);
            if (moved === s && s.pinnedUid === op.uid)
                return {};
            return { stage: stamp(Object.assign(Object.assign({}, moved), { pinnedUid: op.uid }), ctx) };
        }
        case 'unpin':
            if (s.pinnedUid === null)
                return {};
            return { stage: stamp(Object.assign(Object.assign({}, s), { pinnedUid: null }), ctx) };
        case 'setMode': {
            const res = {};
            if (op.mode !== ctx.mode)
                res.mode = op.mode;
            // hostPinned means "the host stays in the center": bring them back.
            if (op.mode === 'hostPinned' && s.centerUid !== ctx.hostId) {
                const onLayout = s.wall.includes(ctx.hostId) || s.overflow.includes(ctx.hostId);
                if (onLayout)
                    res.stage = stamp(bringToCenter(s, ctx.hostId), ctx);
            }
            return res;
        }
        case 'rotateIn': {
            requireMember(ctx, op.uid);
            const oi = s.overflow.indexOf(op.uid);
            if (oi < 0)
                throw new LayoutError('failed-precondition', 'Only overflow members can rotate onto the wall.');
            const wall = [...s.wall];
            const overflow = [...s.overflow];
            const out = wall[op.index];
            wall[op.index] = op.uid;
            if (out)
                overflow[oi] = out;
            else
                overflow.splice(oi, 1);
            return { stage: stamp(Object.assign(Object.assign({}, s), { wall, overflow }), ctx) };
        }
        case 'autoPromote': {
            if (ctx.mode !== 'autoActiveSpeaker')
                throw new LayoutError('failed-precondition', 'Auto speaker mode is off.');
            if (s.pinnedUid)
                throw new LayoutError('failed-precondition', 'The center is pinned.');
            if (ctx.nowMs - s.updatedAtMs < contracts_1.Limits.minCenterHoldMs) {
                throw new LayoutError('failed-precondition', 'The center is still in its minimum hold.');
            }
            if (s.centerUid === op.uid)
                return {};
            requireMember(ctx, op.uid);
            return { stage: stamp(bringToCenter(s, op.uid), ctx) };
        }
    }
}
//# sourceMappingURL=layout_logic.js.map