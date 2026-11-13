"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.REMIX_ORIGINAL_SHARE = void 0;
exports.splitRemixCoins = splitRemixCoins;
exports.remixAllowed = remixAllowed;
/**
 * Remix earnings split (pure logic, unit-tested).
 *
 * A remix's creator keeps HOST_SHARE (80%) of the coins gifted on the remix,
 * like any clip. Of that creator part, REMIX_ORIGINAL_SHARE goes to the
 * creator of the original post:
 *
 *   100-coin gift on a remix → platform 20, original creator 20, remixer 60.
 *
 * The original creator's part rounds down so a 1-coin gift still reaches
 * the remixer; it is recorded in `remix_links/{remixContentId}` and in both
 * wallets' ledgers. Same value as kRemixOriginalShare in
 * lib/backend/social/models/remix_source.dart.
 */
exports.REMIX_ORIGINAL_SHARE = 0.25;
/** Splits the creator part of a gift ([creatorCoins]) between remixer and original creator. */
function splitRemixCoins(creatorCoins, share = exports.REMIX_ORIGINAL_SHARE) {
    const coins = Math.max(0, Math.floor(creatorCoins));
    const s = Math.min(Math.max(share, 0), 1);
    const originalCoins = Math.floor(coins * s);
    return { remixerCoins: coins - originalCoins, originalCoins };
}
/** Whether the original post allows this remix (Duet setting for older posts). */
function remixAllowed(original, remixAuthorId, claimedAuthorId) {
    var _a, _b;
    if (!original)
        return { ok: false, reason: 'missing' };
    if (typeof original.authorId !== 'string' || original.authorId !== claimedAuthorId)
        return { ok: false, reason: 'bad_request' };
    if (original.authorId === remixAuthorId)
        return { ok: false, reason: 'own_post' };
    if (((_a = original.visibility) !== null && _a !== void 0 ? _a : 'public') !== 'public')
        return { ok: false, reason: 'not_public' };
    const p = (_b = original.permissions) !== null && _b !== void 0 ? _b : {};
    const allow = typeof p.allowRemix === 'boolean' ? p.allowRemix : p.allowDuet !== false;
    return allow ? { ok: true } : { ok: false, reason: 'not_allowed' };
}
//# sourceMappingURL=remix_logic.js.map