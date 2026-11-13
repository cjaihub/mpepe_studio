/**
 * Pure rules for the AI listing draft: bound what the model returns and turn
 * price evidence into one suggestion band. Tested in __tests__/models3d.test.ts.
 */

export interface ListingColor { name: string; hex: string }
export interface PriceEstimate { low: number; typical: number; high: number }

export interface ListingDraft {
  name: string;
  description: string;
  category: string;
  condition: 'new' | 'used' | 'refurbished';
  material: string;
  colors: ListingColor[];
  tags: string[];
  price: PriceEstimate | null;
  /** 0..1: how sure the model is about what the product is. */
  confidence: number;
  /** One short tip for better photos / 3D capture, or ''. */
  photoTip: string;
}

const str = (v: unknown, max: number) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : null);

export function cleanListing(raw: unknown): ListingDraft {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const colors: ListingColor[] = [];
  for (const c of Array.isArray(r.colors) ? r.colors : []) {
    if (!c || typeof c !== 'object') continue;
    const name = str((c as any).name, 30);
    const hex = String((c as any).hex ?? '').replace('#', '');
    if (name && /^[0-9a-fA-F]{6}$/.test(hex) && colors.length < 8) colors.push({ name, hex: `#${hex.toUpperCase()}` });
  }
  const tags: string[] = [];
  for (const t of Array.isArray(r.tags) ? r.tags : []) {
    const s = str(t, 24).toLowerCase();
    if (s && !tags.includes(s) && tags.length < 10) tags.push(s);
  }
  const p = (r.price && typeof r.price === 'object' ? r.price : {}) as Record<string, unknown>;
  const band = [num(p.low), num(p.typical), num(p.high)];
  const price = band.every((n) => n !== null)
    ? (() => {
        const [low, typical, high] = (band as number[]).slice().sort((a, b) => a - b);
        return { low, typical, high };
      })()
    : null;
  const condition = ['new', 'used', 'refurbished'].includes(String(r.condition)) ? (r.condition as ListingDraft['condition']) : 'new';
  const conf = typeof r.confidence === 'number' && Number.isFinite(r.confidence) ? r.confidence : 0;
  return {
    name: str(r.name, 120),
    description: str(r.description, 4000),
    category: str(r.category, 40),
    condition,
    material: str(r.material, 60),
    colors,
    tags,
    price,
    confidence: Math.min(1, Math.max(0, conf)),
    photoTip: str(r.photoTip, 160),
  };
}

export function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const s = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const ZERO_DECIMAL = new Set(['BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF', 'TZS']);

/** Whole units where people price in whole units; two decimals otherwise. */
export function roundPrice(n: number, currency: string): number {
  if (ZERO_DECIMAL.has(currency.toUpperCase()) || n >= 1000) return Math.round(n);
  return Math.round(n * 100) / 100;
}

export interface PriceBand extends PriceEstimate {
  /** 'oneova' = what similar products sell for here; 'estimate' = the model's market estimate. */
  basis: 'oneova' | 'estimate';
  samples: number;
}

/**
 * Five or more similar products on Oneova in the same currency beat the
 * model's estimate (quartiles of real prices). Fewer: the estimate stands.
 */
export function priceBand(estimate: PriceEstimate | null, comparables: number[], currency: string): PriceBand | null {
  const real = comparables.filter((n) => Number.isFinite(n) && n > 0).sort((a, b) => a - b);
  if (real.length >= 5) {
    const q = (f: number) => real[Math.min(real.length - 1, Math.floor(f * (real.length - 1)))];
    return {
      low: roundPrice(q(0.25), currency),
      typical: roundPrice(median(real)!, currency),
      high: roundPrice(q(0.75), currency),
      basis: 'oneova',
      samples: real.length,
    };
  }
  if (!estimate) return null;
  return {
    low: roundPrice(estimate.low, currency),
    typical: roundPrice(estimate.typical, currency),
    high: roundPrice(estimate.high, currency),
    basis: 'estimate',
    samples: real.length,
  };
}
