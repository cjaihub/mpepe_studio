/**
 * Store rules with no I/O (unit tested): buyer customizations of a product
 * and seller discount codes. Checkout calls these so the price a buyer pays
 * is always computed on the server.
 *
 * Product `customization` (written by the seller):
 *   [{ id, label, type: 'choice' | 'text', required?, maxLength?, priceDelta?,
 *      choices?: [{ id, label, priceDelta?, colorHex?, modelVariant? }] }]
 * Buyer selection (sent to checkout): { [optionId]: choiceId | text }
 */

export class StoreRuleError extends Error {
  constructor(readonly code: 'invalid-argument' | 'failed-precondition', message: string) {
    super(message);
  }
}

export interface ChosenOption {
  optionId: string;
  label: string;
  value: string;
  priceDelta: number;
  modelVariant?: string;
}

const MAX_OPTIONS = 12;
const MAX_TEXT = 60;

/** Validates a buyer's selection against the product and returns the priced lines. */
export function priceCustomization(product: { customization?: unknown }, raw: unknown): ChosenOption[] {
  const options = Array.isArray(product.customization) ? product.customization.slice(0, MAX_OPTIONS) : [];
  const sel = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const out: ChosenOption[] = [];
  for (const o of options) {
    if (!o || typeof o !== 'object') continue;
    const id = String((o as any).id ?? '');
    const label = String((o as any).label ?? 'Option').slice(0, 60);
    const type = (o as any).type === 'text' ? 'text' : 'choice';
    const required = (o as any).required === true;
    const value = sel[id];
    if (value == null || value === '') {
      if (required) throw new StoreRuleError('invalid-argument', `Choose ${label.toLowerCase()}.`);
      continue;
    }
    if (type === 'text') {
      const max = Math.min(Number((o as any).maxLength) || MAX_TEXT, MAX_TEXT);
      const text = String(value).trim();
      if (!text) continue;
      if (text.length > max) throw new StoreRuleError('invalid-argument', `${label} can be up to ${max} characters.`);
      out.push({ optionId: id, label, value: text, priceDelta: money((o as any).priceDelta) });
      continue;
    }
    const choices: any[] = Array.isArray((o as any).choices) ? (o as any).choices : [];
    const c = choices.find((x) => x && String(x.id) === String(value));
    if (!c) throw new StoreRuleError('invalid-argument', `That ${label.toLowerCase()} is not available.`);
    out.push({
      optionId: id,
      label,
      value: String(c.label ?? c.id).slice(0, 60),
      priceDelta: money(c.priceDelta),
      ...(typeof c.modelVariant === 'string' && c.modelVariant ? { modelVariant: c.modelVariant } : {}),
    });
  }
  return out;
}

const money = (v: unknown) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? Math.min(n, 1_000_000) : 0;
};

export const customizationExtra = (lines: ChosenOption[]) => lines.reduce((s, l) => s + l.priceDelta, 0);

export interface CodeDoc {
  active?: boolean;
  percentOff?: number;
  amountOff?: number;
  currency?: string;
  minSpend?: number;
  maxUses?: number;
  uses?: number;
  endsAtMs?: number;
}

/** Discount for [itemsAmount] with a seller code, or an error the buyer can read. */
export function codeDiscount(code: CodeDoc | null | undefined, itemsAmount: number, currency: string, nowMs: number): number {
  if (!code || code.active === false) throw new StoreRuleError('failed-precondition', 'That code isn’t valid.');
  if (code.endsAtMs != null && code.endsAtMs <= nowMs) throw new StoreRuleError('failed-precondition', 'That code has expired.');
  if (code.maxUses != null && (code.uses ?? 0) >= code.maxUses) throw new StoreRuleError('failed-precondition', 'That code has been used up.');
  if (code.minSpend != null && itemsAmount < code.minSpend) {
    throw new StoreRuleError('failed-precondition', `Spend at least ${code.minSpend} to use this code.`);
  }
  let off = 0;
  const pct = Number(code.percentOff ?? 0);
  if (pct > 0) off = itemsAmount * Math.min(pct, 90) / 100;
  else if (Number(code.amountOff ?? 0) > 0) {
    if (code.currency && code.currency.toUpperCase() !== currency.toUpperCase()) {
      throw new StoreRuleError('failed-precondition', 'That code is for another currency.');
    }
    off = Number(code.amountOff);
  }
  return Math.max(0, Math.min(off, itemsAmount));
}

/** Codes are stored upper-case, letters and digits only. */
export const normalizeCode = (raw: unknown) => String(raw ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 20);

/** Seller fulfilment steps on top of the escrow status. */
export const FULFILMENT = ['new', 'packed', 'ready', 'shipped'] as const;
export type Fulfilment = (typeof FULFILMENT)[number];
export function canFulfil(from: string | undefined, to: Fulfilment): boolean {
  const a = FULFILMENT.indexOf((from ?? 'new') as Fulfilment);
  const b = FULFILMENT.indexOf(to);
  return a >= 0 && b === a + 1;
}

/** Running average after one more rating. */
export function nextRating(avg: number | undefined, count: number | undefined, stars: number) {
  const n = Math.max(0, Number(count) || 0);
  const a = Number(avg) || 0;
  const s = Math.min(5, Math.max(1, Math.round(stars)));
  return { rating: Math.round(((a * n + s) / (n + 1)) * 100) / 100, reviewCount: n + 1 };
}
