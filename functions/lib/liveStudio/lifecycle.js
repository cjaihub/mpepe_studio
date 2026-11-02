"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsSweepOrphanLives = exports.lsHeartbeat = void 0;
exports.endStudioStream = endStudioStream;
exports.onHostPresence = onHostPresence;
/**
 * LIVE STUDIO v2 — live lifecycle: clean endings, no hanging lives.
 *   lsHeartbeat({streamId})  host app pings every 20 s while live
 *   lsSweepOrphanLives       every minute: closes lives whose host is gone
 * endStudioStream() is shared by lsEnd, the sweeper and the LiveKit webhook
 * (room_finished / host left). Pure rules: lifecycle_logic.ts.
 */
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firestore_1 = require("firebase-admin/firestore");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const lifecycle_logic_1 = require("./lifecycle_logic");
const broadcast_1 = require("./broadcast");
/**
 * Closes [streamId] everywhere: studio/state status (broadcast to viewers as a
 * state.patch), the stream doc, and the LiveKit room (which disconnects
 * everyone still inside). Idempotent; never throws for a missing state doc.
 */
async function endStudioStream(streamId, reason) {
    const ref = (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`);
    const ended = await (0, shared_1.db)().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists || snap.get('status') === 'ended')
            return false;
        tx.set(ref, { status: 'ended', endedAt: firestore_1.FieldValue.serverTimestamp(), endedReason: reason, hostLeftAt: firestore_1.FieldValue.delete() }, { merge: true });
        return true;
    });
    // Viewers get the `ended` patch while the recording / restream finishes
    // (in parallel); the room is deleted after egress so the MP4 closes cleanly.
    await Promise.all([
        (0, shared_1.patchState)(streamId, 'status', (s) => (s.status === 'ended' ? undefined : 'ended')).catch((e) => {
            // v1 lives have no studio/state doc.
            console.warn(`[liveStudio] end state ${streamId}:`, e.message);
        }),
        (0, broadcast_1.stopStreamEgress)(streamId),
    ]);
    try {
        await (0, shared_1.roomService)().deleteRoom((0, shared_1.roomName)(streamId));
    }
    catch (e) {
        console.warn(`[liveStudio] deleteRoom ${streamId}:`, e.message);
    }
    return ended;
}
/** Host keep-alive. Returns `{ok, ended}`; `ended` tells the host app the live was closed. */
exports.lsHeartbeat = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const streamId = (0, shared_1.requireString)((_a = req.data) === null || _a === void 0 ? void 0 : _a.streamId, 'streamId', 128);
    const ref = (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'This live does not exist.');
    if (snap.get('hostId') !== uid)
        throw new https_1.HttpsError('permission-denied', 'Only the host sends heartbeats.');
    if (snap.get('status') === 'ended')
        return { ok: false, ended: true };
    await ref.set({ hostHeartbeatAt: firestore_1.FieldValue.serverTimestamp(), hostLeftAt: firestore_1.FieldValue.delete() }, { merge: true });
    return { ok: true, ended: false };
});
/** Closes every live whose host stopped heartbeating or left the room. */
exports.lsSweepOrphanLives = (0, scheduler_1.onSchedule)({ schedule: 'every 1 minutes', secrets: shared_1.LIVEKIT_SECRETS }, async () => {
    var _a;
    const now = Date.now();
    const lives = await (0, shared_1.db)().collection(contracts_1.Paths.streams).where('status', '==', 'live').limit(500).get();
    let closed = 0;
    for (const d of lives.docs) {
        const reason = (0, lifecycle_logic_1.orphanReason)({
            status: d.get('status'),
            createdMs: (_a = (0, lifecycle_logic_1.toMs)(d.get('createdAt'))) !== null && _a !== void 0 ? _a : (0, lifecycle_logic_1.toMs)(d.get('startedAt')),
            heartbeatMs: (0, lifecycle_logic_1.toMs)(d.get('hostHeartbeatAt')),
            hostLeftMs: (0, lifecycle_logic_1.toMs)(d.get('hostLeftAt')),
        }, now);
        if (!reason)
            continue;
        try {
            if (await endStudioStream(d.id, reason))
                closed++;
        }
        catch (e) {
            console.error(`[liveStudio] sweep ${d.id}:`, e.message);
        }
    }
    if (closed)
        console.log(`[liveStudio] swept ${closed} orphaned live(s)`);
});
/** Webhook hook: the host's LiveKit connection joined / left the room. */
async function onHostPresence(streamId, identity, joined) {
    const ref = (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`);
    const snap = await ref.get();
    if (!snap.exists || snap.get('hostId') !== identity || snap.get('status') !== 'live')
        return;
    await ref.set({ hostLeftAt: joined ? firestore_1.FieldValue.delete() : firestore_1.FieldValue.serverTimestamp() }, { merge: true });
}
//# sourceMappingURL=lifecycle.js.map