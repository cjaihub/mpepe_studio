/**
 * LIVE STUDIO v2 — live gifting rules (pure).
 * Viewers spend coins from `wallets/{uid}.balanceCoins`; the host receives
 * HOST_SHARE of it as `pendingCoins` (released by payouts). Catalog prices
 * are server-side only, so the app can never set its own price.
 */

export const GIFT_CATALOG = {
  rose: { label: 'Rose', coins: 1 },
  heart: { label: 'Heart', coins: 5 },
  star: { label: 'Star', coins: 10 },
  crown: { label: 'Crown', coins: 50 },
  rocket: { label: 'Rocket', coins: 100 },
  diamond: { label: 'Diamond', coins: 500 },
} as const;

export type GiftId = keyof typeof GIFT_CATALOG;
export const HOST_SHARE = 0.5;
export const MAX_QTY = 99;
export const RECENT_GIFTS = 15;

export class GiftError extends Error {}

export function parseGift(data: unknown): { giftId: GiftId; qty: number } {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  if (typeof d.giftId !== 'string' || !(d.giftId in GIFT_CATALOG)) throw new GiftError('Unknown gift.');
  const qty = d.qty === undefined ? 1 : d.qty;
  if (typeof qty !== 'number' || !Number.isInteger(qty) || qty < 1 || qty > MAX_QTY) {
    throw new GiftError(`Send 1–${MAX_QTY} at a time.`);
  }
  return { giftId: d.giftId as GiftId, qty };
}

export function giftPrice(giftId: GiftId, qty: number): { total: number; hostCoins: number } {
  const total = GIFT_CATALOG[giftId].coins * qty;
  return { total, hostCoins: Math.floor(total * HOST_SHARE) };
}

export interface RecentGift {
  id: string;
  uid: string;
  name: string;
  avatarUrl: string;
  giftId: GiftId;
  qty: number;
  coins: number;
  atMs: number;
}

/** Newest first, capped at RECENT_GIFTS. */
export function pushRecent(list: RecentGift[] | undefined, g: RecentGift): RecentGift[] {
  return [g, ...(Array.isArray(list) ? list : [])].slice(0, RECENT_GIFTS);
}
