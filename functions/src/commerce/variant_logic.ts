/**
 * Product variants and stock for Oneova Biz / 3D Shops (pure, unit-tested).
 *
 * A product may carry `variants: [{id, name, colorHex?, stock?, modelVariant?}]`.
 * Stock lives on the product (`stock`) and optionally per variant (`variants[i].stock`).
 * The server is the only place that decides which variant was bought and how
 * much stock is left; the app only displays it.
 */

export interface Variant {
  id: string;
  name: string;
  stock: number | null;
}

export class VariantError extends Error {
  constructor(public code: 'invalid-argument' | 'failed-precondition', message: string) {
    super(message);
  }
}

const asStock = (v: unknown): number | null =>
  typeof v === 'number' && Number.isFinite(v) ? Math.max(0, Math.floor(v)) : null;

export function variantsOf(product: Record<string, unknown>): Variant[] {
  const raw = Array.isArray(product.variants) ? product.variants : [];
  const out: Variant[] = [];
  for (const v of raw) {
    if (!v || typeof v !== 'object') continue;
    const m = v as Record<string, unknown>;
    const id = typeof m.id === 'string' ? m.id : '';
    if (!id) continue;
    out.push({ id, name: typeof m.name === 'string' ? m.name.slice(0, 60) : id, stock: asStock(m.stock) });
  }
  return out;
}

/**
 * Validates the buyer's variant choice for a checkout of `qty` units.
 * Products with variants require one; products without variants reject one.
 */
export function pickVariant(product: Record<string, unknown>, variantId: unknown, qty: number): Variant | null {
  const variants = variantsOf(product);
  const id = typeof variantId === 'string' ? variantId.trim() : '';
  if (variants.length === 0) {
    if (id) throw new VariantError('invalid-argument', 'This product has no options to choose from.');
    return null;
  }
  if (!id) throw new VariantError('invalid-argument', 'Choose an option first.');
  const v = variants.find((x) => x.id === id);
  if (!v) throw new VariantError('invalid-argument', 'That option is no longer available.');
  if (v.stock !== null && v.stock < qty) throw new VariantError('failed-precondition', `Not enough ${v.name} in stock.`);
  return v;
}

/**
 * Stock fields to write after a paid sale. Never goes below zero; `shortfall`
 * tells the caller the sale outran the stock (two buyers paid for the last one).
 */
export function stockAfterSale(
  product: Record<string, unknown>,
  variantId: string | null,
  qty: number,
): { update: Record<string, unknown>; shortfall: boolean } {
  const update: Record<string, unknown> = {};
  let shortfall = false;

  const stock = asStock(product.stock);
  if (stock !== null) {
    if (stock < qty) shortfall = true;
    const left = Math.max(0, stock - qty);
    update.stock = left;
    if (left === 0) update.inStock = false;
  }

  if (variantId && Array.isArray(product.variants)) {
    update.variants = (product.variants as unknown[]).map((v) => {
      if (!v || typeof v !== 'object') return v;
      const m = v as Record<string, unknown>;
      if (m.id !== variantId) return m;
      const vs = asStock(m.stock);
      if (vs === null) return m;
      if (vs < qty) shortfall = true;
      return { ...m, stock: Math.max(0, vs - qty) };
    });
  }

  return { update, shortfall };
}
