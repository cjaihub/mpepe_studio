/**
 * Picks a provider for a payout and fails over only when it is safe.
 *
 *   accepted              → done, record providerRef
 *   rejected + retryable  → try the next provider (nothing moved)
 *   rejected (final)      → stop; the request itself is bad (wrong number...)
 *   unknown               → STOP. The money may have moved; reconcile by status
 *                           before anyone retries. Never fail over on unknown.
 *
 * Health is a small circuit breaker per provider: after [failThreshold]
 * unknown/retryable results in a row it is skipped for [cooldownMs].
 */
import { CallOutcome, PaymentProvider, PayoutRequest, ProviderId } from './provider';

export interface ProviderHealth {
  consecutiveFailures: number;
  openUntil: number;
}

export interface RouteOptions {
  /** Cost or preference order (cheapest first). Unlisted providers go last. */
  preference?: ProviderId[];
  health?: Partial<Record<ProviderId, ProviderHealth>>;
  now?: number;
  failThreshold?: number;
  cooldownMs?: number;
}

export interface RouteAttempt {
  provider: ProviderId;
  outcome: CallOutcome;
}

export interface RouteResult {
  /** Final outcome; `rejected` when every candidate refused or none fit. */
  outcome: CallOutcome;
  provider: ProviderId | null;
  attempts: RouteAttempt[];
  health: Partial<Record<ProviderId, ProviderHealth>>;
}

export function candidates(providers: PaymentProvider[], req: PayoutRequest, opts: RouteOptions = {}): PaymentProvider[] {
  const now = opts.now ?? Date.now();
  const pref = opts.preference ?? [];
  const rank = (p: PaymentProvider) => (pref.includes(p.id) ? pref.indexOf(p.id) : pref.length);
  return providers
    .filter((p) => p.supports(req.country, req.rail, req.currency))
    .filter((p) => (opts.health?.[p.id]?.openUntil ?? 0) <= now)
    .sort((a, b) => rank(a) - rank(b));
}

export async function routePayout(providers: PaymentProvider[], req: PayoutRequest, opts: RouteOptions = {}): Promise<RouteResult> {
  if (!Number.isSafeInteger(req.amountMinor) || req.amountMinor <= 0) {
    return { outcome: { kind: 'rejected', reason: 'invalid amount', retryable: false }, provider: null, attempts: [], health: { ...opts.health } };
  }
  const now = opts.now ?? Date.now();
  const threshold = opts.failThreshold ?? 3;
  const cooldown = opts.cooldownMs ?? 5 * 60_000;
  const health: Partial<Record<ProviderId, ProviderHealth>> = { ...opts.health };
  const attempts: RouteAttempt[] = [];

  const mark = (id: ProviderId, ok: boolean) => {
    const h = health[id] ?? { consecutiveFailures: 0, openUntil: 0 };
    const failures = ok ? 0 : h.consecutiveFailures + 1;
    health[id] = { consecutiveFailures: failures, openUntil: failures >= threshold ? now + cooldown : h.openUntil };
  };

  for (const p of candidates(providers, req, opts)) {
    let outcome: CallOutcome;
    try {
      outcome = await p.payout(req);
    } catch (e: any) {
      // An adapter that throws broke its contract; treat it as unknown (safe side).
      outcome = { kind: 'unknown', reason: `adapter error: ${String(e?.message ?? e).slice(0, 120)}` };
    }
    attempts.push({ provider: p.id, outcome });
    if (outcome.kind === 'accepted') {
      mark(p.id, true);
      return { outcome, provider: p.id, attempts, health };
    }
    if (outcome.kind === 'unknown') {
      mark(p.id, false);
      return { outcome, provider: p.id, attempts, health };
    }
    if (!outcome.retryable) {
      mark(p.id, true); // the provider is healthy; the request was refused
      return { outcome, provider: p.id, attempts, health };
    }
    mark(p.id, false);
  }
  const last = attempts[attempts.length - 1];
  return {
    outcome: last?.outcome.kind === 'rejected' ? last.outcome : { kind: 'rejected', reason: 'No payout partner is available for this method right now.', retryable: true },
    provider: last?.provider ?? null,
    attempts,
    health,
  };
}

/**
 * What to do with a payout whose outcome was unknown, given the provider's
 * status answer and how long ago it was sent.
 *   settle_paid / settle_failed  final
 *   wait                         ask again later
 *   review                       a person must check the provider dashboard
 */
export type ReconcileAction = 'settle_paid' | 'settle_failed' | 'wait' | 'review';

export function reconcileAction(
  status: 'paid' | 'failed' | 'pending' | 'not_found' | 'unknown',
  ageMs: number,
  opts: { notFoundIsFinalAfterMs?: number | null; reviewAfterMs?: number } = {},
): ReconcileAction {
  const reviewAfter = opts.reviewAfterMs ?? 24 * 3600_000;
  if (status === 'paid') return 'settle_paid';
  if (status === 'failed') return 'settle_failed';
  if (status === 'not_found') {
    // Only for providers whose lookup by reference is documented and reliable.
    const finalAfter = opts.notFoundIsFinalAfterMs;
    if (finalAfter != null && ageMs >= finalAfter) return 'settle_failed';
    return ageMs >= reviewAfter ? 'review' : 'wait';
  }
  return ageMs >= reviewAfter ? 'review' : 'wait';
}
