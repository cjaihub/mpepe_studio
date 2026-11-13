/**
 * One interface for every payment partner (Flutterwave, Paystack, M-Pesa,
 * MTN MoMo, banks, the sandbox and the test mock). No Firestore here, so it is unit tested.
 *
 * The one rule that keeps money safe: a provider call ends in exactly one of
 *   accepted  the provider took it (it may still finish later by webhook)
 *   rejected  the provider definitely did NOT take it, so it is safe to retry
 *             elsewhere or give the money back
 *   unknown   we can't tell (timeout, 5xx, unreadable reply). The money may have
 *             moved. Never refund or fail over on this; ask the provider's
 *             status endpoint later (reconcile).
 */

export type Rail = 'mobile_money' | 'bank' | 'card';
export type ProviderId = 'flutterwave' | 'paystack' | 'mpesa' | 'mtn_momo' | 'sandbox' | 'mock' | 'mock_b';

export interface PayoutRequest {
  /** Our reference; the provider's idempotency key. Same reference = same payout. */
  reference: string;
  country: string;
  rail: Rail;
  currency: string;
  /** Integer minor units of [currency] (cents, or whole units for UGX/XOF...). */
  amountMinor: number;
  holderName: string;
  /** Mobile number (digits with dial code) or account number. */
  account: string;
  /** Network or bank code the provider needs. */
  bankCode?: string;
  narration?: string;
}

export interface CollectRequest {
  /** Our intent id (a UUID): the provider's reference / idempotency key. */
  reference: string;
  country: string;
  rail: Rail;
  currency: string;
  amountMinor: number;
  /** Payer's mobile number (digits with dial code) for a phone prompt. */
  msisdn?: string;
  /** Mobile money network id from the AFRICA table (MPESA, MTN, ...). */
  network?: string;
  email?: string;
  payerName?: string;
  /** Where a hosted payment page sends the payer back. */
  returnUrl?: string;
  narration?: string;
}

/** How a payer finishes a pay-in: approve a prompt on the phone, or a partner's secure page. */
export type CollectKind = 'prompt' | 'hosted' | 'instant';

export type CollectOutcome =
  | { kind: 'accepted'; providerRef: string; redirectUrl?: string }
  | { kind: 'rejected'; reason: string; retryable: boolean }
  | { kind: 'unknown'; reason: string };

export interface CollectCheck {
  status: ProviderStatus;
  providerRef?: string;
  /** What the provider says was actually paid (checked against the intent). */
  amountMinor?: number;
  currency?: string;
  reason?: string;
}

/** A partner that takes money in. Separate from payouts: few partners do both the same way. */
export interface Collector {
  id: ProviderId;
  kind: CollectKind;
  supports(country: string, rail: Rail, currency: string, network?: string): boolean;
  collect(req: CollectRequest): Promise<CollectOutcome>;
  /** Status of a pay-in by our reference (and the provider's ref when the lookup needs it). */
  check(reference: string, providerRef?: string): Promise<CollectCheck>;
  /** Gives a finished pay-in back (whole or part). Absent: refunds go to review. */
  refund?(reference: string, providerRef: string, amountMinor: number, currency: string): Promise<CallOutcome>;
}

export type CallOutcome =
  | { kind: 'accepted'; providerRef: string }
  | { kind: 'rejected'; reason: string; retryable: boolean }
  | { kind: 'unknown'; reason: string };

export type ProviderStatus = 'paid' | 'failed' | 'pending' | 'not_found' | 'unknown';

export interface PaymentProvider {
  id: ProviderId;
  supports(country: string, rail: Rail, currency: string): boolean;
  payout(req: PayoutRequest): Promise<CallOutcome>;
  /** Status of a payout by our reference. */
  status(reference: string): Promise<{ status: ProviderStatus; providerRef?: string; reason?: string }>;
}

/** Minimal fetch type so tests can pass a fake. */
export type FetchFn = (url: string, init?: { method?: string; headers?: Record<string, string>; body?: string }) =>
  Promise<{ status: number; text(): Promise<string> }>;

export interface HttpResult {
  /** 'ok' when the HTTP call finished with 2xx and readable JSON. */
  kind: 'ok' | 'client_error' | 'unknown';
  status: number;
  body: any;
  reason: string;
}

/**
 * Calls a provider and sorts the result into ok / client_error / unknown.
 * A network error, timeout, 5xx or unreadable body is `unknown`: the request
 * may have reached the provider. 4xx with a JSON body is `client_error`: the
 * provider read it and said no.
 */
export async function callJson(fetchFn: FetchFn, url: string, init: Parameters<FetchFn>[1] = {}): Promise<HttpResult> {
  let res;
  try {
    res = await fetchFn(url, init);
  } catch (e: any) {
    return { kind: 'unknown', status: 0, body: null, reason: `network: ${String(e?.message ?? e).slice(0, 120)}` };
  }
  let body: any = null;
  try {
    body = JSON.parse(await res.text());
  } catch {
    return { kind: res.status >= 400 && res.status < 500 ? 'client_error' : 'unknown', status: res.status, body: null, reason: `unreadable reply (${res.status})` };
  }
  if (res.status >= 500 || res.status === 0) return { kind: 'unknown', status: res.status, body, reason: `provider error ${res.status}` };
  if (res.status >= 400) return { kind: 'client_error', status: res.status, body, reason: String(body?.message ?? `refused (${res.status})`).slice(0, 200) };
  return { kind: 'ok', status: res.status, body, reason: '' };
}

/** 408 / 409 / 429 mean "not processed now", so trying again (or elsewhere) is safe. */
export const retryableStatus = (status: number) => status === 408 || status === 429 || status === 409;

/** ISO-4217 minor-unit exponents for the currencies we pay out in (default 2). */
const EXPONENT: Record<string, number> = {
  UGX: 0, RWF: 0, XAF: 0, XOF: 0, BIF: 0, GNF: 0, KMF: 0, DJF: 0, JPY: 0, KRW: 0, VND: 0, CLP: 0, PYG: 0,
  // Shillings and naira have cents on paper but providers pay whole units.
  KES: 2, TZS: 2, NGN: 2, GHS: 2, ZAR: 2, ZMW: 2, MWK: 2, EGP: 2, ETB: 2, USD: 2, EUR: 2, GBP: 2,
};
export const exponent = (currency: string) => EXPONENT[currency.toUpperCase()] ?? 2;

/** Integer minor units → the decimal number a provider's JSON field expects. */
export function toMajor(amountMinor: number, currency: string): number {
  if (!Number.isSafeInteger(amountMinor)) throw new Error('amount must be an integer number of minor units');
  const e = exponent(currency);
  return e === 0 ? amountMinor : Number((amountMinor / 10 ** e).toFixed(e));
}

/** A decimal amount → integer minor units, rounded half-up once at the edge. */
export function toMinor(amount: number, currency: string): number {
  const e = exponent(currency);
  return Math.round(Number((amount * 10 ** e).toFixed(6)));
}
