"use strict";
/**
 * LIVE STUDIO v2 & Reels — GIF comments (pure).
 *
 * GIFs come from trusted providers (GIPHY, Tenor, Google Noto Animated Emoji CDN,
 * Wikimedia Commons animated GIFs, or Oneova's own Firebase Storage `gifs/`
 * bucket created via `/create/gif`), so clients cannot smuggle arbitrary external
 * tracking/phishing image links into comments.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.sanitizeGifQuery = void 0;
exports.isTrustedGifUrl = isTrustedGifUrl;
exports.parseCommentGif = parseCommentGif;
exports.fromGiphy = fromGiphy;
exports.fromTenor = fromTenor;
exports.fromWikimediaPage = fromWikimediaPage;
exports.searchNotoAnimatedGifs = searchNotoAnimatedGifs;
const TRUSTED_GIF_URLS = [
    /^https:\/\/media[0-9]?\.giphy\.com\/[A-Za-z0-9/_.\-?=&%]+$/,
    /^https:\/\/(?:media|c)\.tenor\.com\/[A-Za-z0-9/_.\-?=&%]+$/,
    /^https:\/\/fonts\.gstatic\.com\/s\/e\/notoemoji\/latest\/[a-f0-9_-]+\/512\.(?:gif|webp)$/,
    /^https:\/\/upload\.wikimedia\.org\/wikipedia\/commons\/[A-Za-z0-9/_.\-%()]+\.gif(?:\?[A-Za-z0-9_.\-&=%]*)?$/i,
    /^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/mpepe-2b4bd\.(?:firebasestorage\.app|appspot\.com)\/o\/gifs%2F[A-Za-z0-9_.\-%]+\?(?:[A-Za-z0-9_.\-&=%]+)$/,
];
function isTrustedGifUrl(url) {
    if (!url || url.length > 600)
        return false;
    return TRUSTED_GIF_URLS.some((re) => re.test(url));
}
/** Validated GIF, null when absent, or `'invalid'` when malformed or untrusted. */
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
    if (!isTrustedGifUrl(url) || !/^[A-Za-z0-9_\-]{1,64}$/.test(id))
        return 'invalid';
    if (w < 1 || h < 1 || w > 4000 || h > 4000)
        return 'invalid';
    return { id, url, w, h };
}
/** Maps one GIPHY API result to what the app renders (small webp + size). */
function fromGiphy(r) {
    var _a, _b;
    var _c, _d;
    const o = (r && typeof r === 'object' ? r : {});
    const img = (_c = (_a = o.images) === null || _a === void 0 ? void 0 : _a.fixed_width) !== null && _c !== void 0 ? _c : (_b = o.images) === null || _b === void 0 ? void 0 : _b.downsized;
    const url = ((img === null || img === void 0 ? void 0 : img.webp) || (img === null || img === void 0 ? void 0 : img.url) || '');
    const parsed = parseCommentGif({
        id: String((_d = o.id) !== null && _d !== void 0 ? _d : '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40),
        url: url.split('?')[0],
        w: Number(img === null || img === void 0 ? void 0 : img.width),
        h: Number(img === null || img === void 0 ? void 0 : img.height),
    });
    return parsed && parsed !== 'invalid' ? parsed : null;
}
/** Maps one Tenor v2 API result to CommentGif. */
function fromTenor(r) {
    var _a, _b;
    var _c, _d;
    const o = (r && typeof r === 'object' ? r : {});
    const fmt = (_c = (_a = o.media_formats) === null || _a === void 0 ? void 0 : _a.tinygif) !== null && _c !== void 0 ? _c : (_b = o.media_formats) === null || _b === void 0 ? void 0 : _b.gif;
    const dims = Array.isArray(fmt === null || fmt === void 0 ? void 0 : fmt.dims) ? fmt.dims : [220, 220];
    const parsed = parseCommentGif({
        id: `tn_${String((_d = o.id) !== null && _d !== void 0 ? _d : '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40)}`,
        url: typeof (fmt === null || fmt === void 0 ? void 0 : fmt.url) === 'string' ? fmt.url : '',
        w: Number(dims[0]) || 220,
        h: Number(dims[1]) || 220,
    });
    return parsed && parsed !== 'invalid' ? parsed : null;
}
/** Maps one Wikimedia Commons page entry (`imageinfo`) to CommentGif. */
function fromWikimediaPage(p) {
    var _a, _b, _c, _d;
    const o = (p && typeof p === 'object' ? p : {});
    const info = Array.isArray(o.imageinfo) ? o.imageinfo[0] : null;
    if (!info || info.mime !== 'image/gif')
        return null;
    const size = Number((_a = info.size) !== null && _a !== void 0 ? _a : 0);
    if (size <= 0 || size > 6 * 1024 * 1024)
        return null;
    const w = Number((_b = info.width) !== null && _b !== void 0 ? _b : 0);
    const h = Number((_c = info.height) !== null && _c !== void 0 ? _c : 0);
    if (w < 64 || h < 64)
        return null;
    const rawUrl = typeof info.url === 'string' ? info.url.split('?')[0] : '';
    const parsed = parseCommentGif({
        id: `wm_${String((_d = o.pageid) !== null && _d !== void 0 ? _d : '').replace(/[^0-9]/g, '')}`,
        url: rawUrl,
        w,
        h,
    });
    return parsed && parsed !== 'invalid' ? parsed : null;
}
const NOTO_ANIMATED_CATALOG = [
    { code: '1f525', tags: ['fire', 'lit', 'hot', 'hype', 'trending', 'flame'] },
    { code: '1f602', tags: ['laugh', 'lol', 'funny', 'tears', 'haha', 'comedy'] },
    { code: '1f923', tags: ['rofl', 'lmao', 'laugh', 'funny', 'hilarious'] },
    { code: '1f60d', tags: ['love', 'heart', 'eyes', 'crush', 'beautiful', 'cute'] },
    { code: '1f970', tags: ['love', 'hearts', 'sweet', 'adore', 'wholesome', 'cute'] },
    { code: '2764_fe0f', tags: ['heart', 'love', 'red', 'like'] },
    { code: '1fa77', tags: ['heart', 'pink', 'love', 'cute'] },
    { code: '1f44f', tags: ['clap', 'applause', 'bravo', 'respect', 'congrats'] },
    { code: '1f389', tags: ['party', 'celebrate', 'congrats', 'yay', 'woohoo', 'hype'] },
    { code: '1f92f', tags: ['mind', 'blown', 'wow', 'shock', 'crazy', 'insane', 'omg'] },
    { code: '1f680', tags: ['rocket', 'launch', 'moon', 'fast', 'hype', 'boost'] },
    { code: '1f4af', tags: ['100', 'facts', 'real', 'true', 'perfect', 'score'] },
    { code: '1f483', tags: ['dance', 'vibe', 'music', 'groove', 'party'] },
    { code: '1f57a', tags: ['dance', 'disco', 'groove', 'vibe', 'party'] },
    { code: '1f60e', tags: ['cool', 'sunglasses', 'boss', 'smooth', 'chill'] },
    { code: '1f929', tags: ['star', 'amazed', 'wow', 'excited', 'fan', 'awesome'] },
    { code: '1f451', tags: ['crown', 'king', 'queen', 'goat', 'royalty', 'boss'] },
    { code: '1f3c6', tags: ['trophy', 'win', 'winner', 'champion', 'gold', 'goat'] },
    { code: '2728', tags: ['sparkles', 'magic', 'shine', 'glow', 'aesthetic'] },
    { code: '1f440', tags: ['eyes', 'look', 'watching', 'tea', 'see', 'wait'] },
    { code: '1f62d', tags: ['cry', 'sad', 'sob', 'tears', 'emotional', 'omg'] },
    { code: '1f97a', tags: ['pleading', 'please', 'cute', 'puppy', 'sad'] },
    { code: '1f631', tags: ['scream', 'shock', 'omg', 'scared', 'wow'] },
    { code: '1f914', tags: ['think', 'hmm', 'wonder', 'question', 'wait'] },
    { code: '1fae1', tags: ['salute', 'respect', 'yes', 'honor'] },
    { code: '1f64c', tags: ['praise', 'hands', 'yay', 'celebrate', 'amen', 'hype'] },
    { code: '1f64f', tags: ['pray', 'thanks', 'thank', 'grateful', 'please', 'bless'] },
    { code: '1f44d', tags: ['thumbs', 'up', 'good', 'yes', 'agree', 'nice', 'ok'] },
    { code: '1f4aa', tags: ['strong', 'muscle', 'flex', 'gym', 'power', 'grind'] },
    { code: '1f91d', tags: ['handshake', 'deal', 'respect', 'agree', 'team'] },
    { code: '1f618', tags: ['kiss', 'love', 'muah', 'flirt', 'cute'] },
    { code: '1f609', tags: ['wink', 'flirt', 'playful', 'nice'] },
    { code: '1f973', tags: ['party', 'birthday', 'celebrate', 'happy', 'fun'] },
    { code: '1f921', tags: ['clown', 'joke', 'funny', 'silly'] },
    { code: '1f480', tags: ['skull', 'dead', 'funny', 'lol', 'bruh'] },
    { code: '1f47b', tags: ['ghost', 'boo', 'spooky', 'cute'] },
    { code: '1f4b8', tags: ['money', 'cash', 'rich', 'fly', 'business'] },
    { code: '1f48e', tags: ['gem', 'diamond', 'luxury', 'shine', 'vip'] },
    { code: '1f3b6', tags: ['music', 'song', 'beat', 'sound', 'vibe', 'tune'] },
    { code: '1f3a4', tags: ['mic', 'sing', 'drop', 'live', 'music'] },
];
/** Returns curated 512x512 animated reaction GIFs from Google's Noto Emoji CDN. */
function searchNotoAnimatedGifs(query, limit = 24) {
    const q = (0, exports.sanitizeGifQuery)(query).toLowerCase();
    const terms = q.split(/\s+/).filter(Boolean);
    const matched = terms.length === 0
        ? NOTO_ANIMATED_CATALOG
        : NOTO_ANIMATED_CATALOG.filter((entry) => terms.some((t) => entry.tags.some((tag) => tag.includes(t) || t.includes(tag))));
    return matched.slice(0, limit).map((entry) => ({
        id: `noto_${entry.code}`,
        url: `https://fonts.gstatic.com/s/e/notoemoji/latest/${entry.code}/512.gif`,
        w: 256,
        h: 256,
    }));
}
const sanitizeGifQuery = (q) => typeof q === 'string' ? q.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 50) : '';
exports.sanitizeGifQuery = sanitizeGifQuery;
//# sourceMappingURL=gif_logic.js.map