"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.clawbackPlan = clawbackPlan;
exports.creditWithDebt = creditWithDebt;
exports.giftRecipients = giftRecipients;
function clawbackPlan(balanceCoins, coins) {
    const have = Math.max(0, Math.floor(Number(balanceCoins) || 0));
    const owed = Math.max(0, Math.floor(Number(coins) || 0));
    const take = Math.min(have, owed);
    return { takeFromBalance: take, addDebt: owed - take };
}
/** A new pack pays the debt first. */
function creditWithDebt(coins, coinDebt) {
    const debt = Math.max(0, Math.floor(Number(coinDebt) || 0));
    const debtPaid = Math.min(debt, coins);
    return { credit: coins - debtPaid, debtPaid };
}
const SENT_TYPES = new Set(['user_gift_sent', 'live_gift_sent']);
/** People who received gifts from the buyer at or after [sinceMs], with the coins sent. */
function giftRecipients(entries, sinceMs) {
    var _a, _b;
    const out = new Map();
    for (const e of entries) {
        if (!SENT_TYPES.has(String(e.type)) || typeof e.toUid !== 'string' || !e.toUid)
            continue;
        if (((_a = e.createdAtMs) !== null && _a !== void 0 ? _a : 0) < sinceMs)
            continue;
        out.set(e.toUid, ((_b = out.get(e.toUid)) !== null && _b !== void 0 ? _b : 0) + Math.abs(Number(e.amount) || 0));
    }
    return out;
}
//# sourceMappingURL=clawbackLogic.js.map