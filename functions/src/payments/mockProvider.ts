/**
 * A deterministic provider for tests and the sandbox. It never touches money.
 *
 * Scenario by the amount's last two digits (so a tester can pick one):
 *   ..00–..89  accepted, status `paid`
 *   ..90       rejected, final (bad account)
 *   ..91       rejected, retryable (provider busy)
 *   ..92       unknown on payout, but the provider DID pay (late success)
 *   ..93       unknown on payout and the provider never got it (not_found)
 *   ..94       accepted, status `failed` later (network reversed it)
 * `down: true` makes every call retryable-rejected (outage drill).
 */
import { CallOutcome, PaymentProvider, PayoutRequest, ProviderId, ProviderStatus, Rail } from './provider';

export interface MockOptions {
  id?: ProviderId;
  down?: boolean;
  countries?: string[];
  rails?: Rail[];
}

export class MockProvider implements PaymentProvider {
  readonly id: ProviderId;
  /** reference → what the provider "knows". */
  readonly book = new Map<string, { status: ProviderStatus; providerRef: string; amountMinor: number }>();
  calls = 0;

  constructor(private readonly opts: MockOptions = {}) {
    this.id = opts.id ?? 'mock';
  }

  supports(country: string, rail: Rail): boolean {
    return (!this.opts.countries || this.opts.countries.includes(country)) && (!this.opts.rails || this.opts.rails.includes(rail));
  }

  async payout(req: PayoutRequest): Promise<CallOutcome> {
    this.calls++;
    if (this.opts.down) return { kind: 'rejected', reason: 'provider unavailable', retryable: true };
    const seen = this.book.get(req.reference);
    // Idempotent: the same reference never pays twice.
    if (seen && seen.status !== 'not_found') return { kind: 'accepted', providerRef: seen.providerRef };
    const ref = `${this.id}_${req.reference}`;
    switch (req.amountMinor % 100) {
      case 90: return { kind: 'rejected', reason: 'account not found', retryable: false };
      case 91: return { kind: 'rejected', reason: 'provider busy', retryable: true };
      case 92:
        this.book.set(req.reference, { status: 'paid', providerRef: ref, amountMinor: req.amountMinor });
        return { kind: 'unknown', reason: 'timeout' };
      case 93:
        return { kind: 'unknown', reason: 'timeout' };
      case 94:
        this.book.set(req.reference, { status: 'failed', providerRef: ref, amountMinor: req.amountMinor });
        return { kind: 'accepted', providerRef: ref };
      default:
        this.book.set(req.reference, { status: 'paid', providerRef: ref, amountMinor: req.amountMinor });
        return { kind: 'accepted', providerRef: ref };
    }
  }

  async status(reference: string) {
    const b = this.book.get(reference);
    if (!b) return { status: 'not_found' as ProviderStatus };
    return { status: b.status, providerRef: b.providerRef };
  }

  /** Total paid out for a reference (to prove nothing paid twice). */
  paidCount(reference: string): number {
    return this.book.get(reference)?.status === 'paid' ? 1 : 0;
  }
}
