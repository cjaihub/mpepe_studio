"use strict";
/**
 * Reel destination links (pure). A creator attaches one link to a post: a
 * Biz product, a shop, or any web page. The server turns what the creator
 * typed into a `destination` the feed can show:
 *   - first-party links (oneova.web.app …) and Biz products open an in-app
 *     route;
 *   - other links stay `web` and are opened in the browser only after an
 *     Ova Guard check.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MAX_LABEL = exports.MAX_URL = void 0;
exports.cleanLabel = cleanLabel;
exports.firstPartyRoute = firstPartyRoute;
exports.parseDestination = parseDestination;
exports.defaultLabel = defaultLabel;
const FIRST_PARTY = new Set(['oneova.web.app', 'oneova.app', 'oneova.com', 'mpepe-2b4bd.web.app', 'mpepe-2b4bd.firebaseapp.com']);
const ID = /^[A-Za-z0-9_-]{1,64}$/;
const BAD_SCHEMES = /^(javascript|data|file|intent|content|blob|vbscript|about|chrome|market):/i;
exports.MAX_URL = 500;
exports.MAX_LABEL = 40;
function cleanLabel(raw) {
    return typeof raw === 'string' ? raw.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, exports.MAX_LABEL) : '';
}
function isPrivateHost(host) {
    if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') || host.endsWith('.internal'))
        return true;
    const m = /^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/.exec(host);
    if (!m)
        return host.startsWith('[');
    const a = Number(m[1]);
    const b = Number(m[2]);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}
/** In-app route for a first-party path, or null when it is not one we know. */
function firstPartyRoute(path) {
    const parts = path.split('?')[0].split('#')[0].split('/').filter(Boolean);
    const [a, b] = parts;
    if ((a === 'product' || a === 'p' || (a === 'biz' && b === 'product') || (a === 'biz' && b === 'checkout'))) {
        const id = a === 'biz' ? parts[2] : b;
        if (id && ID.test(id))
            return { kind: 'product', route: `/biz/checkout/${id}`, productId: id };
        return null;
    }
    if (a === 'shop' || a === 'biz_feed' || a === 'biz')
        return { kind: 'shop', route: '/biz_feed', productId: null };
    if ((a === 'profile' || a === 'u') && b && ID.test(b))
        return { kind: 'profile', route: `/profile/${b}`, productId: null };
    if (a === 'live' && b && ID.test(b))
        return { kind: 'live', route: `/live/viewer/${b}`, productId: null };
    return null;
}
/**
 * Validates what the creator sent: `{url?, productId?, label?}`.
 * A product id wins over a URL.
 */
function parseDestination(raw) {
    const d = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {});
    const label = cleanLabel(d.label);
    const productId = typeof d.productId === 'string' ? d.productId.trim() : '';
    if (productId) {
        if (!ID.test(productId))
            return { ok: false, reason: 'That product is not valid.' };
        return { ok: true, value: { kind: 'product', url: null, host: null, route: `/biz/checkout/${productId}`, productId, label } };
    }
    let input = typeof d.url === 'string' ? d.url.trim() : '';
    if (!input)
        return { ok: false, reason: 'Add a link.' };
    if (input.length > exports.MAX_URL)
        return { ok: false, reason: 'That link is too long.' };
    if (/\s/.test(input))
        return { ok: false, reason: 'A link cannot contain spaces.' };
    if (BAD_SCHEMES.test(input))
        return { ok: false, reason: 'Only web links (https://) can be attached.' };
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(input))
        input = `https://${input}`;
    let u;
    try {
        u = new URL(input);
    }
    catch (_a) {
        return { ok: false, reason: 'That link is not a valid web address.' };
    }
    if (u.protocol !== 'https:' && u.protocol !== 'http:')
        return { ok: false, reason: 'Only web links (https://) can be attached.' };
    if (u.username || u.password)
        return { ok: false, reason: 'Links with a hidden login part are not allowed.' };
    const host = u.hostname.toLowerCase().replace(/\.$/, '');
    if (!host.includes('.') || isPrivateHost(host))
        return { ok: false, reason: 'That link does not go to a public website.' };
    // Plain http is upgraded: the app never opens unencrypted pages.
    u.protocol = 'https:';
    const url = u.toString();
    if (FIRST_PARTY.has(host)) {
        const fp = firstPartyRoute(u.pathname);
        if (fp)
            return { ok: true, value: { kind: fp.kind, url, host, route: fp.route, productId: fp.productId, label } };
    }
    return { ok: true, value: { kind: 'web', url, host, route: null, productId: null, label } };
}
/** Text on the reel chip when the creator gave no label. */
function defaultLabel(kind, host, productTitle) {
    switch (kind) {
        case 'product':
            return cleanLabel(productTitle) || 'Shop this product';
        case 'shop':
            return 'Visit shop';
        case 'profile':
            return 'View profile';
        case 'live':
            return 'Watch live';
        default:
            return cleanLabel(host === null || host === void 0 ? void 0 : host.replace(/^www\./, '')) || 'Open link';
    }
}
//# sourceMappingURL=destination_logic.js.map