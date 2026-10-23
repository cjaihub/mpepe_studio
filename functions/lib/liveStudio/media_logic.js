"use strict";
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PUBLISH_SOURCES = exports.ROOM_EMPTY_TIMEOUT_SECONDS = exports.TOKEN_TTL_SECONDS = void 0;
exports.grantForRole = grantForRole;
exports.tokenDecision = tokenDecision;
exports.mergeStartSettings = mergeStartSettings;
exports.buildInitialState = buildInitialState;
exports.profileFrom = profileFrom;
exports.buildHostMember = buildHostMember;
exports.buildStreamDoc = buildStreamDoc;
exports.stagePublishers = stagePublishers;
exports.canSetOwnMedia = canSetOwnMedia;
exports.parseOwnMedia = parseOwnMedia;
exports.wireState = wireState;
/**
 * LIVE STUDIO v2 — media pure logic (workstream #1, realtime media).
 * No Firestore / LiveKit imports so everything here is unit-testable.
 * See docs/live-studio/ARCHITECTURE.md §6–§7.
 */
const contracts_1 = require("./contracts");
/** Token lifetime: one long live plus margin (~6 h). */
exports.TOKEN_TTL_SECONDS = 6 * 60 * 60;
/** LiveKit closes an empty room after ~10 min (host app restarts survive). */
exports.ROOM_EMPTY_TIMEOUT_SECONDS = 10 * 60;
exports.PUBLISH_SOURCES = ['camera', 'microphone', 'screen_share'];
/**
 * Role → grant mapping (ARCHITECTURE §6).
 * - everyone joins and subscribes;
 * - only host / coHost / guest publish, and only camera, mic and screen share;
 * - `canPublishData` is false for everyone: all data goes through callables.
 */
function grantForRole(role, room) {
    const publish = role === 'host' || role === 'coHost' || role === 'guest';
    return {
        room,
        roomJoin: true,
        canSubscribe: true,
        canPublish: publish,
        canPublishData: false,
        canPublishSources: publish ? [...exports.PUBLISH_SOURCES] : [],
        canUpdateOwnMetadata: false,
    };
}
/** Decides whether a token may be minted. Blocked users and ended streams are refused. */
function tokenDecision(input) {
    if (input.blocked)
        return { ok: false, code: 'permission-denied', message: 'You are blocked from this live.' };
    if (input.status === 'ended')
        return { ok: false, code: 'failed-precondition', message: 'This live has ended.' };
    return { ok: true };
}
/**
 * Settings for a new live: the host's saved settings with the (partial) lsStart
 * argument on top, then normalized by settings_logic (the settings workstream
 * owns validation).
 */
function mergeStartSettings(saved, arg) {
    const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
    return Object.assign(Object.assign({}, obj(saved)), obj(arg));
}
/** Initial `studio/state` for a new live: host in the center, empty wall, goods table. */
function buildInitialState(a) {
    return {
        schemaVersion: contracts_1.SCHEMA_VERSION,
        streamId: a.streamId,
        hostId: a.hostId,
        title: a.title,
        status: 'live',
        seq: 0,
        settings: a.settings,
        stage: Object.assign(Object.assign({}, (0, contracts_1.emptyStage)(a.hostId)), { updatedAtMs: a.nowMs, updatedBy: a.hostId }),
        table: { mode: 'goods', goods: null, screen: null, watch: null },
        counts: { viewers: 0, participants: 1, loves: 0, sparkles: 0, shares: 0 },
    };
}
/** Display name / avatar from a `users/{uid}` doc, falling back to auth token claims. */
function profileFrom(user, token) {
    const s = (v) => (typeof v === 'string' && v.trim().length > 0 ? v.trim() : '');
    const u = user !== null && user !== void 0 ? user : {};
    return {
        displayName: (s(u.displayName) || s(u.username) || s(token === null || token === void 0 ? void 0 : token.name) || 'Oneova creator').slice(0, 80),
        avatarUrl: s(u.avatarUrl) || s(u.photoUrl) || s(u.photoURL) || s(token === null || token === void 0 ? void 0 : token.picture),
    };
}
function buildHostMember(uid, p, nowMs) {
    return {
        uid,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        accent: contracts_1.ACCENT_PALETTE[0],
        role: 'host',
        micOn: true,
        camOn: true,
        chatMuted: false,
        joinedAtMs: nowMs,
    };
}
/** Fields of `live_streams/{id}` required by the v1 rules + the v2 markers. */
function buildStreamDoc(a) {
    return {
        id: a.streamId,
        hostId: a.hostId,
        hostDisplayName: a.profile.displayName,
        hostAvatarUrl: a.profile.avatarUrl,
        title: a.title,
        status: 'live',
        layoutMode: 'studio',
        studioVersion: 2,
        audienceMode: 'public',
        viewerCount: 0,
        totalLikes: 0,
        totalComments: 0,
    };
}
/** Everyone on stage (center, wall, overflow). */
function stagePublishers(s) {
    return [s.stage.centerUid, ...s.stage.wall.filter((u) => !!u), ...s.stage.overflow].filter((u) => !!u);
}
/** lsSetOwnMedia precondition: a publishing role AND currently on stage. */
function canSetOwnMedia(role, uid, s) {
    if (role === 'viewer')
        return false;
    return stagePublishers(s).includes(uid);
}
/** Validates the two booleans of lsSetOwnMedia. Returns null when invalid. */
function parseOwnMedia(data) {
    const d = (data && typeof data === 'object' ? data : {});
    if (typeof d.micOn !== 'boolean' || typeof d.camOn !== 'boolean')
        return null;
    return { micOn: d.micOn, camOn: d.camOn };
}
/** Strips Firestore-only fields (Timestamps) so the state is JSON-safe for callables. */
function wireState(raw) {
    const { updatedAt, createdAt } = raw, rest = __rest(raw, ["updatedAt", "createdAt"]);
    return rest;
}
//# sourceMappingURL=media_logic.js.map