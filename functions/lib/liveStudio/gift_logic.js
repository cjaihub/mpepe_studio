"use strict";
/**
 * LIVE STUDIO v2 — live gifting rules (pure).
 * Viewers spend coins from `wallets/{uid}.balanceCoins`; the host receives
 * HOST_SHARE of it as `pendingCoins` (released by payouts). Catalog prices
 * are server-side only, so the app can never set its own price.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.GiftError = exports.RECENT_GIFTS = exports.MAX_QTY = exports.HOST_SHARE = exports.GIFT_CATALOG = void 0;
exports.parseGift = parseGift;
exports.giftPrice = giftPrice;
exports.pushRecent = pushRecent;
exports.GIFT_CATALOG = {
    rose: { label: 'Rose', coins: 1 },
    thumbs: { label: 'Thumbs up', coins: 1 },
    spark: { label: 'Spark', coins: 2 },
    coffee: { label: 'Coffee', coins: 3 },
    heart: { label: 'Heart', coins: 5 },
    icecream: { label: 'Ice cream', coins: 7 },
    star: { label: 'Star', coins: 10 },
    fire: { label: 'Fire', coins: 15 },
    balloon: { label: 'Balloons', coins: 20 },
    music: { label: 'Mic drop', coins: 30 },
    crown: { label: 'Crown', coins: 50 },
    rocket: { label: 'Rocket', coins: 100 },
    trophy: { label: 'Trophy', coins: 199 },
    diamond: { label: 'Diamond', coins: 500 },
    car: { label: 'Sports car', coins: 1000 },
    castle: { label: 'Castle', coins: 2500 },
    galaxy: { label: 'Galaxy', coins: 5000 },
};
exports.HOST_SHARE = 0.5;
exports.MAX_QTY = 99;
exports.RECENT_GIFTS = 15;
class GiftError extends Error {
}
exports.GiftError = GiftError;
function parseGift(data) {
    const d = (data && typeof data === 'object' ? data : {});
    if (typeof d.giftId !== 'string' || !(d.giftId in exports.GIFT_CATALOG))
        throw new GiftError('Unknown gift.');
    const qty = d.qty === undefined ? 1 : d.qty;
    if (typeof qty !== 'number' || !Number.isInteger(qty) || qty < 1 || qty > exports.MAX_QTY) {
        throw new GiftError(`Send 1–${exports.MAX_QTY} at a time.`);
    }
    return { giftId: d.giftId, qty };
}
function giftPrice(giftId, qty) {
    const total = exports.GIFT_CATALOG[giftId].coins * qty;
    return { total, hostCoins: Math.floor(total * exports.HOST_SHARE) };
}
/** Newest first, capped at RECENT_GIFTS. */
function pushRecent(list, g) {
    return [g, ...(Array.isArray(list) ? list : [])].slice(0, exports.RECENT_GIFTS);
}
//# sourceMappingURL=gift_logic.js.map