"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsLeaveStage = exports.lsModerate = exports.lsRespondRequest = exports.lsCancelRequest = exports.lsRequestJoin = void 0;
/**
 * LIVE STUDIO v2 — roles, join requests and moderation callables (workstream #4).
 * lsRequestJoin · lsCancelRequest · lsRespondRequest · lsModerate · lsLeaveStage
 * See docs/live-studio/ARCHITECTURE.md §5–§6. Pure logic: roles_logic.ts.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const livekit_server_sdk_1 = require("livekit-server-sdk");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const social_logic_1 = require("./social_logic");
const roles_logic_1 = require("./roles_logic");
const security_1 = require("./security");
const SOURCE = {
    camera: livekit_server_sdk_1.TrackSource.CAMERA,
    microphone: livekit_server_sdk_1.TrackSource.MICROPHONE,
    screen_share: livekit_server_sdk_1.TrackSource.SCREEN_SHARE,
};
/** Maps RolesError to HttpsError; rethrows anything else. */
async function guarded(fn) {
    try {
        return await fn();
    }
    catch (e) {
        if (e instanceof roles_logic_1.RolesError)
            throw new https_1.HttpsError(e.code, e.message);
        throw e;
    }
}
const streamIdArg = (data) => (0, shared_1.requireString)(data === null || data === void 0 ? void 0 : data.streamId, 'streamId', 128);
const memberRef = (streamId, uid) => (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`);
const requestRef = (streamId, uid) => (0, shared_1.db)().doc(`${contracts_1.Paths.requests(streamId)}/${uid}`);
async function profileOf(uid) {
    const snap = await (0, shared_1.db)().doc(`users/${uid}`).get();
    const d = snap.exists ? snap.data() : undefined;
    return { name: (0, social_logic_1.displayNameOf)(d), avatarUrl: (0, social_logic_1.avatarOf)(d) };
}
/** Host + co-hosts (identities that receive `stage.req`). */
async function managerUids(streamId, hostId) {
    const q = await (0, shared_1.db)().collection(contracts_1.Paths.members(streamId)).where('role', '==', 'coHost').select().get();
    return [hostId, ...q.docs.map((d) => d.id).filter((u) => u !== hostId)];
}
async function sendSystemLine(streamId, kind, who) {
    const ts = Date.now();
    await (0, shared_1.broadcast)(streamId, contracts_1.Topics.chat, {
        v: 1,
        type: 'system',
        id: (0, social_logic_1.systemLineId)(ts, Math.random()),
        kind,
        uid: who.uid,
        name: who.name,
        avatarUrl: who.avatarUrl,
        text: social_logic_1.SYSTEM_TEXT[kind],
        ts,
    });
}
/** `request.new` / `request.update` to [to]. [extra] (e.g. `rejoin`) rides along in the JSON. */
async function sendRequestEvent(streamId, type, r, to, extra = {}) {
    const event = Object.assign(Object.assign(Object.assign({ v: 1, type }, r), extra), { ts: Date.now() });
    await (0, shared_1.broadcast)(streamId, contracts_1.Topics.requests, event, { to });
}
/**
 * Updates the participant's LiveKit permission (and `role` attribute) in
 * place. Returns false when they are not in the room or LiveKit refused,
 * so the caller can ask the client to rejoin with a fresh token.
 */
async function setLivePermission(streamId, uid, role) {
    const p = (0, roles_logic_1.permissionForRole)(role);
    try {
        await (0, shared_1.roomService)().updateParticipant((0, shared_1.roomName)(streamId), uid, {
            attributes: { role },
            permission: Object.assign(Object.assign({}, p), { canPublishSources: p.canPublishSources.map((s) => SOURCE[s]) }),
        });
        return true;
    }
    catch (e) {
        console.warn(`[liveStudio] updateParticipant ${uid} in ${streamId}:`, e.message);
        return false;
    }
}
/** Mutes every published mic track of [uid] (server-side). Best effort. */
async function muteMic(streamId, uid) {
    var _a;
    const room = (0, shared_1.roomName)(streamId);
    try {
        const p = await (0, shared_1.roomService)().getParticipant(room, uid);
        const sids = (0, roles_logic_1.micTrackSids)(((_a = p.tracks) !== null && _a !== void 0 ? _a : []).map((t) => ({ sid: t.sid, source: t.source, name: t.name })), livekit_server_sdk_1.TrackSource.MICROPHONE);
        await Promise.all(sids.map((sid) => (0, shared_1.roomService)().mutePublishedTrack(room, uid, sid, true)));
    }
    catch (e) {
        console.warn(`[liveStudio] mute ${uid} in ${streamId}:`, e.message);
    }
}
/**
 * Takes [uid] off the stage: removed from center/wall/overflow (host back to
 * center if they were there), members doc → viewer, join request cleared,
 * LiveKit publish revoked, the user told with `request.update` (cancelled).
 */
async function takeOffStage(streamId, uid, by) {
    let wasCoHost = false;
    await (0, shared_1.patchState)(streamId, 'stage', async (s, tx) => {
        const [m, r] = await Promise.all([tx.get(memberRef(streamId, uid)), tx.get(requestRef(streamId, uid))]);
        if (m.exists) {
            wasCoHost = m.data().role === 'coHost';
            tx.set(memberRef(streamId, uid), (0, roles_logic_1.offStagePatch)(), { merge: true });
        }
        if (r.exists)
            tx.delete(requestRef(streamId, uid));
        return (0, roles_logic_1.removeFromLayout)(s.stage, uid, s.hostId, Date.now(), by);
    });
    if (wasCoHost) {
        await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ coHostIds: firestore_1.FieldValue.arrayRemove(uid) }, { merge: true });
    }
    await setLivePermission(streamId, uid, 'viewer');
    await sendRequestEvent(streamId, 'request.update', { uid, displayName: '', avatarUrl: '', status: 'cancelled', requestedAtMs: 0 }, [uid]);
    return { wasCoHost };
}
// ─── Callables ───────────────────────────────────────────────────────────────
/** A viewer asks to join the stage. Returns `{ok, status:'pending'}`. */
exports.lsRequestJoin = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, (req) => guarded(async () => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    void (0, security_1.recordStudioSignal)(streamId, uid, 'join_request');
    const [state, blocked, streamSnap, existing] = await Promise.all([
        (0, shared_1.loadState)(streamId),
        (0, shared_1.isBlocked)(streamId, uid),
        (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).get(),
        requestRef(streamId, uid).get(),
    ]);
    const role = await (0, shared_1.roleOf)(streamId, uid, state);
    (0, roles_logic_1.assertDecision)((0, roles_logic_1.requestJoinDecision)({
        role,
        blocked,
        status: state.status,
        allowGuestRequests: (0, roles_logic_1.allowsGuestRequests)(streamSnap.data()),
        existing: existing.exists ? ((_a = existing.data().status) !== null && _a !== void 0 ? _a : null) : null,
        onStage: (0, roles_logic_1.stageCount)(state.stage),
    }));
    await (0, shared_1.rateLimit)(streamId, uid, 'join', roles_logic_1.REQUEST_JOIN_MAX, roles_logic_1.REQUEST_JOIN_WINDOW_MS);
    const p = await profileOf(uid);
    const request = {
        uid,
        displayName: p.name,
        avatarUrl: p.avatarUrl,
        status: 'pending',
        requestedAtMs: Date.now(),
    };
    await requestRef(streamId, uid).set(request);
    await sendRequestEvent(streamId, 'request.new', request, await managerUids(streamId, state.hostId));
    await sendSystemLine(streamId, 'requested', { uid, name: p.name, avatarUrl: p.avatarUrl });
    return { ok: true, status: 'pending' };
}));
/** The requester withdraws their pending request. Returns `{ok, status:'cancelled'}`. */
exports.lsCancelRequest = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, (req) => guarded(async () => {
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    const ref = requestRef(streamId, uid);
    const r = await (0, shared_1.db)().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const cur = snap.exists ? snap.data() : null;
        (0, roles_logic_1.assertDecision)((0, roles_logic_1.cancelDecision)(cur === null || cur === void 0 ? void 0 : cur.status));
        tx.update(ref, { status: 'cancelled' });
        return Object.assign(Object.assign({}, cur), { status: 'cancelled' });
    });
    const state = await (0, shared_1.loadState)(streamId);
    await sendRequestEvent(streamId, 'request.update', r, await managerUids(streamId, state.hostId));
    return { ok: true, status: 'cancelled' };
}));
/**
 * Host/co-host answers a request. Approve → guest with an accent, first free
 * wall index (or overflow), LiveKit publish granted in place.
 * Returns `{ok, status, placement?, rejoin}`; `rejoin` is true when the
 * guest was not in the room and must reconnect with a fresh token.
 */
exports.lsRespondRequest = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, (req) => guarded(async () => {
    const actor = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    const { uid, approve } = (0, roles_logic_1.parseRespondArgs)(req.data);
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    const actorRole = await (0, shared_1.requireRole)(streamId, actor, ['host', 'coHost'], state);
    const targetBlocked = await (0, shared_1.isBlocked)(streamId, uid);
    const ref = requestRef(streamId, uid);
    if (!approve) {
        const r = await (0, shared_1.db)().runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const cur = snap.exists ? snap.data() : null;
            (0, roles_logic_1.assertDecision)((0, roles_logic_1.respondDecision)({ actorRole, requestStatus: cur === null || cur === void 0 ? void 0 : cur.status, targetRole: 'viewer', targetBlocked: false }));
            tx.update(ref, { status: 'declined', respondedBy: actor, respondedAtMs: Date.now() });
            return Object.assign(Object.assign({}, cur), { status: 'declined' });
        });
        await sendRequestEvent(streamId, 'request.update', r, [uid]);
        return { ok: true, status: 'declined', rejoin: false };
    }
    let request = null;
    let placement = { kind: 'already' };
    await (0, shared_1.patchState)(streamId, 'stage', async (s, tx) => {
        var _a;
        const [reqSnap, membersSnap] = await Promise.all([tx.get(ref), tx.get((0, shared_1.db)().collection(contracts_1.Paths.members(streamId)))]);
        const cur = reqSnap.exists ? reqSnap.data() : null;
        const members = membersSnap.docs.map((d) => (Object.assign(Object.assign({}, d.data()), { uid: d.id })));
        const target = members.find((m) => m.uid === uid);
        const targetRole = uid === s.hostId ? 'host' : ((_a = target === null || target === void 0 ? void 0 : target.role) !== null && _a !== void 0 ? _a : 'viewer');
        (0, roles_logic_1.assertDecision)((0, roles_logic_1.respondDecision)({ actorRole, requestStatus: cur === null || cur === void 0 ? void 0 : cur.status, targetRole, targetBlocked }));
        const now = Date.now();
        const placed = (0, roles_logic_1.placeOnStage)(s.stage, uid, now, actor);
        placement = placed.placement;
        tx.set(memberRef(streamId, uid), (0, roles_logic_1.guestMemberPatch)({
            uid,
            displayName: cur.displayName,
            avatarUrl: cur.avatarUrl,
            accent: (0, roles_logic_1.pickAccent)(members, uid),
            nowMs: now,
        }), { merge: true });
        tx.update(ref, { status: 'approved', respondedBy: actor, respondedAtMs: now, rejoin: false });
        request = Object.assign(Object.assign({}, cur), { status: 'approved' });
        return placed.placement.kind === 'already' ? undefined : placed.stage;
    });
    const inPlace = await setLivePermission(streamId, uid, 'guest');
    if (!inPlace)
        await ref.update({ rejoin: true });
    const approved = request;
    await sendRequestEvent(streamId, 'request.update', approved, [uid], { rejoin: !inPlace });
    await sendSystemLine(streamId, 'onStage', { uid, name: approved.displayName, avatarUrl: approved.avatarUrl });
    return { ok: true, status: 'approved', placement, rejoin: !inPlace };
}));
/**
 * Host/co-host moderation: `mute` | `removeFromStage` | `block`, plus the
 * host-only `promoteCoHost` | `demoteCoHost` (local type until the contract
 * enum gains them). Returns `{ok, action}`.
 */
exports.lsModerate = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, (req) => guarded(async () => {
    const actor = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    const { uid, action } = (0, roles_logic_1.parseModerateArgs)(req.data);
    const state = await (0, shared_1.loadState)(streamId);
    const actorRole = await (0, shared_1.requireRole)(streamId, actor, ['host', 'coHost'], state);
    const targetRole = await (0, shared_1.roleOf)(streamId, uid, state);
    const st = state.stage;
    const targetOnStage = st.centerUid === uid || st.wall.includes(uid) || st.overflow.includes(uid);
    (0, roles_logic_1.assertDecision)((0, roles_logic_1.authorizeModeration)({ action, actorUid: actor, actorRole, targetUid: uid, targetRole, targetOnStage }));
    switch (action) {
        case 'mute':
            await muteMic(streamId, uid);
            await memberRef(streamId, uid).set({ micOn: false }, { merge: true });
            break;
        case 'removeFromStage':
            await takeOffStage(streamId, uid, actor);
            break;
        case 'block': {
            if (targetOnStage || targetRole !== 'viewer')
                await takeOffStage(streamId, uid, actor);
            await (0, shared_1.db)().doc(`${contracts_1.Paths.blocks(streamId)}/${uid}`).set({ uid, by: actor, atMs: Date.now() });
            await requestRef(streamId, uid).delete();
            try {
                await (0, shared_1.roomService)().removeParticipant((0, shared_1.roomName)(streamId), uid);
            }
            catch (e) {
                console.warn(`[liveStudio] removeParticipant ${uid}:`, e.message);
            }
            break;
        }
        case 'promoteCoHost':
        case 'demoteCoHost': {
            const role = action === 'promoteCoHost' ? 'coHost' : 'guest';
            await memberRef(streamId, uid).set({ role }, { merge: true });
            await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ coHostIds: action === 'promoteCoHost' ? firestore_1.FieldValue.arrayUnion(uid) : firestore_1.FieldValue.arrayRemove(uid) }, { merge: true });
            await setLivePermission(streamId, uid, role);
            break;
        }
    }
    return { ok: true, action };
}));
/** A guest or co-host leaves the stage. Returns `{ok}`. */
exports.lsLeaveStage = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, (req) => guarded(async () => {
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    const state = await (0, shared_1.loadState)(streamId);
    const role = await (0, shared_1.roleOf)(streamId, uid, state);
    (0, roles_logic_1.assertDecision)((0, roles_logic_1.leaveDecision)(role));
    await takeOffStage(streamId, uid, uid);
    return { ok: true };
}));
//# sourceMappingURL=roles.js.map