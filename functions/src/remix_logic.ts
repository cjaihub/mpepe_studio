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
export const REMIX_ORIGINAL_SHARE = 0.25;

export interface RemixSplit {
  remixerCoins: number;
  originalCoins: number;
}

/** Splits the creator part of a gift ([creatorCoins]) between remixer and original creator. */
export function splitRemixCoins(creatorCoins: number, share = REMIX_ORIGINAL_SHARE): RemixSplit {
  const coins = Math.max(0, Math.floor(creatorCoins));
  const s = Math.min(Math.max(share, 0), 1);
  const originalCoins = Math.floor(coins * s);
  return { remixerCoins: coins - originalCoins, originalCoins };
}

export type RemixVerdict =
  | { ok: true }
  | { ok: false; reason: 'missing' | 'own_post' | 'not_public' | 'not_allowed' | 'bad_request' };

/** Whether the original post allows this remix (Duet setting for older posts). */
export function remixAllowed(
  original: { authorId?: unknown; visibility?: unknown; permissions?: Record<string, unknown> } | undefined,
  remixAuthorId: string,
  claimedAuthorId: unknown,
): RemixVerdict {
  if (!original) return { ok: false, reason: 'missing' };
  if (typeof original.authorId !== 'string' || original.authorId !== claimedAuthorId) return { ok: false, reason: 'bad_request' };
  if (original.authorId === remixAuthorId) return { ok: false, reason: 'own_post' };
  if ((original.visibility ?? 'public') !== 'public') return { ok: false, reason: 'not_public' };
  const p = original.permissions ?? {};
  const allow = typeof p.allowRemix === 'boolean' ? p.allowRemix : p.allowDuet !== false;
  return allow ? { ok: true } : { ok: false, reason: 'not_allowed' };
}
