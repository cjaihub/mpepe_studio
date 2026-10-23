"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isAcceptedFollow = exports.followDocId = exports.SLOW_DEFAULT_S = exports.SLOW_MAX_S = exports.SLOW_MIN_S = exports.DEFAULT_CHAT_MODE = void 0;
exports.parseChatMode = parseChatMode;
exports.readChatMode = readChatMode;
exports.chatModeApplies = chatModeApplies;
exports.chatModeRequirement = chatModeRequirement;
/**
 * LIVE STUDIO v2 — chat mode and join-request controls (pure logic).
 * Used by the security advisories' one-tap actions (security.ts) and the host.
 */
const contracts_1 = require("./contracts");
exports.DEFAULT_CHAT_MODE = { mode: 'open', slowSeconds: 0 };
exports.SLOW_MIN_S = 5;
exports.SLOW_MAX_S = 300;
exports.SLOW_DEFAULT_S = 15;
function parseChatMode(data) {
    const mode = data.mode;
    if (mode !== 'open' && mode !== 'slow' && mode !== 'followers') {
        return { ok: false, reason: "mode must be 'open', 'slow' or 'followers'." };
    }
    if (mode !== 'slow')
        return { ok: true, value: { mode, slowSeconds: 0 } };
    const raw = data.slowSeconds === undefined ? exports.SLOW_DEFAULT_S : data.slowSeconds;
    if (typeof raw !== 'number' || !Number.isFinite(raw))
        return { ok: false, reason: 'slowSeconds must be a number.' };
    return { ok: true, value: { mode, slowSeconds: Math.min(exports.SLOW_MAX_S, Math.max(exports.SLOW_MIN_S, Math.round(raw))) } };
}
function readChatMode(raw) {
    if (!raw || typeof raw !== 'object')
        return exports.DEFAULT_CHAT_MODE;
    const r = raw;
    const p = parseChatMode(r);
    return p.ok ? p.value : exports.DEFAULT_CHAT_MODE;
}
/** Host and co-hosts are never limited by chat mode. */
function chatModeApplies(role) {
    return !(0, contracts_1.isManager)(role);
}
/** What lsComment must check for a non-manager under [mode]. */
function chatModeRequirement(mode, role) {
    if (!chatModeApplies(role))
        return { kind: 'none' };
    if (mode.mode === 'slow')
        return { kind: 'slow', seconds: mode.slowSeconds };
    if (mode.mode === 'followers')
        return { kind: 'follower' };
    return { kind: 'none' };
}
/** relationships/{follower}_{host} with status accepted (RelationshipRepository). */
const followDocId = (followerUid, hostId) => `${followerUid}_${hostId}`;
exports.followDocId = followDocId;
const isAcceptedFollow = (status) => status === 'accepted';
exports.isAcceptedFollow = isAcceptedFollow;
//# sourceMappingURL=controls_logic.js.map