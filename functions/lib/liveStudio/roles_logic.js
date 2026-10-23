"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.allowsGuestRequests = exports.offStagePatch = exports.isOnStageRole = exports.actorAllowed = exports.ACTOR_MATRIX = exports.RolesError = exports.REQUEST_JOIN_WINDOW_MS = exports.REQUEST_JOIN_MAX = exports.MODERATION_ACTIONS = void 0;
exports.assertDecision = assertDecision;
exports.parseTargetUid = parseTargetUid;
exports.parseModerationAction = parseModerationAction;
exports.parseRespondArgs = parseRespondArgs;
exports.parseModerateArgs = parseModerateArgs;
exports.requestJoinDecision = requestJoinDecision;
exports.cancelDecision = cancelDecision;
exports.respondDecision = respondDecision;
exports.leaveDecision = leaveDecision;
exports.authorizeModeration = authorizeModeration;
exports.placeOnStage = placeOnStage;
exports.removeFromLayout = removeFromLayout;
exports.pickAccent = pickAccent;
exports.guestMemberPatch = guestMemberPatch;
exports.permissionForRole = permissionForRole;
exports.micTrackSids = micTrackSids;
/**
 * LIVE STUDIO v2 — roles, join requests and moderation: pure logic
 * (workstream #4). No Firestore / LiveKit imports, so everything here is
 * unit-tested in __tests__/roles_logic.test.ts.
 *
 * Permission matrix: docs/live-studio/ARCHITECTURE.md §6.
 */
const contracts_1 = require("./contracts");
const media_logic_1 = require("./media_logic");
exports.MODERATION_ACTIONS = [
    'mute',
    'removeFromStage',
    'block',
    'promoteCoHost',
    'demoteCoHost',
];
/** Rate limit for lsRequestJoin: 1 call per 10 s per user. */
exports.REQUEST_JOIN_MAX = 1;
exports.REQUEST_JOIN_WINDOW_MS = 10000;
class RolesError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
}
exports.RolesError = RolesError;
const OK = { ok: true };
const deny = (code, message) => ({ ok: false, code, message });
/** Throws [RolesError] for a refused decision. */
function assertDecision(d) {
    if (!d.ok)
        throw new RolesError(d.code, d.message);
}
// ─── §6 matrix: which actor roles may attempt each action ────────────────────
/**
 * Actor side of ARCHITECTURE §6 for the actions owned here. Target-specific
 * restrictions (co-hosts cannot act on the host, cannot block co-hosts, …)
 * are in [authorizeModeration].
 */
exports.ACTOR_MATRIX = {
    requestJoin: ['viewer'],
    cancelRequest: ['viewer'],
    respondRequest: ['host', 'coHost'],
    mute: ['host', 'coHost'],
    removeFromStage: ['host', 'coHost'],
    block: ['host', 'coHost'],
    promoteCoHost: ['host'],
    demoteCoHost: ['host'],
    leaveStage: ['coHost', 'guest'],
};
const actorAllowed = (action, role) => exports.ACTOR_MATRIX[action].includes(role);
exports.actorAllowed = actorAllowed;
const isOnStageRole = (r) => r === 'host' || r === 'coHost' || r === 'guest';
exports.isOnStageRole = isOnStageRole;
// ─── Arg parsing ─────────────────────────────────────────────────────────────
const isUid = (v) => typeof v === 'string' && v.length > 0 && v.length <= 128 && !v.includes('/');
function parseTargetUid(v) {
    if (!isUid(v))
        throw new RolesError('invalid-argument', 'uid is required.');
    return v;
}
function parseModerationAction(v) {
    if (typeof v === 'string' && exports.MODERATION_ACTIONS.includes(v)) {
        return v;
    }
    throw new RolesError('invalid-argument', `Unknown moderation action "${String(v)}".`);
}
function parseRespondArgs(data) {
    const d = (data && typeof data === 'object' ? data : {});
    const uid = parseTargetUid(d.uid);
    if (typeof d.approve !== 'boolean')
        throw new RolesError('invalid-argument', 'approve must be a boolean.');
    return { uid, approve: d.approve };
}
function parseModerateArgs(data) {
    const d = (data && typeof data === 'object' ? data : {});
    return { uid: parseTargetUid(d.uid), action: parseModerationAction(d.action) };
}
// ─── Decisions ───────────────────────────────────────────────────────────────
/** lsRequestJoin: a viewer, not blocked, on a live stream that allows requests. */
function requestJoinDecision(a) {
    if (a.blocked)
        return deny('permission-denied', 'You are blocked from this live.');
    if (a.status !== 'live')
        return deny('failed-precondition', 'This live is not on air.');
    if (!(0, exports.actorAllowed)('requestJoin', a.role))
        return deny('failed-precondition', 'You are already on stage.');
    if (!a.allowGuestRequests)
        return deny('failed-precondition', 'The host is not taking requests.');
    return OK;
}
/** lsCancelRequest: the requester's own doc, still pending. */
function cancelDecision(existing) {
    if (!existing)
        return deny('not-found', 'No request to cancel.');
    if (existing !== 'pending')
        return deny('failed-precondition', 'This request was already answered.');
    return OK;
}
/** lsRespondRequest: a manager answering a pending request of a viewer. */
function respondDecision(a) {
    if (!(0, exports.actorAllowed)('respondRequest', a.actorRole))
        return deny('permission-denied', 'Only the host or a co-host can answer.');
    if (!a.requestStatus)
        return deny('not-found', 'Request not found.');
    if (a.requestStatus !== 'pending')
        return deny('failed-precondition', 'This request was already answered.');
    if (a.targetBlocked)
        return deny('failed-precondition', 'This user is blocked.');
    if (a.targetRole !== 'viewer')
        return deny('failed-precondition', 'This user is already on stage.');
    return OK;
}
/** lsLeaveStage: a guest or co-host leaves (the host ends the live instead). */
function leaveDecision(role) {
    if (role === 'host')
        return deny('failed-precondition', 'The host ends the live instead of leaving the stage.');
    if (!(0, exports.actorAllowed)('leaveStage', role))
        return deny('failed-precondition', 'You are not on stage.');
    return OK;
}
/**
 * lsModerate: actor/target rules of ARCHITECTURE §6.
 * - host/coHost only; promote/demote are host only;
 * - nobody targets themselves (use lsLeaveStage);
 * - a co-host never acts on the host, and never blocks a co-host;
 * - mute/remove need someone on stage, promote needs a guest, demote a co-host.
 */
function authorizeModeration(a) {
    if (!(0, exports.actorAllowed)(a.action, a.actorRole)) {
        return deny('permission-denied', a.action === 'promoteCoHost' || a.action === 'demoteCoHost'
            ? 'Only the host can change co-hosts.'
            : 'Only the host or a co-host can moderate.');
    }
    if (a.actorUid === a.targetUid)
        return deny('invalid-argument', 'You cannot moderate yourself.');
    if (a.targetRole === 'host')
        return deny('permission-denied', 'Nobody can moderate the host.');
    switch (a.action) {
        case 'mute':
            if (!a.targetOnStage && !(0, exports.isOnStageRole)(a.targetRole))
                return deny('failed-precondition', 'This user is not on stage.');
            return OK;
        case 'removeFromStage':
            if (!a.targetOnStage && !(0, exports.isOnStageRole)(a.targetRole))
                return deny('failed-precondition', 'This user is not on stage.');
            return OK;
        case 'block':
            if (a.actorRole === 'coHost' && a.targetRole === 'coHost') {
                return deny('permission-denied', 'Co-hosts cannot block other co-hosts.');
            }
            return OK;
        case 'promoteCoHost':
            if (a.targetRole !== 'guest')
                return deny('failed-precondition', 'Only a guest on stage can become a co-host.');
            return OK;
        case 'demoteCoHost':
            if (a.targetRole !== 'coHost')
                return deny('failed-precondition', 'This user is not a co-host.');
            return OK;
    }
}
const onLayout = (s, uid) => s.centerUid === uid || s.wall.includes(uid) || s.overflow.includes(uid);
const normWall = (wall) => Array.from({ length: contracts_1.Limits.wallSlots }, (_, i) => { var _a; return (_a = wall[i]) !== null && _a !== void 0 ? _a : null; });
/** Puts [uid] in the first free wall index, or overflow when the wall is full. */
function placeOnStage(stage, uid, nowMs, by) {
    if (onLayout(stage, uid))
        return { stage, placement: { kind: 'already' } };
    const wall = normWall(stage.wall);
    const index = wall.findIndex((u) => !u);
    if (index >= 0) {
        wall[index] = uid;
        return {
            stage: Object.assign(Object.assign({}, stage), { wall, updatedAtMs: nowMs, updatedBy: by }),
            placement: { kind: 'wall', index },
        };
    }
    return {
        stage: Object.assign(Object.assign({}, stage), { wall, overflow: [...stage.overflow, uid], updatedAtMs: nowMs, updatedBy: by }),
        placement: { kind: 'overflow' },
    };
}
/**
 * Removes [uid] from the center, wall and overflow. If they were in the
 * center the host returns to the center (and leaves their own wall/overflow
 * spot). A freed wall slot is refilled from the head of overflow. A pin on
 * [uid] is cleared. Returns `undefined` when [uid] was not on the layout.
 */
function removeFromLayout(stage, uid, hostId, nowMs, by) {
    if (!onLayout(stage, uid) && stage.pinnedUid !== uid)
        return undefined;
    let centerUid = stage.centerUid;
    const gone = new Set([uid]);
    if (centerUid === uid) {
        centerUid = hostId;
        gone.add(hostId);
    }
    const wall = normWall(stage.wall).map((u) => (u && gone.has(u) ? null : u));
    const overflow = stage.overflow.filter((u) => !gone.has(u));
    for (let i = 0; i < wall.length && overflow.length > 0; i++) {
        if (!wall[i])
            wall[i] = overflow.shift();
    }
    return Object.assign(Object.assign({}, stage), { centerUid,
        wall,
        overflow, pinnedUid: stage.pinnedUid === uid ? null : stage.pinnedUid, updatedAtMs: nowMs, updatedBy: by });
}
// ─── Members ─────────────────────────────────────────────────────────────────
/**
 * First palette accent not used by the current on-stage members (by join
 * order). When every accent is taken, cycles by the number of members.
 */
function pickAccent(members, forUid, palette = contracts_1.ACCENT_PALETTE) {
    const current = members
        .filter((m) => m.uid !== forUid && (0, exports.isOnStageRole)(m.role))
        .sort((a, b) => { var _a, _b; return ((_a = a.joinedAtMs) !== null && _a !== void 0 ? _a : 0) - ((_b = b.joinedAtMs) !== null && _b !== void 0 ? _b : 0); });
    const used = new Set(current.map((m) => { var _a; return ((_a = m.accent) !== null && _a !== void 0 ? _a : '').toUpperCase(); }));
    const free = palette.find((c) => !used.has(c.toUpperCase()));
    return free !== null && free !== void 0 ? free : palette[current.length % palette.length];
}
/** Members doc fields written on approval (chatMuted is preserved by merge). */
function guestMemberPatch(a) {
    return {
        uid: a.uid,
        displayName: a.displayName,
        avatarUrl: a.avatarUrl,
        accent: a.accent,
        role: 'guest',
        micOn: true,
        camOn: true,
        joinedAtMs: a.nowMs,
    };
}
/** Members doc fields written when someone leaves or is removed from the stage. */
const offStagePatch = () => ({
    role: 'viewer',
    micOn: false,
    camOn: false,
});
exports.offStagePatch = offStagePatch;
// ─── LiveKit ─────────────────────────────────────────────────────────────────
/** LiveKit ParticipantPermission for [role] (string sources; mapped to TrackSource in roles.ts). */
function permissionForRole(role) {
    const g = (0, media_logic_1.grantForRole)(role, '');
    return {
        canPublish: g.canPublish,
        canSubscribe: true,
        canPublishData: false,
        canPublishSources: g.canPublishSources,
    };
}
/** Sids of published microphone tracks (by source, or by track name `mic` as a fallback). */
function micTrackSids(tracks, micSource, micName = 'mic') {
    return tracks.filter((t) => t.sid && (t.source === micSource || t.name === micName)).map((t) => t.sid);
}
/** `allowGuestRequests` on the stream doc; defaults to true (v1 default). */
const allowsGuestRequests = (streamDoc) => (streamDoc === null || streamDoc === void 0 ? void 0 : streamDoc.allowGuestRequests) !== false;
exports.allowsGuestRequests = allowsGuestRequests;
//# sourceMappingURL=roles_logic.js.map