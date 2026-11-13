/**
 * Oneova Pay rules with no I/O, so they are unit tested.
 *
 * A pay-in is a `pay_intents/{id}` document:
 *   created → pending_payer → succeeded
 *                           → failed | expired | cancelled
 *   expired / cancelled → succeeded   only when the partner later confirms the
 *                                     money really arrived (a late approval);
 *                                     money that came in is never ignored.
 *   succeeded → refunded
 * Any state → review when the amount paid doesn't match the intent.
 */
import { AFRICA } from '../creator/payoutLogic';
import { CollectKind, ProviderId, Rail } from '../payments/provider';

export type IntentStatus = 'created' | 'pending_payer' | 'succeeded' | 'failed' | 'expired' | 'cancelled' | 'refunded' | 'review';
export type IntentPurpose = 'order' | 'topup';

const NEXT: Record<IntentStatus, IntentStatus[]> = {
  created: ['pending_payer', 'succeeded', 'failed', 'cancelled', 'review'],
  pending_payer: ['succeeded', 'failed', 'expired', 'cancelled', 'review'],
  expired: ['succeeded', 'review'],
  cancelled: ['succeeded', 'review'],
  failed: ['review'],
  succeeded: ['refunded', 'review'],
  refunded: [],
  review: ['succeeded', 'failed', 'refunded'],
};

export function canMoveIntent(from: IntentStatus, to: IntentStatus): boolean {
  return NEXT[from]?.includes(to) ?? false;
}

export const isOpenIntent = (s: IntentStatus) => s === 'created' || s === 'pending_payer';

/** How long a payer has to approve: a phone prompt is short, a hosted page longer. */
export const intentTtlMs = (kind: CollectKind) => (kind === 'hosted' ? 45 * 60_000 : 10 * 60_000);

/** Which partners have keys right now (and whether the sandbox / wallet are on). */
export interface PayConfig {
  sandbox: boolean;
  /** Stored-value Oneova balance: needs an e-money licence. */
  wallet: boolean;
  mpesa: boolean;
  momo: boolean;
  flutterwave: boolean;
  paystack: boolean;
}

export interface PayMethod {
  /** Stable id the app sends back, e.g. `momo:MTN`, `card`, `bank`, `balance`. */
  id: string;
  rail: Rail | 'balance';
  provider: ProviderId | 'oneova';
  kind: CollectKind;
  label: string;
  network?: string;
  /** The payer types their phone number (prompt rails). */
  needsPhone: boolean;
  sandbox?: boolean;
}

const MOMO_COUNTRIES = ['UG', 'GH', 'RW', 'ZM', 'CM', 'CI', 'BJ'];
const PAYSTACK_COUNTRIES = ['NG', 'GH', 'KE', 'ZA', 'CI'];

export const currencyFor = (country: string) => AFRICA[country]?.currency ?? 'USD';

/**
 * Ways to pay in [country], best first. A rail appears only when a partner
 * with keys can take it; with the sandbox on, every rail appears and is
 * served by the sandbox instead.
 */
export function methodsFor(country: string, cfg: PayConfig): PayMethod[] {
  const a = AFRICA[country];
  const out: PayMethod[] = [];
  const sbx = (m: Omit<PayMethod, 'provider' | 'sandbox' | 'kind'>): PayMethod => ({ ...m, kind: 'prompt', provider: 'sandbox', sandbox: true });

  for (const n of a?.networks ?? []) {
    const id = `momo:${n.id}`;
    const base = { id, rail: 'mobile_money' as const, label: n.label, network: n.id };
    if (n.id === 'MPESA' && country === 'KE' && cfg.mpesa) out.push({ ...base, provider: 'mpesa', kind: 'prompt', needsPhone: true });
    else if (n.id === 'MTN' && MOMO_COUNTRIES.includes(country) && cfg.momo) out.push({ ...base, provider: 'mtn_momo', kind: 'prompt', needsPhone: true });
    else if (cfg.flutterwave) out.push({ ...base, provider: 'flutterwave', kind: 'hosted', needsPhone: true });
    else if (cfg.paystack && PAYSTACK_COUNTRIES.includes(country) && n.paystack) out.push({ ...base, provider: 'paystack', kind: 'hosted', needsPhone: true });
    else if (cfg.sandbox) out.push(sbx({ ...base, needsPhone: true }));
  }

  if (cfg.flutterwave) out.push({ id: 'card', rail: 'card', provider: 'flutterwave', kind: 'hosted', label: 'Debit or credit card', needsPhone: false });
  else if (cfg.paystack && PAYSTACK_COUNTRIES.includes(country)) out.push({ id: 'card', rail: 'card', provider: 'paystack', kind: 'hosted', label: 'Debit or credit card', needsPhone: false });
  else if (cfg.sandbox) out.push(sbx({ id: 'card', rail: 'card', label: 'Debit or credit card', needsPhone: false }));

  if (a?.bank) {
    if (cfg.flutterwave) out.push({ id: 'bank', rail: 'bank', provider: 'flutterwave', kind: 'hosted', label: 'Bank transfer', needsPhone: false });
    else if (cfg.paystack && PAYSTACK_COUNTRIES.includes(country)) out.push({ id: 'bank', rail: 'bank', provider: 'paystack', kind: 'hosted', label: 'Bank transfer', needsPhone: false });
  }

  if (cfg.wallet) out.unshift({ id: 'balance', rail: 'balance', provider: 'oneova', kind: 'instant', label: 'Oneova balance', needsPhone: false });
  return out;
}

/** Top-up limits, in USD-equivalent major units (checked against the local amount × rate). */
export const TOPUP_MIN_USD = 1;
export const TOPUP_MAX_USD = 1000;

// ───────────────────────────── Ledger ─────────────────────────────

export type Bucket = 'available' | 'pending' | 'locked';

/**
 * One line of a double-entry posting. Positive = money into the account.
 * `user:{uid}` accounts also move the user's `pay_balances` [bucket];
 * `escrow:{orderId}`, `platform:revenue`, `clearing:{provider}` and
 * `payout:{provider}` are system accounts recorded in the ledger only.
 */
export interface LedgerLine {
  account: string;
  currency: string;
  amountMinor: number;
  bucket?: Bucket;
}

/** Every posting must sum to zero per currency, with integer minor units. */
export function ledgerBalanced(lines: LedgerLine[]): boolean {
  if (!lines.length) return false;
  const sums = new Map<string, number>();
  for (const l of lines) {
    if (!Number.isSafeInteger(l.amountMinor) || !l.account || !l.currency) return false;
    sums.set(l.currency, (sums.get(l.currency) ?? 0) + l.amountMinor);
  }
  return [...sums.values()].every((v) => v === 0);
}

/** `user:{uid}` → uid, anything else → null. */
export const userOf = (account: string) => (account.startsWith('user:') ? account.slice(5) : null);

// ───────────────────────────── Orders ─────────────────────────────

/**
 * How a paid order's escrow is released, in integer minor units:
 * the seller gets the items minus commission (rounded down to the seller's
 * favour of the platform never taking more than the percent), the rider the
 * delivery fee, the platform the rest. Sums exactly to the total.
 */
export function orderSplit(itemsMinor: number, deliveryMinor: number, commissionPercent: number) {
  if (!Number.isSafeInteger(itemsMinor) || !Number.isSafeInteger(deliveryMinor) || itemsMinor < 0 || deliveryMinor < 0) {
    throw new Error('amounts must be non-negative integers');
  }
  const pct = Math.min(Math.max(commissionPercent, 0), 50);
  const platform = Math.floor((itemsMinor * pct) / 100);
  return { seller: itemsMinor - platform, rider: deliveryMinor, platform, total: itemsMinor + deliveryMinor };
}

/** Payout fee on a balance withdrawal, in minor units (mobile money 1.5%, bank 1%). */
export function balancePayoutFee(rail: Rail, amountMinor: number): number {
  const pct = rail === 'mobile_money' ? 1.5 : 1;
  return Math.ceil((amountMinor * pct) / 100);
}

/** Masks a phone number for display: 2547…1234. */
export const maskMsisdn = (m: string) => (m.length > 8 ? `${m.slice(0, 4)}…${m.slice(-4)}` : '…');
