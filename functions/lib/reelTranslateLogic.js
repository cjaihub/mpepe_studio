"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MAX_SEGMENT_CHARS = exports.MAX_SEGMENTS = exports.MAX_CAPTION_CHARS = void 0;
exports.normalizeLang = normalizeLang;
exports.baseLang = baseLang;
exports.sameLanguage = sameLanguage;
exports.captionBody = captionBody;
exports.cleanSegments = cleanSegments;
exports.buildItems = buildItems;
exports.applyTranslations = applyTranslations;
exports.sourceHash = sourceHash;
exports.cleanSupport = cleanSupport;
exports.validPostId = validPostId;
/**
 * Pure helpers for the reel translator (reelTranslate.ts). No Firebase here so
 * node tests can cover them.
 */
const crypto_1 = require("crypto");
exports.MAX_CAPTION_CHARS = 2200;
exports.MAX_SEGMENTS = 300;
exports.MAX_SEGMENT_CHARS = 200;
const HASHTAG = /(^|\s)#[\p{L}\p{M}\p{N}_]+/gu;
/**
 * A target language as a cache key: lowercase base code with an optional
 * region/script ("sw", "yo", "pt-BR", "zh-Hant"). Null when it isn't a code.
 */
function normalizeLang(v) {
    if (typeof v !== 'string')
        return null;
    const m = v.trim().replace('_', '-').match(/^([A-Za-z]{2,3})(?:-([A-Za-z0-9]{2,8}))?$/);
    if (!m)
        return null;
    const base = m[1].toLowerCase();
    if (base === 'und')
        return null;
    const sub = m[2];
    if (!sub)
        return base;
    if (/^[A-Za-z]{4}$/.test(sub))
        return `${base}-${sub[0].toUpperCase()}${sub.slice(1).toLowerCase()}`;
    return `${base}-${sub.toUpperCase()}`;
}
/** Base code of a language ("pt" for "pt-BR"). */
function baseLang(code) {
    return code.split('-')[0].toLowerCase();
}
/** Same language for reading purposes (regions differ, the text doesn't need translating). */
function sameLanguage(a, b) {
    if (!a || !b)
        return false;
    return baseLang(a) === baseLang(b);
}
/** Reel caption without its hashtags; hashtags are kept as they are. */
function captionBody(caption) {
    return caption.replace(HASHTAG, ' ').replace(/[ \t]{2,}/g, ' ').replace(/\s*\n\s*/g, '\n').trim();
}
/** Cleans a stored caption track: valid times, trimmed text, capped size. */
function cleanSegments(raw) {
    if (!Array.isArray(raw))
        return [];
    const out = [];
    for (const r of raw) {
        if (out.length >= exports.MAX_SEGMENTS)
            break;
        const o = (r !== null && r !== void 0 ? r : {});
        const text = typeof o.text === 'string' ? o.text.trim().slice(0, exports.MAX_SEGMENT_CHARS) : '';
        const startMs = Math.round(Number(o.startMs));
        const endMs = Math.round(Number(o.endMs));
        if (!text || !Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs || startMs < 0)
            continue;
        out.push({ startMs, endMs, text });
    }
    return out;
}
/** Items sent to the model: the caption body first (when any), then each caption line. */
function buildItems(body, segments) {
    return [...(body ? [body.slice(0, exports.MAX_CAPTION_CHARS)] : []), ...segments.map((s) => s.text)];
}
/** Puts model output back into caption + timed lines; null when it doesn't line up. */
function applyTranslations(body, segments, translations) {
    const expected = (body ? 1 : 0) + segments.length;
    if (!Array.isArray(translations) || translations.length !== expected)
        return null;
    const items = translations.map((t) => (typeof t === 'string' ? t.trim() : ''));
    const caption = body ? items[0] || body : '';
    const offset = body ? 1 : 0;
    return {
        caption,
        segments: segments.map((s, i) => (Object.assign(Object.assign({}, s), { text: items[i + offset] || s.text }))),
    };
}
/**
 * Fingerprint of what was translated. A stored translation is reused only while
 * the caption and caption track it was made from are unchanged.
 */
function sourceHash(body, segments) {
    const h = (0, crypto_1.createHash)('sha256');
    h.update(body);
    for (const s of segments)
        h.update(`\u0000${s.startMs}:${s.endMs}:${s.text}`);
    return h.digest('hex').slice(0, 24);
}
function cleanSupport(v) {
    return v === 'good' || v === 'limited' || v === 'unsupported' ? v : 'limited';
}
/** Post ids are Firestore auto ids or similar; nothing with slashes. */
function validPostId(v) {
    return typeof v === 'string' && /^[A-Za-z0-9_-]{4,128}$/.test(v);
}
//# sourceMappingURL=reelTranslateLogic.js.map