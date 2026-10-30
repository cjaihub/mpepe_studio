"use strict";
/**
 * LIVE STUDIO v2 — host entertainment tools (pure; no Firebase imports).
 * Polls, countdown timers, spotlight (pin a message on stage), celebrations
 * and a comment raffle. State lives in `live_streams/{id}/studio/fun`.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseSpotlightText = exports.pollAccepting = exports.FunError = exports.emptyFun = exports.MANAGER_OPS = exports.CELEBRATIONS = exports.FUN_LIMITS = void 0;
exports.parseOp = parseOp;
exports.newPoll = newPoll;
exports.applyVote = applyVote;
exports.newTimer = newTimer;
exports.parseCelebration = parseCelebration;
exports.raffleEntrants = raffleEntrants;
exports.pickWinner = pickWinner;
exports.FUN_LIMITS = {
    questionMax: 120,
    optionMax: 40,
    optionsMin: 2,
    optionsMax: 4,
    pollSecondsMin: 15,
    pollSecondsMax: 600,
    timerLabelMax: 40,
    timerSecondsMin: 5,
    timerSecondsMax: 3600,
    spotlightMax: 200,
    raffleWindowMs: 10 * 60 * 1000,
};
exports.CELEBRATIONS = ['confetti', 'hearts', 'fireworks'];
exports.MANAGER_OPS = [
    'pollStart',
    'pollEnd',
    'timerStart',
    'timerStop',
    'spotlight',
    'spotlightClear',
    'celebrate',
    'raffle',
];
const emptyFun = () => ({ poll: null, timer: null, spotlight: null, celebrate: null, raffle: null });
exports.emptyFun = emptyFun;
class FunError extends Error {
}
exports.FunError = FunError;
const CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f]/;
function text(v, name, max) {
    if (typeof v !== 'string')
        throw new FunError(`${name} is required.`);
    const t = v.trim();
    if (!t || t.length > max || CONTROL.test(t))
        throw new FunError(`${name} must be 1–${max} characters.`);
    return t;
}
function int(v, name, min, max) {
    if (typeof v !== 'number' || !Number.isFinite(v))
        throw new FunError(`${name} must be a number.`);
    return Math.min(max, Math.max(min, Math.round(v)));
}
function parseOp(v) {
    if (v === 'pollVote' || exports.MANAGER_OPS.includes(v))
        return v;
    throw new FunError('Unknown op.');
}
function newPoll(data, id, nowMs) {
    var _a;
    const question = text(data.question, 'question', exports.FUN_LIMITS.questionMax);
    const raw = Array.isArray(data.options) ? data.options : [];
    const options = raw.map((o, i) => text(o, `option ${i + 1}`, exports.FUN_LIMITS.optionMax));
    if (options.length < exports.FUN_LIMITS.optionsMin || options.length > exports.FUN_LIMITS.optionsMax) {
        throw new FunError(`A poll needs ${exports.FUN_LIMITS.optionsMin}–${exports.FUN_LIMITS.optionsMax} options.`);
    }
    if (new Set(options.map((o) => o.toLowerCase())).size !== options.length)
        throw new FunError('Options must be different.');
    const seconds = int((_a = data.seconds) !== null && _a !== void 0 ? _a : 60, 'seconds', exports.FUN_LIMITS.pollSecondsMin, exports.FUN_LIMITS.pollSecondsMax);
    return { id, question, options, counts: options.map(() => 0), startedAtMs: nowMs, endsAtMs: nowMs + seconds * 1000, open: true };
}
/** A poll accepts votes while open and before its end time. */
const pollAccepting = (p, nowMs) => !!p && p.open && nowMs < p.endsAtMs;
exports.pollAccepting = pollAccepting;
/** Moves one vote: [prev] (null = first vote) → [next]. Counts never go below 0. */
function applyVote(p, prev, next) {
    if (!Number.isInteger(next) || next < 0 || next >= p.options.length)
        throw new FunError('Pick one of the options.');
    if (prev === next)
        return p;
    const counts = [...p.counts];
    if (prev !== null && prev >= 0 && prev < counts.length)
        counts[prev] = Math.max(0, counts[prev] - 1);
    counts[next] += 1;
    return Object.assign(Object.assign({}, p), { counts });
}
function newTimer(data, nowMs) {
    const label = typeof data.label === 'string' && data.label.trim() ? text(data.label, 'label', exports.FUN_LIMITS.timerLabelMax) : 'Countdown';
    const seconds = int(data.seconds, 'seconds', exports.FUN_LIMITS.timerSecondsMin, exports.FUN_LIMITS.timerSecondsMax);
    return { label, startedAtMs: nowMs, endsAtMs: nowMs + seconds * 1000 };
}
function parseCelebration(v) {
    return exports.CELEBRATIONS.includes(v) ? v : 'confetti';
}
const parseSpotlightText = (v) => text(v, 'text', exports.FUN_LIMITS.spotlightMax);
exports.parseSpotlightText = parseSpotlightText;
/** Distinct commenters (not [excludeUid]) in comment order, newest window only. */
function raffleEntrants(comments, nowMs, excludeUids) {
    const seen = new Map();
    for (const c of comments) {
        if (!c.uid || excludeUids.includes(c.uid) || nowMs - c.ts > exports.FUN_LIMITS.raffleWindowMs)
            continue;
        if (!seen.has(c.uid))
            seen.set(c.uid, { uid: c.uid, name: c.name, avatarUrl: c.avatarUrl });
    }
    return [...seen.values()];
}
/** Uniform pick with [random] in [0, 1). */
function pickWinner(entrants, random) {
    if (!entrants.length)
        return null;
    return entrants[Math.min(entrants.length - 1, Math.floor(random * entrants.length))];
}
//# sourceMappingURL=fun_logic.js.map