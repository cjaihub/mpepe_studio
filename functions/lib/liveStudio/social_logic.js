"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SYSTEM_TEXT = exports.systemKindForReaction = exports.reactionField = exports.COUNTER_SHARDS = exports.FLUSH_GRACE_MS = exports.JOIN_LINE_INTERVAL_MS = exports.LARGE_ROOM_VIEWERS = exports.COUNTS_STATE_INTERVAL_MS = exports.SYSTEM_LINE_USER_INTERVAL_MS = exports.LeaseMemo = exports.SecondWindowCounter = exports.epochSecond = exports.COMMENT_GATE_SHARDS = exports.MAX_MUTE_MINUTES = exports.DEFAULT_MASKED_TERMS = exports.DEFAULT_BLOCKED_TERMS = void 0;
exports.normalizeCommentText = normalizeCommentText;
exports.isValidClientId = isValidClientId;
exports.commentDocId = commentDocId;
exports.foldForMatching = foldForMatching;
exports.blockListModerator = blockListModerator;
exports.composeModerators = composeModerators;
exports.setCommentModerator = setCommentModerator;
exports.moderateComment = moderateComment;
exports.parseMuteMinutes = parseMuteMinutes;
exports.muteUntil = muteUntil;
exports.isChatMuted = isChatMuted;
exports.canDeleteComment = canDeleteComment;
exports.canMuteChat = canMuteChat;
exports.shardBudget = shardBudget;
exports.gateStep = gateStep;
exports.shouldBroadcastComment = shouldBroadcastComment;
exports.throttleDue = throttleDue;
exports.parseReaction = parseReaction;
exports.pickShard = pickShard;
exports.sumShards = sumShards;
exports.reactionDeltas = reactionDeltas;
exports.flushDelayMs = flushDelayMs;
exports.simulateAggregation = simulateAggregation;
exports.streamIdFromRoom = streamIdFromRoom;
exports.resolveViewers = resolveViewers;
exports.computeParticipants = computeParticipants;
exports.stagePublishers = stagePublishers;
exports.countsChanged = countsChanged;
exports.joinLineMode = joinLineMode;
exports.systemLineId = systemLineId;
exports.displayNameOf = displayNameOf;
exports.avatarOf = avatarOf;
/**
 * LIVE STUDIO v2 — realtime social, pure logic (workstream #2).
 *
 * No Firestore / LiveKit imports here: everything is deterministic given its
 * inputs (clock values are passed in), so it is unit-tested in
 * `__tests__/social_logic.test.ts`. The I/O lives in `social.ts`.
 */
const contracts_1 = require("./contracts");
/**
 * Collapses every whitespace run (including newlines and tabs) to one space,
 * strips control / zero-width characters, trims, and enforces the length cap.
 */
function normalizeCommentText(raw, max = contracts_1.Limits.commentMaxLength) {
    if (typeof raw !== 'string')
        return { ok: false, reason: 'Comment text is required.' };
    const text = raw
        // eslint-disable-next-line no-control-regex
        .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‍⁠﻿]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
    if (text.length === 0)
        return { ok: false, reason: 'Comment text is required.' };
    if ([...text].length > max)
        return { ok: false, reason: `Comments are limited to ${max} characters.` };
    return { ok: true, text };
}
/** Client-supplied idempotency key: `[A-Za-z0-9_-]{8,40}`. */
function isValidClientId(v) {
    return typeof v === 'string' && /^[A-Za-z0-9_-]{8,40}$/.test(v);
}
/**
 * Deterministic comment id when the client sends a `clientId`, so its
 * optimistic row has the same id as the server echo, and retries are
 * idempotent. Mirrored in Dart (`studioCommentDocId`).
 */
function commentDocId(uid, clientId) {
    return `${uid}_${clientId}`;
}
/** Lower-cases, strips diacritics and maps common leetspeak to letters. */
function foldForMatching(s) {
    const leet = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', $: 's', '!': 'i' };
    return s
        .normalize('NFKD')
        .replace(/[̀-ͯ]/g, '')
        .toLowerCase()
        .replace(/[013457@$!]/g, (c) => { var _a; return (_a = leet[c]) !== null && _a !== void 0 ? _a : c; });
}
/**
 * Default terms. Deliberately small: production lists belong in config and
 * are passed to [blockListModerator] (see `social.ts` → `setCommentModerator`).
 */
exports.DEFAULT_BLOCKED_TERMS = ['kill yourself', 'kys', 'go die'];
/** Terms that are masked (replaced with •) instead of rejecting the comment. */
exports.DEFAULT_MASKED_TERMS = [];
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/**
 * Basic block-list moderator. Whole-word / whole-phrase match on the folded
 * text: [blocked] terms reject the comment, [masked] terms are replaced with
 * bullets of the same length.
 */
function blockListModerator(opts = {}) {
    var _a, _b;
    const build = (terms) => terms
        .map((t) => foldForMatching(t.trim()))
        .filter((t) => t.length > 0)
        .map((t) => new RegExp(`(^|[^a-z0-9])(${escapeRe(t).replace(/ /g, '\\s+')})(?=$|[^a-z0-9])`, 'g'));
    const blocked = build((_a = opts.blocked) !== null && _a !== void 0 ? _a : exports.DEFAULT_BLOCKED_TERMS);
    const masked = build((_b = opts.masked) !== null && _b !== void 0 ? _b : exports.DEFAULT_MASKED_TERMS);
    return (text) => {
        const folded = foldForMatching(text);
        for (const re of blocked) {
            re.lastIndex = 0;
            if (re.test(folded))
                return { allow: false, reason: 'This comment breaks the community guidelines.', text };
        }
        if (masked.length === 0 || folded.length !== text.length)
            return { allow: true, text };
        // Folding kept the length, so indexes line up with the original text.
        const chars = [...text];
        for (const re of masked) {
            re.lastIndex = 0;
            let m;
            while ((m = re.exec(folded)) !== null) {
                const start = m.index + m[1].length;
                for (let i = start; i < start + m[2].length; i++)
                    chars[i] = '•';
            }
        }
        return { allow: true, text: chars.join('') };
    };
}
/** Runs moderators in order; the first rejection wins, masks accumulate. */
function composeModerators(...mods) {
    return async (text, uid) => {
        let current = text;
        for (const m of mods) {
            const v = await m(current, uid);
            if (!v.allow)
                return v;
            current = v.text;
        }
        return { allow: true, text: current };
    };
}
let activeModerator = blockListModerator();
/**
 * Extension point: replace the moderator (e.g. compose the block list with a
 * remote classifier). Called once at module load by whoever wires it.
 */
function setCommentModerator(m) {
    activeModerator = m;
}
/** The moderation hook `lsComment` calls. */
function moderateComment(text, uid) {
    return Promise.resolve(activeModerator(text, uid));
}
// ─── Comments: mute / permissions ───────────────────────────────────────────
exports.MAX_MUTE_MINUTES = 24 * 60;
/** Returns minutes as an integer in 0..MAX_MUTE_MINUTES, or null if invalid. 0 = unmute. */
function parseMuteMinutes(v) {
    if (typeof v !== 'number' || !Number.isFinite(v))
        return null;
    const m = Math.floor(v);
    return m < 0 || m > exports.MAX_MUTE_MINUTES ? null : m;
}
function muteUntil(nowMs, minutes) {
    return nowMs + minutes * 60000;
}
function isChatMuted(memberChatMuted, muteUntilMs, nowMs) {
    return memberChatMuted === true || (typeof muteUntilMs === 'number' && muteUntilMs > nowMs);
}
/** Host/co-host may delete any comment; anyone may delete their own. */
function canDeleteComment(actorRole, actorUid, authorUid) {
    return (0, contracts_1.isManager)(actorRole) || (actorUid.length > 0 && actorUid === authorUid);
}
/** Host/co-host may mute chat; a co-host cannot mute the host; nobody mutes themselves. */
function canMuteChat(actorRole, actorUid, targetRole, targetUid) {
    if (!(0, contracts_1.isManager)(actorRole) || actorUid === targetUid)
        return false;
    if (targetRole === 'host')
        return false;
    return true;
}
// ─── Comments: broadcast sampling ───────────────────────────────────────────
/** Number of Firestore budget shards for the per-second comment gate. */
exports.COMMENT_GATE_SHARDS = 5;
/** Each shard's share of the per-second budget (rounded up, ≥ 1). */
function shardBudget(total = contracts_1.Limits.commentBroadcastPerSecond, shards = exports.COMMENT_GATE_SHARDS) {
    return Math.max(1, Math.ceil(total / shards));
}
const epochSecond = (nowMs) => Math.floor(nowMs / 1000);
exports.epochSecond = epochSecond;
/**
 * In-memory fixed 1-second window counter, keyed (e.g. by stream). Best
 * effort: it only sees this instance's traffic. Old keys are pruned lazily.
 */
class SecondWindowCounter {
    constructor(maxKeys = 2000) {
        this.maxKeys = maxKeys;
        this.windows = new Map();
    }
    /** Records one hit and returns the count in the current second (incl. this one). */
    hit(key, nowMs) {
        const sec = (0, exports.epochSecond)(nowMs);
        const w = this.windows.get(key);
        if (!w || w.sec !== sec) {
            if (this.windows.size >= this.maxKeys)
                this.prune(sec);
            this.windows.set(key, { sec, n: 1 });
            return 1;
        }
        w.n += 1;
        return w.n;
    }
    count(key, nowMs) {
        const w = this.windows.get(key);
        return w && w.sec === (0, exports.epochSecond)(nowMs) ? w.n : 0;
    }
    prune(sec) {
        for (const [k, w] of this.windows)
            if (w.sec !== sec)
                this.windows.delete(k);
        if (this.windows.size >= this.maxKeys)
            this.windows.clear();
    }
}
exports.SecondWindowCounter = SecondWindowCounter;
/** Pure decision for one per-second budget window (`{sec, n}` doc state). */
function gateStep(doc, nowMs, budget) {
    var _a;
    const sec = (0, exports.epochSecond)(nowMs);
    if (!doc || doc.sec !== sec)
        return { allow: true, next: { sec, n: 1 } };
    const n = (_a = doc.n) !== null && _a !== void 0 ? _a : 0;
    if (n >= budget)
        return { allow: false, next: null };
    return { allow: true, next: { sec, n: n + 1 } };
}
/**
 * The sampling decision for one comment. Host/co-host comments are always
 * broadcast. Others are broadcast while this instance's local count is
 * within budget AND the global (Firestore) gate allows it.
 */
function shouldBroadcastComment(input) {
    var _a;
    if ((0, contracts_1.isManager)(input.role))
        return true;
    const budget = (_a = input.budget) !== null && _a !== void 0 ? _a : contracts_1.Limits.commentBroadcastPerSecond;
    if (input.localCountThisSecond > budget)
        return false;
    return input.globalAllow === true;
}
// ─── Leases / throttles ─────────────────────────────────────────────────────
/** True when an action last done at [lastMs] may run again at [nowMs]. */
function throttleDue(lastMs, nowMs, intervalMs) {
    if (typeof lastMs !== 'number' || !Number.isFinite(lastMs))
        return true;
    // A clock step backwards (lastMs in the future) beyond one interval resets the lease.
    if (lastMs - nowMs > intervalMs)
        return true;
    return nowMs - lastMs >= intervalMs;
}
/**
 * Per-instance memo of "not due before T" for leases, so hot paths skip the
 * Firestore read entirely while a lease is known to be held.
 */
class LeaseMemo {
    constructor(maxKeys = 5000) {
        this.maxKeys = maxKeys;
        this.until = new Map();
    }
    blocked(key, nowMs) {
        const u = this.until.get(key);
        if (u === undefined)
            return false;
        if (nowMs >= u) {
            this.until.delete(key);
            return false;
        }
        return true;
    }
    hold(key, untilMs) {
        if (this.until.size >= this.maxKeys)
            this.until.clear();
        this.until.set(key, untilMs);
    }
}
exports.LeaseMemo = LeaseMemo;
/** System lines from reactions/shares: at most one per user per this window. */
exports.SYSTEM_LINE_USER_INTERVAL_MS = 10000;
/** studio/state `counts` is patched at most this often. */
exports.COUNTS_STATE_INTERVAL_MS = 10000;
/** Above this many viewers, `joined` lines are sampled. */
exports.LARGE_ROOM_VIEWERS = 100;
/** Sampled `joined` lines: at most one per this window per stream. */
exports.JOIN_LINE_INTERVAL_MS = 1000;
/** Extra wait after a reaction window closes, to absorb clock skew between instances. */
exports.FLUSH_GRACE_MS = 60;
// ─── Reactions ──────────────────────────────────────────────────────────────
exports.COUNTER_SHARDS = 10;
function parseReaction(kind, n, max = contracts_1.Limits.reactionMaxPerCall) {
    if (kind !== 'love' && kind !== 'sparkles')
        return { ok: false, reason: 'kind must be love or sparkles.' };
    if (typeof n !== 'number' || !Number.isInteger(n) || n < 1 || n > max) {
        return { ok: false, reason: `n must be an integer from 1 to ${max}.` };
    }
    return { ok: true, kind, n };
}
/** Counter field in the shard docs. */
const reactionField = (k) => (k === 'love' ? 'loves' : 'sparkles');
exports.reactionField = reactionField;
const systemKindForReaction = (k) => (k === 'love' ? 'love' : 'sparkles');
exports.systemKindForReaction = systemKindForReaction;
exports.SYSTEM_TEXT = {
    joined: 'joined the live',
    love: 'sent love',
    sparkles: 'sent sparkles',
    shared: 'shared this live',
    requested: 'requested to join the stage',
    onStage: 'is on stage',
};
/** Picks a shard index in 0..shards-1 from a random number in [0, 1). */
function pickShard(rand, shards = exports.COUNTER_SHARDS) {
    const i = Math.floor(rand * shards);
    return Math.min(shards - 1, Math.max(0, i));
}
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
/** Sums shard docs (missing docs/fields count as 0). */
function sumShards(docs) {
    const t = { loves: 0, sparkles: 0, shares: 0, viewers: 0 };
    for (const d of docs) {
        if (!d)
            continue;
        t.loves += num(d.loves);
        t.sparkles += num(d.sparkles);
        t.shares += num(d.shares);
        t.viewers += num(d.viewers);
    }
    return t;
}
/**
 * Deltas since the last flush. The flush doc remembers the totals it last
 * broadcast, so nothing is ever lost: increments that land after a flush's
 * read simply show up in the next window's delta.
 */
function reactionDeltas(totals, flushed) {
    return {
        loves: Math.max(0, totals.loves - num(flushed === null || flushed === void 0 ? void 0 : flushed.loves)),
        sparkles: Math.max(0, totals.sparkles - num(flushed === null || flushed === void 0 ? void 0 : flushed.sparkles)),
    };
}
/** How long the flush leader waits before reading the shards. */
function flushDelayMs(leaseAtMs, nowMs, windowMs = contracts_1.Limits.reactionAggregateWindowMs) {
    return Math.max(0, leaseAtMs + windowMs + exports.FLUSH_GRACE_MS - nowMs);
}
/**
 * Simulates the aggregation protocol (used by tests and as the reference
 * for `social.ts`): given call timestamps, returns the flush times. Each call
 * first increments, then tries to claim the window lease; only a claimer
 * schedules a flush at `leaseAt + window`.
 */
function simulateAggregation(callTimesMs, windowMs = contracts_1.Limits.reactionAggregateWindowMs) {
    let leaseAt;
    const flushes = [];
    for (const t of [...callTimesMs].sort((a, b) => a - b)) {
        if (throttleDue(leaseAt, t, windowMs)) {
            leaseAt = t;
            flushes.push(t + windowMs);
        }
    }
    return flushes;
}
// ─── Presence / counts ──────────────────────────────────────────────────────
/** `studio_<streamId>` → streamId, or null for rooms that are not studio rooms. */
function streamIdFromRoom(room) {
    if (!room || !room.startsWith('studio_'))
        return null;
    const id = room.slice('studio_'.length);
    return /^[A-Za-z0-9_-]{1,128}$/.test(id) ? id : null;
}
/**
 * Viewer count. LiveKit's `room.numParticipants` (when the webhook carries
 * it) is authoritative; otherwise the ±1 counter maintained from join/leave
 * webhooks is used, clamped at 0 (webhooks can arrive out of order).
 */
function resolveViewers(roomNumParticipants, counter) {
    if (typeof roomNumParticipants === 'number' && roomNumParticipants > 0)
        return roomNumParticipants;
    return Math.max(0, Math.round(counter));
}
/** Participants = stage members + co-hosts + pending requests (ARCHITECTURE Q4). */
function computeParticipants(stagePublishers, coHostUids, pendingRequests) {
    const s = new Set();
    for (const u of stagePublishers)
        if (u)
            s.add(u);
    for (const u of coHostUids)
        if (u)
            s.add(u);
    return s.size + Math.max(0, pendingRequests);
}
/** Publishers on stage (center + wall + overflow), from a raw stage object. */
function stagePublishers(stage) {
    var _a, _b;
    if (!stage)
        return [];
    return [
        ...(stage.centerUid ? [stage.centerUid] : []),
        ...(((_a = stage.wall) !== null && _a !== void 0 ? _a : []).filter((u) => typeof u === 'string' && u.length > 0)),
        ...(((_b = stage.overflow) !== null && _b !== void 0 ? _b : []).filter((u) => typeof u === 'string' && u.length > 0)),
    ];
}
function countsChanged(prev, next) {
    return !prev || prev.viewers !== next.viewers || prev.participants !== next.participants;
}
/**
 * Whether a `joined` line should be emitted. Small rooms: always. Large
 * rooms: only when the per-stream 1/s lease is due (the caller then claims it).
 */
function joinLineMode(viewers, threshold = exports.LARGE_ROOM_VIEWERS) {
    return viewers <= threshold ? 'always' : 'sampled';
}
/** Random-ish id for broadcast-only system lines. */
function systemLineId(nowMs, rand) {
    return `sys_${nowMs.toString(36)}_${Math.floor(rand * 36 ** 6).toString(36).padStart(6, '0')}`;
}
/** Display name from a users/{uid} doc (same order as the Dart repositories). */
function displayNameOf(d, fallback = 'Someone') {
    for (const k of ['fullName', 'displayName', 'username', 'name']) {
        const v = d === null || d === void 0 ? void 0 : d[k];
        if (typeof v === 'string' && v.trim().length > 0)
            return v.trim().slice(0, 60);
    }
    return fallback;
}
function avatarOf(d) {
    for (const k of ['avatarUrl', 'photoUrl', 'photoURL']) {
        const v = d === null || d === void 0 ? void 0 : d[k];
        if (typeof v === 'string' && v.length > 0)
            return v;
    }
    return '';
}
//# sourceMappingURL=social_logic.js.map