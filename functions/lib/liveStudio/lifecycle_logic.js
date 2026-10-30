"use strict";
/**
 * LIVE STUDIO v2 — live lifecycle rules (pure; no Firebase imports).
 *
 * - Setup-wizard extras accepted by lsStart (category, cover, audience, join requests).
 * - When a live is orphaned (host app killed / network gone) so the sweeper
 *   (lifecycle.ts) closes it server-side and it never hangs.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.AUDIENCE_MODES = exports.CATEGORY_MAX_LENGTH = exports.FIRST_HEARTBEAT_GRACE_MS = exports.NO_HEARTBEAT_MAX_MS = exports.HOST_LEFT_GRACE_MS = exports.HEARTBEAT_STALE_MS = exports.HEARTBEAT_INTERVAL_MS = void 0;
exports.parseStartExtras = parseStartExtras;
exports.orphanReason = orphanReason;
exports.toMs = toMs;
/** The host app pings lsHeartbeat this often while live. */
exports.HEARTBEAT_INTERVAL_MS = 20000;
/** No heartbeat for this long → the host is gone (covers ~4 missed pings + a short reconnect). */
exports.HEARTBEAT_STALE_MS = 90000;
/** LiveKit saw the host leave the room and they did not come back within this grace. */
exports.HOST_LEFT_GRACE_MS = 60000;
/** A live with no heartbeat at all (older app builds) is closed after this long. */
exports.NO_HEARTBEAT_MAX_MS = 12 * 60 * 60 * 1000;
/** A live with no heartbeat yet gets this long to send its first one before
 *  the host-left signal alone can end it. */
exports.FIRST_HEARTBEAT_GRACE_MS = 2 * 60 * 1000;
exports.CATEGORY_MAX_LENGTH = 40;
/** `private` is accepted for older clients but treated like `public` (no invite list yet). */
exports.AUDIENCE_MODES = ['public', 'followers', 'private'];
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;
/**
 * Optional setup-wizard fields of lsStart. Invalid values fall back to the
 * defaults instead of failing the start (older clients send none of them).
 */
function parseStartExtras(data) {
    const d = (data && typeof data === 'object' && !Array.isArray(data) ? data : {});
    const cat = typeof d.category === 'string' ? d.category.trim() : '';
    const category = cat && cat.length <= exports.CATEGORY_MAX_LENGTH && !CONTROL_CHARS.test(cat) ? cat : null;
    const cover = typeof d.coverUrl === 'string' ? d.coverUrl.trim() : '';
    const coverUrl = cover.startsWith('https://') && cover.length <= 2048 ? cover : null;
    const audienceMode = exports.AUDIENCE_MODES.includes(d.audienceMode)
        ? d.audienceMode
        : 'public';
    const allowGuestRequests = typeof d.allowGuestRequests === 'boolean' ? d.allowGuestRequests : true;
    return { category, coverUrl, audienceMode, allowGuestRequests };
}
/** Why [live] should be closed now, or null when it is healthy (or already ended). */
function orphanReason(live, nowMs) {
    if (live.status !== 'live')
        return null;
    if (live.hostLeftMs !== null && nowMs - live.hostLeftMs >= exports.HOST_LEFT_GRACE_MS) {
        // A fresh heartbeat after the leave means the host is back on another connection.
        if (live.heartbeatMs === null || live.heartbeatMs < live.hostLeftMs) {
            if (live.heartbeatMs !== null || live.createdMs === null || nowMs - live.createdMs >= exports.FIRST_HEARTBEAT_GRACE_MS) {
                return 'host_left';
            }
        }
    }
    if (live.heartbeatMs !== null) {
        return nowMs - live.heartbeatMs >= exports.HEARTBEAT_STALE_MS ? 'timeout' : null;
    }
    if (live.createdMs !== null && nowMs - live.createdMs >= exports.NO_HEARTBEAT_MAX_MS)
        return 'timeout';
    return null;
}
/** Milliseconds of a Firestore Timestamp / Date / number, else null. */
function toMs(v) {
    if (typeof v === 'number' && Number.isFinite(v))
        return v;
    if (v instanceof Date)
        return v.getTime();
    if (v && typeof v === 'object' && typeof v.toMillis === 'function') {
        return v.toMillis();
    }
    return null;
}
//# sourceMappingURL=lifecycle_logic.js.map