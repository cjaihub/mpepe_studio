"use strict";
/**
 * LIVE STUDIO v2 — GIF comments (pure). GIFs come from GIPHY (searched
 * server-side by lsGifSearch); a comment may carry one GIF whose URL must be
 * a GIPHY media host, so clients can't post arbitrary links as images.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.sanitizeGifQuery = void 0;
exports.parseCommentGif = parseCommentGif;
exports.fromGiphy = fromGiphy;
const GIPHY_MEDIA = /^https:\/\/media[0-9]?\.giphy\.com\/[A-Za-z0-9/_.\-?=&]+$/;
/** Validated GIF, null when absent, or throws (via the returned string) when invalid. */
function parseCommentGif(raw) {
    if (raw === undefined || raw === null)
        return null;
    if (typeof raw !== 'object' || Array.isArray(raw))
        return 'invalid';
    const g = raw;
    const url = typeof g.url === 'string' ? g.url.trim() : '';
    const id = typeof g.id === 'string' ? g.id.trim() : '';
    const w = typeof g.w === 'number' && Number.isFinite(g.w) ? Math.round(g.w) : 0;
    const h = typeof g.h === 'number' && Number.isFinite(g.h) ? Math.round(g.h) : 0;
    if (!GIPHY_MEDIA.test(url) || url.length > 500 || !/^[A-Za-z0-9]{1,40}$/.test(id))
        return 'invalid';
    if (w < 1 || h < 1 || w > 4000 || h > 4000)
        return 'invalid';
    return { id, url, w, h };
}
/** Maps one GIPHY API result to what the app renders (small webp + size). */
function fromGiphy(r) {
    var _a, _b;
    var _c;
    const o = (r && typeof r === 'object' ? r : {});
    const img = (_c = (_a = o.images) === null || _a === void 0 ? void 0 : _a.fixed_width) !== null && _c !== void 0 ? _c : (_b = o.images) === null || _b === void 0 ? void 0 : _b.downsized;
    const url = ((img === null || img === void 0 ? void 0 : img.webp) || (img === null || img === void 0 ? void 0 : img.url) || '');
    const parsed = parseCommentGif({ id: o.id, url: url.split('?')[0], w: Number(img === null || img === void 0 ? void 0 : img.width), h: Number(img === null || img === void 0 ? void 0 : img.height) });
    return parsed && parsed !== 'invalid' ? parsed : null;
}
const sanitizeGifQuery = (q) => typeof q === 'string' ? q.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 50) : '';
exports.sanitizeGifQuery = sanitizeGifQuery;
//# sourceMappingURL=gif_logic.js.map