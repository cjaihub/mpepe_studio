/**
 * Real partner adapters behind PaymentProvider. Keys come from Secret Manager
 * (see creator/payouts.ts `configured()`); nothing here reads Firestore.
 *
 * Status lookups by our reference:
 *   Paystack     GET /transfer/verify/:reference (documented) → a not_found an
 *                hour later is final.
 *   Flutterwave  GET /v3/transfers?reference= — only an item whose reference
 *                matches ours counts; not_found never refunds by itself, it
 *                goes to a person. Check this filter in the sandbox.
 *   Stripe       transfers are idempotent by key, so reconcile re-sends the
 *                same request (`idempotentRetry`) instead of looking it up.
 */
import Stripe from 'stripe';
import {
  CallOutcome, FetchFn, PaymentProvider, PayoutRequest, ProviderStatus, Rail, callJson, retryableStatus, toMajor,
} from './provider';

const FLW = 'https://api.flutterwave.com/v3';
const PAYSTACK = 'https://api.paystack.co';

export interface ReconcilePolicy {
  /** null: a not_found answer never fails a payout on its own. */
  notFoundIsFinalAfterMs: number | null;
  /** Re-sending the same reference is safe (provider dedupes it). */
  idempotentRetry: boolean;
}

export const POLICY: Record<string, ReconcilePolicy> = {
  paystack: { notFoundIsFinalAfterMs: 3600_000, idempotentRetry: false },
  flutterwave: { notFoundIsFinalAfterMs: null, idempotentRetry: false },
  stripe: { notFoundIsFinalAfterMs: null, idempotentRetry: true },
  mock: { notFoundIsFinalAfterMs: 3600_000, idempotentRetry: true },
};

const fromHttp = (r: { kind: string; status: number; reason: string }): CallOutcome =>
  r.kind === 'unknown'
    ? { kind: 'unknown', reason: r.reason }
    : { kind: 'rejected', reason: r.reason, retryable: retryableStatus(r.status) };

export class FlutterwaveProvider implements PaymentProvider {
  readonly id = 'flutterwave' as const;
  constructor(private readonly key: string, private readonly fetchFn: FetchFn) {}

  supports(_country: string, rail: Rail): boolean {
    return rail === 'mobile_money' || rail === 'bank';
  }

  private headers() {
    return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
  }

  async payout(req: PayoutRequest): Promise<CallOutcome> {
    const r = await callJson(this.fetchFn, `${FLW}/transfers`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        account_bank: req.bankCode,
        account_number: req.account,
        amount: toMajor(req.amountMinor, req.currency),
        currency: req.currency,
        debit_currency: 'USD',
        narration: req.narration ?? 'Oneova payout',
        reference: req.reference,
        beneficiary_name: req.holderName,
      }),
    });
    if (r.kind !== 'ok') return fromHttp(r);
    if (r.body?.status !== 'success') return { kind: 'rejected', reason: String(r.body?.message ?? 'Flutterwave refused the transfer').slice(0, 200), retryable: false };
    return { kind: 'accepted', providerRef: String(r.body?.data?.id ?? '') };
  }

  async status(reference: string) {
    const r = await callJson(this.fetchFn, `${FLW}/transfers?reference=${encodeURIComponent(reference)}`, { headers: this.headers() });
    if (r.kind !== 'ok') return { status: 'unknown' as ProviderStatus, reason: r.reason };
    const items: any[] = Array.isArray(r.body?.data) ? r.body.data : r.body?.data ? [r.body.data] : [];
    const t = items.find((x) => String(x?.reference ?? '') === reference);
    if (!t) return { status: 'not_found' as ProviderStatus };
    const s = String(t.status ?? '').toUpperCase();
    const status: ProviderStatus = s === 'SUCCESSFUL' ? 'paid' : s === 'FAILED' ? 'failed' : 'pending';
    return { status, providerRef: String(t.id ?? ''), reason: t.complete_message };
  }
}

export class PaystackProvider implements PaymentProvider {
  readonly id = 'paystack' as const;
  /**
   * [recipient] returns a cached recipient code for this payee, or null;
   * [saveRecipient] stores a new one. Creating a recipient moves no money.
   */
  constructor(
    private readonly key: string,
    private readonly fetchFn: FetchFn,
    private readonly recipient: (req: PayoutRequest) => Promise<string | null> = async () => null,
    private readonly saveRecipient: (req: PayoutRequest, code: string) => Promise<void> = async () => undefined,
  ) {}

  supports(country: string, rail: Rail): boolean {
    return ['NG', 'GH', 'KE', 'ZA', 'CI'].includes(country) && (rail === 'mobile_money' || rail === 'bank');
  }

  private headers() {
    return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
  }

  async payout(req: PayoutRequest): Promise<CallOutcome> {
    let code = await this.recipient(req);
    if (!code) {
      const bankType: Record<string, string> = { NG: 'nuban', GH: 'ghipss', KE: 'kepss', ZA: 'basa' };
      const r = await callJson(this.fetchFn, `${PAYSTACK}/transferrecipient`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify(req.rail === 'mobile_money'
          ? { type: 'mobile_money', name: req.holderName, account_number: req.account, bank_code: req.bankCode, currency: req.currency }
          : { type: bankType[req.country] ?? 'nuban', name: req.holderName, account_number: req.account, bank_code: req.bankCode, currency: req.currency }),
      });
      // No transfer was sent yet, so any failure here is a safe "rejected".
      if (r.kind !== 'ok' || !r.body?.status) {
        return { kind: 'rejected', reason: r.reason || String(r.body?.message ?? 'Paystack could not add this account'), retryable: r.kind === 'unknown' || retryableStatus(r.status) };
      }
      code = String(r.body.data.recipient_code);
      await this.saveRecipient(req, code);
    }
    const t = await callJson(this.fetchFn, `${PAYSTACK}/transfer`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        source: 'balance', amount: req.amountMinor, recipient: code, reference: req.reference,
        reason: req.narration ?? 'Oneova payout', currency: req.currency,
      }),
    });
    if (t.kind !== 'ok') return fromHttp(t);
    if (!t.body?.status) return { kind: 'rejected', reason: String(t.body?.message ?? 'Paystack refused the transfer').slice(0, 200), retryable: false };
    return { kind: 'accepted', providerRef: String(t.body?.data?.transfer_code ?? '') };
  }

  async status(reference: string) {
    const r = await callJson(this.fetchFn, `${PAYSTACK}/transfer/verify/${encodeURIComponent(reference)}`, { headers: this.headers() });
    if (r.kind === 'client_error' && r.status === 404) return { status: 'not_found' as ProviderStatus };
    if (r.kind !== 'ok') return { status: 'unknown' as ProviderStatus, reason: r.reason };
    const s = String(r.body?.data?.status ?? '');
    const status: ProviderStatus = s === 'success' ? 'paid' : s === 'failed' || s === 'reversed' ? 'failed' : 'pending';
    return { status, providerRef: String(r.body?.data?.transfer_code ?? ''), reason: r.body?.data?.reason };
  }
}

export class StripeTransferProvider implements PaymentProvider {
  readonly id = 'stripe' as const;
  constructor(private readonly stripe: Pick<Stripe, 'transfers'>) {}

  supports(_country: string, rail: Rail, currency: string): boolean {
    return rail === 'stripe' && currency.toUpperCase() === 'USD';
  }

  async payout(req: PayoutRequest): Promise<CallOutcome> {
    try {
      const t = await this.stripe.transfers.create({
        amount: req.amountMinor, currency: 'usd', destination: req.account,
        description: req.narration ?? 'Oneova payout', metadata: { reference: req.reference },
      }, { idempotencyKey: `wd_${req.reference}` });
      return { kind: 'accepted', providerRef: t.id };
    } catch (e: any) {
      const type = String(e?.type ?? '');
      if (type === 'StripeConnectionError' || type === 'StripeAPIError' || (e?.statusCode ?? 0) >= 500) {
        return { kind: 'unknown', reason: String(e?.message ?? 'Stripe did not answer').slice(0, 200) };
      }
      return { kind: 'rejected', reason: String(e?.message ?? 'Stripe refused the transfer').slice(0, 200), retryable: type === 'StripeRateLimitError' };
    }
  }

  async status() {
    // Looked up by re-sending with the same idempotency key (POLICY.stripe).
    return { status: 'unknown' as ProviderStatus };
  }
}
