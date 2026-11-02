"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RATES = exports.MAX_POSITION_MS = exports.WatchError = exports.EMPTY_WATCH = void 0;
exports.isVideoId = isVideoId;
exports.validateBrowserUrl = validateBrowserUrl;
exports.parseWatchOp = parseWatchOp;
exports.targetPositionMs = targetPositionMs;
exports.normalizeWatch = normalizeWatch;
exports.applyWatchOp = applyWatchOp;
exports.sanitizeYouTubeQuery = sanitizeYouTubeQuery;
exports.fromYouTubeItem = fromYouTubeItem;
/**
 * LIVE STUDIO v2 — "Watch together" layer: pure logic (no Firestore, no fetch).
 *
 * The host (or a co-host) puts a YouTube video or a web page on a shared
 * layer above the stage. Their camera keeps streaming; nothing is re-streamed
 * into LiveKit. Every viewer plays the same thing locally (YouTube through the
 * official IFrame player) and follows `live_streams/{id}/studio/watch`:
 *
 *   target = positionMs + (serverNow − anchorServerMs) × rate   (while playing)
 *
 * Unit-tested in __tests__/watch_logic.test.ts; watch.ts does the I/O.
 */
const linkSafety_1 = require("../guard/linkSafety");
exports.EMPTY_WATCH = {
    kind: null,
    youtube: null,
    browser: null,
    state: 'paused',
    positionMs: 0,
    rate: 1,
    anchorServerMs: 0,
    by: '',
    rev: 0,
    updatedAtMs: 0,
};
class WatchError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
}
exports.WatchError = WatchError;
exports.MAX_POSITION_MS = 24 * 60 * 60 * 1000;
exports.RATES = [0.5, 0.75, 1, 1.25, 1.5, 2];
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const MAX_URL = 2000;
const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
function isVideoId(v) {
    return typeof v === 'string' && VIDEO_ID.test(v);
}
function position(v) {
    if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > exports.MAX_POSITION_MS) {
        throw new WatchError('invalid-argument', 'positionMs must be a number of milliseconds.');
    }
    return Math.round(v);
}
/** Only https://i.ytimg.com thumbnails are kept (they come from our search). */
function thumb(v) {
    const s = str(v, 300);
    return /^https:\/\/i\d?\.ytimg\.com\//.test(s) ? s : '';
}
/**
 * Validates a page for the shared browser: https only, a real public host
 * (no IP, localhost or private names), not a look-alike / phishing address.
 * Returns the normalized URL.
 */
function validateBrowserUrl(raw) {
    var _a;
    const s = str(raw, MAX_URL + 1);
    if (!s || s.length > MAX_URL)
        throw new WatchError('invalid-argument', 'Enter a web address.');
    let u;
    try {
        u = new URL(s);
    }
    catch (_b) {
        throw new WatchError('invalid-argument', 'That is not a web address.');
    }
    if (u.protocol !== 'https:')
        throw new WatchError('invalid-argument', 'Only secure (https) pages can be shared.');
    if (u.username || u.password)
        throw new WatchError('invalid-argument', 'Addresses with a login inside cannot be shared.');
    const host = u.hostname.toLowerCase();
    if (!host.includes('.') ||
        host === 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        /^\d{1,3}(\.\d{1,3}){3}$/.test(host) ||
        host.startsWith('[')) {
        throw new WatchError('invalid-argument', 'Only public websites can be shared.');
    }
    const finding = (0, linkSafety_1.analyzeUrl)(u.toString());
    if (finding && finding.points >= 40) {
        throw new WatchError('failed-precondition', `This page cannot be shared: ${(_a = finding.reasons[0]) !== null && _a !== void 0 ? _a : 'it looks unsafe'}.`);
    }
    return u.toString();
}
/** Parses an `lsWatch` request body (everything except streamId). */
function parseWatchOp(data) {
    switch (data.op) {
        case 'youtube': {
            if (!isVideoId(data.videoId))
                throw new WatchError('invalid-argument', 'videoId must be a YouTube video id.');
            return {
                op: 'youtube',
                video: {
                    videoId: data.videoId,
                    title: str(data.title, 200),
                    channel: str(data.channel, 100),
                    thumbUrl: thumb(data.thumbUrl),
                },
            };
        }
        case 'browser':
            return { op: 'browser', url: validateBrowserUrl(data.url) };
        case 'play':
        case 'pause':
        case 'seek':
            return { op: data.op, positionMs: position(data.positionMs) };
        case 'rate': {
            const r = data.rate;
            if (typeof r !== 'number' || !exports.RATES.includes(r)) {
                throw new WatchError('invalid-argument', `rate must be one of ${exports.RATES.join(', ')}.`);
            }
            return { op: 'rate', rate: r };
        }
        case 'ended':
            return { op: 'ended' };
        case 'stop':
            return { op: 'stop' };
        default:
            throw new WatchError('invalid-argument', 'Unknown watch op.');
    }
}
/** Where playback is at [nowMs] (server clock). */
function targetPositionMs(w, nowMs) {
    if (w.state !== 'playing')
        return w.positionMs;
    return Math.max(0, w.positionMs + Math.round((nowMs - w.anchorServerMs) * w.rate));
}
/** Normalizes a stored doc (missing / older shape → [EMPTY_WATCH] fields). */
function normalizeWatch(raw) {
    if (!raw)
        return Object.assign({}, exports.EMPTY_WATCH);
    const kind = raw.kind === 'youtube' || raw.kind === 'browser' ? raw.kind : null;
    const yt = raw.youtube;
    const br = raw.browser;
    const state = raw.state === 'playing' || raw.state === 'ended' ? raw.state : 'paused';
    const num = (v, d) => (typeof v === 'number' && Number.isFinite(v) ? v : d);
    return {
        kind,
        youtube: yt && isVideoId(yt.videoId)
            ? { videoId: yt.videoId, title: str(yt.title, 200), channel: str(yt.channel, 100), thumbUrl: thumb(yt.thumbUrl) }
            : null,
        browser: br && typeof br.url === 'string' ? { url: br.url } : null,
        state,
        positionMs: num(raw.positionMs, 0),
        rate: num(raw.rate, 1),
        anchorServerMs: num(raw.anchorServerMs, 0),
        by: str(raw.by, 128),
        rev: num(raw.rev, 0),
        updatedAtMs: num(raw.updatedAtMs, 0),
    };
}
/** Applies [op] by [by] at server time [nowMs]. Returns the new doc. */
function applyWatchOp(cur, op, by, nowMs) {
    const stamp = (next) => (Object.assign(Object.assign(Object.assign({}, cur), next), { by, rev: cur.rev + 1, updatedAtMs: nowMs }));
    switch (op.op) {
        case 'youtube':
            // Starts playing from 0: viewers seek to the moving target as they load.
            return stamp({
                kind: 'youtube',
                youtube: op.video,
                browser: null,
                state: 'playing',
                positionMs: 0,
                rate: 1,
                anchorServerMs: nowMs,
            });
        case 'browser':
            return stamp({ kind: 'browser', browser: { url: op.url }, youtube: null, state: 'paused', positionMs: 0, anchorServerMs: nowMs });
        case 'stop':
            return stamp(Object.assign(Object.assign({}, exports.EMPTY_WATCH), { rev: cur.rev + 1 }));
        default:
            break;
    }
    if (cur.kind !== 'youtube')
        throw new WatchError('failed-precondition', 'No video is playing.');
    switch (op.op) {
        case 'play':
            return stamp({ state: 'playing', positionMs: op.positionMs, anchorServerMs: nowMs });
        case 'pause':
            return stamp({ state: 'paused', positionMs: op.positionMs, anchorServerMs: nowMs });
        case 'seek':
            return stamp({ positionMs: op.positionMs, anchorServerMs: nowMs });
        case 'rate':
            return stamp({ rate: op.rate, positionMs: targetPositionMs(cur, nowMs), anchorServerMs: nowMs });
        case 'ended':
            return stamp({ state: 'ended', positionMs: targetPositionMs(cur, nowMs), anchorServerMs: nowMs });
    }
}
function sanitizeYouTubeQuery(v) {
    return str(v, 100).replace(/[\u0000-\u001f]/g, ' ');
}
const decodeEntities = (s) => s
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
/** Maps one `search.list` item (YouTube Data API v3) to a hit; null when unusable. */
function fromYouTubeItem(raw) {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h;
    const item = raw;
    const videoId = (_a = item === null || item === void 0 ? void 0 : item.id) === null || _a === void 0 ? void 0 : _a.videoId;
    if (!isVideoId(videoId))
        return null;
    const sn = (_e = item === null || item === void 0 ? void 0 : item.snippet) !== null && _e !== void 0 ? _e : {};
    const th = (_f = sn.thumbnails) !== null && _f !== void 0 ? _f : {};
    const url = (_h = (_g = (_b = th.high) === null || _b === void 0 ? void 0 : _b.url) !== null && _g !== void 0 ? _g : (_c = th.medium) === null || _c === void 0 ? void 0 : _c.url) !== null && _h !== void 0 ? _h : (_d = th.default) === null || _d === void 0 ? void 0 : _d.url;
    return {
        videoId,
        title: decodeEntities(str(sn.title, 200)),
        channel: decodeEntities(str(sn.channelTitle, 100)),
        thumbUrl: thumb(url),
        live: sn.liveBroadcastContent === 'live',
    };
}
//# sourceMappingURL=watch_logic.js.map