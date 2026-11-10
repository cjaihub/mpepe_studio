/**
 * Refunded coin purchases (Google Play voided purchases): the rules, no I/O.
 *
 * When Play refunds or charges back a coin pack:
 *   1. take the coins back from the buyer's balance;
 *   2. what they already spent becomes `coinDebt`, paid first from the next pack;
 *   3. if they had spent any, everyone they gifted since that purchase gets a
 *      payout hold: their next withdrawal waits for a person to check it.
 * Nobody's Diamonds are taken automatically; an innocent creator just waits.
 */

export interface ClawbackPlan {
  takeFromBalance: number;
  addDebt: number;
}

export function clawbackPlan(balanceCoins: number, coins: number): ClawbackPlan {
  const have = Math.max(0, Math.floor(Number(balanceCoins) || 0));
  const owed = Math.max(0, Math.floor(Number(coins) || 0));
  const take = Math.min(have, owed);
  return { takeFromBalance: take, addDebt: owed - take };
}

/** A new pack pays the debt first. */
export function creditWithDebt(coins: number, coinDebt: number): { credit: number; debtPaid: number } {
  const debt = Math.max(0, Math.floor(Number(coinDebt) || 0));
  const debtPaid = Math.min(debt, coins);
  return { credit: coins - debtPaid, debtPaid };
}

const SENT_TYPES = new Set(['user_gift_sent', 'live_gift_sent']);

/** People who received gifts from the buyer at or after [sinceMs], with the coins sent. */
export function giftRecipients(entries: { type?: unknown; toUid?: unknown; amount?: unknown; createdAtMs?: number | null }[], sinceMs: number): Map<string, number> {
  const out = new Map<string, number>();
  for (const e of entries) {
    if (!SENT_TYPES.has(String(e.type)) || typeof e.toUid !== 'string' || !e.toUid) continue;
    if ((e.createdAtMs ?? 0) < sinceMs) continue;
    out.set(e.toUid, (out.get(e.toUid) ?? 0) + Math.abs(Number(e.amount) || 0));
  }
  return out;
}
