/**
 * Country signals the app sends with KYC (see lib/shared/location/country_detector.dart):
 * where the phone is (GPS through the phone's own geocoder), its mobile network,
 * SIM, phone number and region. Reviewers see them next to the country on the
 * ID; a mismatch is a hint for review, never an automatic rejection (people
 * live abroad).
 */
const KEYS = ['location', 'network', 'sim', 'phone', 'region'] as const;
export type SignalKey = (typeof KEYS)[number];

export function cleanCountrySignals(v: unknown): Partial<Record<SignalKey, string>> {
  const out: Partial<Record<SignalKey, string>> = {};
  if (!v || typeof v !== 'object' || Array.isArray(v)) return out;
  const o = v as Record<string, unknown>;
  for (const k of KEYS) {
    const c = o[k];
    if (typeof c === 'string' && /^[A-Za-z]{2}$/.test(c)) out[k] = c.toUpperCase();
  }
  return out;
}

/** True when the strongest "where you are" signal differs from the ID country. */
export function countryMismatch(declared: string, s: Partial<Record<SignalKey, string>>): boolean {
  const where = s.location ?? s.network ?? s.sim;
  return !!where && where !== declared;
}
