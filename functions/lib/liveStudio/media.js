"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsSetOwnMedia = exports.lsStateFull = exports.lsTime = exports.lsEnd = exports.lsToken = exports.lsStart = void 0;
/**
 * LIVE STUDIO v2 — realtime media callables (workstream #1).
 * lsStart · lsToken · lsEnd · lsTime · lsStateFull · lsSetOwnMedia
 * See docs/live-studio/ARCHITECTURE.md §5–§7. Pure logic: media_logic.ts.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const livekit_server_sdk_1 = require("livekit-server-sdk");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const settings_logic_1 = require("./settings_logic");
const security_1 = require("./security");
const media_logic_1 = require("./media_logic");
const SOURCE = {
    camera: livekit_server_sdk_1.TrackSource.CAMERA,
    microphone: livekit_server_sdk_1.TrackSource.MICROPHONE,
    screen_share: livekit_server_sdk_1.TrackSource.SCREEN_SHARE,
};
async function profileOf(uid, token) {
    const snap = await (0, shared_1.db)().doc(`users/${uid}`).get();
    return (0, media_logic_1.profileFrom)(snap.exists ? snap.data() : undefined, token);
}
/** Mints a LiveKit token for [uid] with the grants of [role] (identity = Firebase uid). */
async function mintToken(streamId, uid, role, name) {
    const g = (0, media_logic_1.grantForRole)(role, (0, shared_1.roomName)(streamId));
    const at = new livekit_server_sdk_1.AccessToken(shared_1.LIVEKIT_API_KEY.value(), shared_1.LIVEKIT_API_SECRET.value(), {
        identity: uid,
        name,
        ttl: media_logic_1.TOKEN_TTL_SECONDS,
        attributes: { role },
    });
    at.addGrant(Object.assign(Object.assign({}, g), { canPublishSources: g.canPublishSources.map((s) => SOURCE[s]) }));
    return at.toJwt();
}
function streamIdArg(data) {
    return (0, shared_1.requireString)(data === null || data === void 0 ? void 0 : data.streamId, 'streamId', 128);
}
/** Host starts a v2 live. Returns `{streamId, token, url, role}`. */
exports.lsStart = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    var _b;
    const uid = (0, shared_1.requireUid)(req);
    const data = ((_b = req.data) !== null && _b !== void 0 ? _b : {});
    const title = (0, shared_1.requireString)(data.title, 'title', 200);
    const [profile, savedSnap] = await Promise.all([
        profileOf(uid, (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token),
        (0, shared_1.db)().doc(contracts_1.Paths.hostSettings(uid)).get(),
    ]);
    const settings = (0, settings_logic_1.normalizeSettings)((0, media_logic_1.mergeStartSettings)(savedSnap.exists ? savedSnap.data() : undefined, data.settings));
    const streamRef = (0, shared_1.db)().collection(contracts_1.Paths.streams).doc();
    const streamId = streamRef.id;
    const now = Date.now();
    // Room first: if LiveKit is unreachable nothing is written.
    try {
        await (0, shared_1.roomService)().createRoom({ name: (0, shared_1.roomName)(streamId), emptyTimeout: media_logic_1.ROOM_EMPTY_TIMEOUT_SECONDS });
    }
    catch (e) {
        console.error('[liveStudio] createRoom failed:', e.message);
        throw new https_1.HttpsError('unavailable', 'Could not open the live room. Try again.');
    }
    const batch = (0, shared_1.db)().batch();
    batch.set(streamRef, Object.assign(Object.assign({}, (0, media_logic_1.buildStreamDoc)({ streamId, hostId: uid, title, profile })), { createdAt: firestore_1.FieldValue.serverTimestamp() }));
    batch.set((0, shared_1.db)().doc(contracts_1.Paths.state(streamId)), Object.assign(Object.assign({}, (0, media_logic_1.buildInitialState)({ streamId, hostId: uid, title, settings, nowMs: now })), { updatedAt: firestore_1.FieldValue.serverTimestamp() }));
    batch.set((0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`), (0, media_logic_1.buildHostMember)(uid, profile, now));
    await batch.commit();
    const [token, e2ee] = await Promise.all([
        mintToken(streamId, uid, 'host', profile.displayName),
        (0, security_1.mediaKeyForToken)(streamId),
    ]);
    return { streamId, token, url: shared_1.LIVEKIT_URL.value(), role: 'host', e2ee };
});
/**
 * LiveKit join token for the caller. Returns `{token, url, role, e2ee}`;
 * `e2ee` is `{key, keyIndex}` (the stream's shared media key, base64) or
 * null when LIVE_STUDIO_E2EE is off. See security.ts / security_logic.ts.
 */
exports.lsToken = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    const state = await (0, shared_1.loadState)(streamId);
    const blocked = await (0, shared_1.isBlocked)(streamId, uid);
    const decision = (0, media_logic_1.tokenDecision)({ status: state.status, blocked });
    if (!decision.ok) {
        if (blocked)
            await (0, security_1.recordStudioSignal)(streamId, uid, 'blocked_token');
        throw new https_1.HttpsError(decision.code, decision.message);
    }
    const role = await (0, shared_1.roleOf)(streamId, uid, state);
    const member = await (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`).get();
    const name = member.exists
        ? member.data().displayName
        : (await profileOf(uid, (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token)).displayName;
    const [token, e2ee] = await Promise.all([
        mintToken(streamId, uid, role, name),
        (0, security_1.mediaKeyForToken)(streamId),
        (0, security_1.recordTokenSignal)(streamId, uid, req),
    ]);
    return { token, url: shared_1.LIVEKIT_URL.value(), role, e2ee };
});
/** Host ends the live: status ended (stream doc + studio/state), room deleted. */
exports.lsEnd = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    await (0, shared_1.requireRole)(streamId, uid, ['host']);
    await (0, shared_1.patchState)(streamId, 'status', (s) => (s.status === 'ended' ? undefined : 'ended'));
    await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ status: 'ended', endedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    try {
        await (0, shared_1.roomService)().deleteRoom((0, shared_1.roomName)(streamId));
    }
    catch (e) {
        console.warn(`[liveStudio] deleteRoom ${streamId}:`, e.message);
    }
    return { ok: true };
});
/** Server clock, for the client's offset estimate. Returns `{serverMs}`. */
exports.lsTime = (0, https_1.onCall)(async (req) => {
    (0, shared_1.requireUid)(req);
    return { serverMs: Date.now() };
});
/** Full StudioState for resync (late join, reconnect, seq gap). Returns `{state}`. */
exports.lsStateFull = (0, https_1.onCall)(async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    if (await (0, shared_1.isBlocked)(streamId, uid))
        throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
    const snap = await (0, shared_1.db)().doc(contracts_1.Paths.state(streamId)).get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'This live does not exist.');
    return { state: (0, media_logic_1.wireState)(snap.data()) };
});
/** A publisher syncs their own mic / cam flags to their members doc. */
exports.lsSetOwnMedia = (0, https_1.onCall)(async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const streamId = streamIdArg(req.data);
    const media = (0, media_logic_1.parseOwnMedia)(req.data);
    if (!media)
        throw new https_1.HttpsError('invalid-argument', 'micOn and camOn must be booleans.');
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    const role = await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost', 'guest'], state);
    if (!(0, media_logic_1.canSetOwnMedia)(role, uid, state))
        throw new https_1.HttpsError('failed-precondition', 'You are not on stage.');
    await (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`).set(media, { merge: true });
    return Object.assign({ ok: true }, media);
});
//# sourceMappingURL=media.js.map