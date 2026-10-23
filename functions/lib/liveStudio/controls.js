"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsSetJoinRequests = exports.lsSetChatMode = void 0;
exports.enforceChatMode = enforceChatMode;
/**
 * LIVE STUDIO v2 — host chat / join controls.
 *   lsSetChatMode({streamId, mode: 'open'|'slow'|'followers', slowSeconds?})
 *   lsSetJoinRequests({streamId, open})
 * Host / co-host only. State lives on the stream doc (studioChatMode,
 * allowGuestRequests) and is enforced server-side in lsComment / lsRequestJoin.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const controls_logic_1 = require("./controls_logic");
const asData = (d) => (d && typeof d === 'object' ? d : {});
exports.lsSetChatMode = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const parsed = (0, controls_logic_1.parseChatMode)(data);
    if (!parsed.ok)
        throw new https_1.HttpsError('invalid-argument', parsed.reason);
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    await (0, shared_1.rateLimit)(streamId, uid, 'chatmode', 10, 60000);
    await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ studioChatMode: parsed.value, studioChatModeAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    await (0, shared_1.broadcast)(streamId, 'chat', {
        v: 1,
        type: 'system',
        id: `chatmode_${Date.now()}`,
        uid,
        name: '',
        avatarUrl: '',
        text: parsed.value.mode === 'slow'
            ? `Slow mode on: one comment every ${parsed.value.slowSeconds}s`
            : parsed.value.mode === 'followers'
                ? 'Followers-only chat is on'
                : 'Chat is open to everyone',
        kind: 'shared',
        ts: Date.now(),
    });
    return { ok: true, chatMode: parsed.value };
});
exports.lsSetJoinRequests = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    const uid = (0, shared_1.requireUid)(req);
    const data = asData(req.data);
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    if (typeof data.open !== 'boolean')
        throw new https_1.HttpsError('invalid-argument', 'open must be true or false.');
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    await (0, shared_1.rateLimit)(streamId, uid, 'joinreq_ctl', 10, 60000);
    await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ allowGuestRequests: data.open }, { merge: true });
    return { ok: true, open: data.open };
});
/**
 * Called by lsComment for every comment: enforces slow mode and
 * followers-only chat for non-managers. Throws HttpsError when refused.
 */
async function enforceChatMode(streamId, uid, role, hostId) {
    const streamSnap = await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).get();
    const mode = (0, controls_logic_1.readChatMode)(streamSnap.get('studioChatMode'));
    const need = (0, controls_logic_1.chatModeRequirement)(mode, role);
    if (need.kind === 'slow') {
        await (0, shared_1.rateLimit)(streamId, uid, 'cmt_slow', 1, need.seconds * 1000);
    }
    else if (need.kind === 'follower') {
        const rel = await (0, shared_1.db)().doc(`relationships/${(0, controls_logic_1.followDocId)(uid, hostId)}`).get();
        if (!rel.exists || !(0, controls_logic_1.isAcceptedFollow)(rel.get('status'))) {
            throw new https_1.HttpsError('permission-denied', 'Only followers can comment right now. Follow the host to join the chat.');
        }
    }
}
//# sourceMappingURL=controls.js.map