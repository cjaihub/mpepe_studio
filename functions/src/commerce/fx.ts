/**
 * World exchange rates for the shops.
 *
 * `fx_rates/USD` holds units of every currency per 1 US dollar (about 160
 * currencies). fxRefresh rewrites it every hour, so the app's live stream of
 * that document updates every open screen on its own. The source publishes
 * new rates once a day; the hourly run picks them up within the hour.
 *
 * Payouts (creator/payouts.ts) read the same document.
 */
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const SOURCE = 'https://open.er-api.com/v6/latest/USD';

export async function refreshRates(): Promise<number> {
  const res = (await fetch(SOURCE, { signal: AbortSignal.timeout(20_000) }).then((r) => r.json())) as any;
  if (res?.result !== 'success' || !res.rates || typeof res.rates !== 'object') throw new Error('rates source answered without rates');
  const rates: Record<string, number> = {};
  for (const [code, value] of Object.entries(res.rates)) {
    if (/^[A-Z]{3}$/.test(code) && typeof value === 'number' && Number.isFinite(value) && value > 0) rates[code] = value;
  }
  if (Object.keys(rates).length < 100) throw new Error('rates source answered with too few currencies');
  await getFirestore().doc('fx_rates/USD').set({
    rates,
    fetchedAt: FieldValue.serverTimestamp(),
    sourceUpdatedAt: Number(res.time_last_update_unix ?? 0) * 1000 || null,
    source: 'open.er-api.com',
  });
  return Object.keys(rates).length;
}

export const fxRefresh = onSchedule({ schedule: 'every 60 minutes', timeoutSeconds: 60 }, async () => {
  try {
    logger.info('fx rates refreshed', await refreshRates());
  } catch (e: any) {
    // The last good rates stay in place.
    logger.warn('fx refresh failed', e?.message ?? e);
  }
});

/** Units of [currency] per 1 USD from the stored rates, or null. */
export async function storedUsdRate(currency: string): Promise<number | null> {
  if (currency === 'USD') return 1;
  const r = (await getFirestore().doc('fx_rates/USD').get()).get('rates')?.[currency];
  return typeof r === 'number' && Number.isFinite(r) && r > 0 ? r : null;
}
