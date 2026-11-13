/**
 * Pay-in partners behind `Collector` (Oneova Pay). Keys come from Secret
 * Manager (see pay/payConfig.ts); a missing key simply turns its rail off.
 * Nothing here reads Firestore, so every adapter is unit tested with a fake
 * fetch.
 *
 *   M-Pesa (Daraja)   STK push on the payer's phone, then STK query
 *   MTN MoMo          request-to-pay on the payer's phone, then status
 *   Flutterwave       the partner's secure page (card, mobile money, bank)
 *   Paystack          the partner's secure page (card, mobile money, bank)
 *   Sandbox           no money; approves a few seconds later (testing)
 *
 * Card numbers never touch Oneova: cards are only taken on a licensed
 * partner's hosted page.
 */
import {
  CallOutcome, CollectCheck, CollectKind, CollectOutcome, CollectRequest, Collector, FetchFn, ProviderStatus, Rail,
  callJson, retryableStatus, toMajor, toMinor,
} from './provider';

const FLW = 'https://api.flutterwave.com/v3';
const PAYSTACK = 'https://api.paystack.co';

const notFound = (): CollectCheck => ({ status: 'not_found' });
const unknown = (reason: string): CollectCheck => ({ status: 'unknown', reason });

// ───────────────────────────── M-Pesa (Daraja) ─────────────────────────────

export interface MpesaConfig {
  consumerKey: string;
  consumerSecret: string;
  /** Paybill or till shortcode. */
  shortcode: string;
  passkey: string;
  env: 'sandbox' | 'production';
  callbackUrl: string;
}

/** Daraja wants the timestamp in Kenya time (UTC+3) as YYYYMMDDHHmmss. */
export function darajaTimestamp(now: Date): string {
  const t = new Date(now.getTime() + 3 * 3600_000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

export class MpesaCollector implements Collector {
  readonly id = 'mpesa' as const;
  readonly kind: CollectKind = 'prompt';
  constructor(private readonly cfg: MpesaConfig, private readonly fetchFn: FetchFn, private readonly now: () => Date = () => new Date()) {}

  private get base() {
    return this.cfg.env === 'production' ? 'https://api.safaricom.co.ke' : 'https://sandbox.safaricom.co.ke';
  }

  supports(country: string, rail: Rail, currency: string, network?: string): boolean {
    return country === 'KE' && rail === 'mobile_money' && currency === 'KES' && (!network || network === 'MPESA');
  }

  private async token(): Promise<string | null> {
    const basic = Buffer.from(`${this.cfg.consumerKey}:${this.cfg.consumerSecret}`).toString('base64');
    const r = await callJson(this.fetchFn, `${this.base}/oauth/v1/generate?grant_type=client_credentials`, { headers: { Authorization: `Basic ${basic}` } });
    return r.kind === 'ok' && r.body?.access_token ? String(r.body.access_token) : null;
  }

  private password(ts: string) {
    return Buffer.from(`${this.cfg.shortcode}${this.cfg.passkey}${ts}`).toString('base64');
  }

  async collect(req: CollectRequest): Promise<CollectOutcome> {
    const amount = toMajor(req.amountMinor, req.currency);
    if (!Number.isInteger(amount) || amount < 1) return { kind: 'rejected', reason: 'M-Pesa takes whole shillings only.', retryable: false };
    if (!req.msisdn) return { kind: 'rejected', reason: 'Enter your M-Pesa number.', retryable: false };
    // No token means nothing was sent: safe to retry.
    const token = await this.token();
    if (!token) return { kind: 'rejected', reason: 'M-Pesa is not answering right now.', retryable: true };
    const ts = darajaTimestamp(this.now());
    const r = await callJson(this.fetchFn, `${this.base}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        BusinessShortCode: this.cfg.shortcode,
        Password: this.password(ts),
        Timestamp: ts,
        TransactionType: 'CustomerPayBillOnline',
        Amount: amount,
        PartyA: req.msisdn,
        PartyB: this.cfg.shortcode,
        PhoneNumber: req.msisdn,
        CallBackURL: this.cfg.callbackUrl,
        AccountReference: 'Oneova',
        TransactionDesc: (req.narration ?? 'Oneova payment').slice(0, 13),
      }),
    });
    if (r.kind === 'unknown') return { kind: 'unknown', reason: r.reason };
    if (r.kind === 'client_error') return { kind: 'rejected', reason: String(r.body?.errorMessage ?? r.reason).slice(0, 200), retryable: retryableStatus(r.status) };
    if (String(r.body?.ResponseCode) !== '0' || !r.body?.CheckoutRequestID) {
      return { kind: 'rejected', reason: String(r.body?.ResponseDescription ?? 'M-Pesa refused the request').slice(0, 200), retryable: false };
    }
    return { kind: 'accepted', providerRef: String(r.body.CheckoutRequestID) };
  }

  async check(_reference: string, providerRef?: string): Promise<CollectCheck> {
    if (!providerRef) return notFound();
    const token = await this.token();
    if (!token) return unknown('no token');
    const ts = darajaTimestamp(this.now());
    const r = await callJson(this.fetchFn, `${this.base}/mpesa/stkpushquery/v1/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ BusinessShortCode: this.cfg.shortcode, Password: this.password(ts), Timestamp: ts, CheckoutRequestID: providerRef }),
    });
    // While the payer hasn't answered, Daraja replies with an error code.
    const code = String(r.body?.errorCode ?? '');
    if (code === '500.001.1001') return { status: 'pending', providerRef };
    if (r.kind !== 'ok') return unknown(r.reason);
    const result = String(r.body?.ResultCode ?? '');
    if (result === '0') return { status: 'paid', providerRef };
    if (result === '') return { status: 'pending', providerRef };
    return { status: 'failed', providerRef, reason: String(r.body?.ResultDesc ?? 'The payment was not completed.').slice(0, 200) };
  }
}

// ───────────────────────────── MTN MoMo ─────────────────────────────

export interface MomoConfig {
  subscriptionKey: string;
  apiUser: string;
  apiKey: string;
  /** 'sandbox' or the live target environment (mtnuganda, mtnghana, ...). */
  env: string;
  callbackUrl?: string;
}

const MOMO_COUNTRIES = ['UG', 'GH', 'RW', 'ZM', 'CM', 'CI', 'BJ'];

export class MomoCollector implements Collector {
  readonly id = 'mtn_momo' as const;
  readonly kind: CollectKind = 'prompt';
  constructor(private readonly cfg: MomoConfig, private readonly fetchFn: FetchFn) {}

  private get sandbox() {
    return this.cfg.env === 'sandbox';
  }

  private get base() {
    return this.sandbox ? 'https://sandbox.momodeveloper.mtn.com' : 'https://proxy.momoapi.mtn.com';
  }

  supports(country: string, rail: Rail, _currency: string, network?: string): boolean {
    return rail === 'mobile_money' && MOMO_COUNTRIES.includes(country) && (!network || network === 'MTN');
  }

  private async token(): Promise<string | null> {
    const basic = Buffer.from(`${this.cfg.apiUser}:${this.cfg.apiKey}`).toString('base64');
    const r = await callJson(this.fetchFn, `${this.base}/collection/token/`, {
      method: 'POST',
      headers: { Authorization: `Basic ${basic}`, 'Ocp-Apim-Subscription-Key': this.cfg.subscriptionKey },
    });
    return r.kind === 'ok' && r.body?.access_token ? String(r.body.access_token) : null;
  }

  private headers(token: string, reference?: string): Record<string, string> {
    return {
      Authorization: `Bearer ${token}`,
      'X-Target-Environment': this.cfg.env,
      'Ocp-Apim-Subscription-Key': this.cfg.subscriptionKey,
      'Content-Type': 'application/json',
      ...(reference ? { 'X-Reference-Id': reference } : {}),
      ...(reference && this.cfg.callbackUrl ? { 'X-Callback-Url': this.cfg.callbackUrl } : {}),
    };
  }

  async collect(req: CollectRequest): Promise<CollectOutcome> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(req.reference)) {
      return { kind: 'rejected', reason: 'MoMo needs a UUID reference.', retryable: false };
    }
    if (!req.msisdn) return { kind: 'rejected', reason: 'Enter your MoMo number.', retryable: false };
    const token = await this.token();
    if (!token) return { kind: 'rejected', reason: 'MoMo is not answering right now.', retryable: true };
    let res;
    try {
      res = await this.fetchFn(`${this.base}/collection/v1_0/requesttopay`, {
        method: 'POST',
        headers: this.headers(token, req.reference),
        body: JSON.stringify({
          // The sandbox only takes EUR.
          amount: String(toMajor(req.amountMinor, req.currency)),
          currency: this.sandbox ? 'EUR' : req.currency,
          externalId: req.reference,
          payer: { partyIdType: 'MSISDN', partyId: req.msisdn },
          payerMessage: (req.narration ?? 'Oneova payment').slice(0, 160),
          payeeNote: 'Oneova',
        }),
      });
    } catch (e: any) {
      return { kind: 'unknown', reason: `network: ${String(e?.message ?? e).slice(0, 120)}` };
    }
    // 202: accepted. 409: this reference already exists (a retry) — same request.
    if (res.status === 202 || res.status === 409) return { kind: 'accepted', providerRef: req.reference };
    if (res.status >= 500 || res.status === 0) return { kind: 'unknown', reason: `provider error ${res.status}` };
    let msg = `refused (${res.status})`;
    try {
      msg = String(JSON.parse(await res.text())?.message ?? msg);
    } catch { /* keep msg */ }
    return { kind: 'rejected', reason: msg.slice(0, 200), retryable: retryableStatus(res.status) };
  }

  async check(reference: string): Promise<CollectCheck> {
    const token = await this.token();
    if (!token) return unknown('no token');
    const r = await callJson(this.fetchFn, `${this.base}/collection/v1_0/requesttopay/${encodeURIComponent(reference)}`, { headers: this.headers(token) });
    if (r.kind === 'client_error' && r.status === 404) return notFound();
    if (r.kind !== 'ok') return unknown(r.reason);
    const s = String(r.body?.status ?? '').toUpperCase();
    const status: ProviderStatus = s === 'SUCCESSFUL' ? 'paid' : s === 'FAILED' || s === 'REJECTED' || s === 'TIMEOUT' ? 'failed' : 'pending';
    const currency = String(r.body?.currency ?? '');
    return {
      status,
      providerRef: String(r.body?.financialTransactionId ?? reference),
      ...(status === 'paid' && currency && !this.sandbox ? { amountMinor: toMinor(Number(r.body?.amount), currency), currency } : {}),
      reason: r.body?.reason ? String(r.body.reason?.message ?? r.body.reason).slice(0, 200) : undefined,
    };
  }
}

// ───────────────────────────── Flutterwave (hosted page) ─────────────────────────────

export class FlutterwaveCollector implements Collector {
  readonly id = 'flutterwave' as const;
  readonly kind: CollectKind = 'hosted';
  constructor(private readonly key: string, private readonly fetchFn: FetchFn, private readonly countries: string[]) {}

  private headers() {
    return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
  }

  supports(country: string, rail: Rail): boolean {
    return rail === 'card' || ((rail === 'mobile_money' || rail === 'bank') && this.countries.includes(country));
  }

  async collect(req: CollectRequest): Promise<CollectOutcome> {
    const r = await callJson(this.fetchFn, `${FLW}/payments`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        tx_ref: req.reference,
        amount: toMajor(req.amountMinor, req.currency),
        currency: req.currency,
        redirect_url: req.returnUrl,
        payment_options: req.rail === 'card' ? 'card' : req.rail === 'bank' ? 'banktransfer,account' : 'mobilemoneyghana,mobilemoneyuganda,mobilemoneyrwanda,mobilemoneyzambia,mobilemoneytanzania,mobilemoneyfranco,mpesa',
        customer: { email: req.email, phonenumber: req.msisdn, name: req.payerName },
        customizations: { title: 'Oneova', description: (req.narration ?? 'Oneova payment').slice(0, 100) },
        meta: { reference: req.reference },
      }),
    });
    if (r.kind === 'unknown') return { kind: 'unknown', reason: r.reason };
    if (r.kind === 'client_error' || r.body?.status !== 'success' || !r.body?.data?.link) {
      return { kind: 'rejected', reason: String(r.body?.message ?? r.reason ?? 'Could not open the payment page').slice(0, 200), retryable: retryableStatus(r.status) };
    }
    // Opening a page moves no money; the payer pays there.
    return { kind: 'accepted', providerRef: '', redirectUrl: String(r.body.data.link) };
  }

  async check(reference: string): Promise<CollectCheck> {
    const r = await callJson(this.fetchFn, `${FLW}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(reference)}`, { headers: this.headers() });
    if (r.kind === 'client_error' && (r.status === 404 || /no transaction/i.test(String(r.body?.message ?? '')))) return notFound();
    if (r.kind !== 'ok') return unknown(r.reason);
    const d = r.body?.data ?? {};
    if (String(d.tx_ref ?? '') !== reference) return notFound();
    const s = String(d.status ?? '').toLowerCase();
    const status: ProviderStatus = s === 'successful' ? 'paid' : s === 'failed' || s === 'cancelled' ? 'failed' : 'pending';
    const currency = String(d.currency ?? '');
    return {
      status,
      providerRef: String(d.id ?? ''),
      ...(status === 'paid' && currency ? { amountMinor: toMinor(Number(d.amount), currency), currency } : {}),
      reason: d.processor_response ? String(d.processor_response).slice(0, 200) : undefined,
    };
  }

  async refund(_reference: string, providerRef: string, amountMinor: number, currency: string): Promise<CallOutcome> {
    if (!providerRef) return { kind: 'rejected', reason: 'missing transaction id', retryable: false };
    const r = await callJson(this.fetchFn, `${FLW}/transactions/${encodeURIComponent(providerRef)}/refund`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({ amount: toMajor(amountMinor, currency) }),
    });
    if (r.kind === 'unknown') return { kind: 'unknown', reason: r.reason };
    if (r.kind !== 'ok' || r.body?.status !== 'success') return { kind: 'rejected', reason: String(r.body?.message ?? r.reason).slice(0, 200), retryable: retryableStatus(r.status) };
    return { kind: 'accepted', providerRef: String(r.body?.data?.id ?? '') };
  }
}

// ───────────────────────────── Paystack (hosted page) ─────────────────────────────

const PAYSTACK_COUNTRIES = ['NG', 'GH', 'KE', 'ZA', 'CI'];

export class PaystackCollector implements Collector {
  readonly id = 'paystack' as const;
  readonly kind: CollectKind = 'hosted';
  constructor(private readonly key: string, private readonly fetchFn: FetchFn) {}

  private headers() {
    return { Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json' };
  }

  supports(country: string, rail: Rail): boolean {
    return PAYSTACK_COUNTRIES.includes(country) && (rail === 'card' || rail === 'mobile_money' || rail === 'bank');
  }

  async collect(req: CollectRequest): Promise<CollectOutcome> {
    const r = await callJson(this.fetchFn, `${PAYSTACK}/transaction/initialize`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        email: req.email,
        // Paystack takes the amount in subunits, which is our minor units.
        amount: req.amountMinor,
        currency: req.currency,
        reference: req.reference,
        callback_url: req.returnUrl,
        channels: req.rail === 'card' ? ['card'] : req.rail === 'bank' ? ['bank', 'bank_transfer', 'ussd'] : ['mobile_money'],
        metadata: { reference: req.reference },
      }),
    });
    if (r.kind === 'unknown') return { kind: 'unknown', reason: r.reason };
    if (r.kind === 'client_error' || !r.body?.status || !r.body?.data?.authorization_url) {
      return { kind: 'rejected', reason: String(r.body?.message ?? r.reason ?? 'Could not open the payment page').slice(0, 200), retryable: retryableStatus(r.status) };
    }
    return { kind: 'accepted', providerRef: String(r.body.data.access_code ?? ''), redirectUrl: String(r.body.data.authorization_url) };
  }

  async check(reference: string): Promise<CollectCheck> {
    const r = await callJson(this.fetchFn, `${PAYSTACK}/transaction/verify/${encodeURIComponent(reference)}`, { headers: this.headers() });
    if (r.kind === 'client_error' && (r.status === 404 || r.status === 400)) return notFound();
    if (r.kind !== 'ok') return unknown(r.reason);
    const d = r.body?.data ?? {};
    const s = String(d.status ?? '').toLowerCase();
    // "abandoned" / "ongoing": the payer hasn't finished on the page yet.
    const status: ProviderStatus = s === 'success' ? 'paid' : s === 'failed' || s === 'reversed' ? 'failed' : 'pending';
    return {
      status,
      providerRef: String(d.id ?? ''),
      ...(status === 'paid' ? { amountMinor: Number(d.amount), currency: String(d.currency ?? '') } : {}),
      reason: d.gateway_response ? String(d.gateway_response).slice(0, 200) : undefined,
    };
  }

  async refund(reference: string, _providerRef: string, amountMinor: number): Promise<CallOutcome> {
    const r = await callJson(this.fetchFn, `${PAYSTACK}/refund`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({ transaction: reference, amount: amountMinor }),
    });
    if (r.kind === 'unknown') return { kind: 'unknown', reason: r.reason };
    if (r.kind !== 'ok' || !r.body?.status) return { kind: 'rejected', reason: String(r.body?.message ?? r.reason).slice(0, 200), retryable: retryableStatus(r.status) };
    return { kind: 'accepted', providerRef: String(r.body?.data?.id ?? '') };
  }
}

// ───────────────────────────── Sandbox ─────────────────────────────

/**
 * Moves no money. The payer "approves" [approveAfterMs] after the prompt;
 * an amount ending in 90 (minor units) is declined, so failures can be tested.
 * Only switched on with PAY_SANDBOX=true, and every intent it touches is
 * marked `sandbox: true`.
 */
export class SandboxCollector implements Collector {
  readonly id = 'sandbox' as const;
  readonly kind: CollectKind = 'prompt';
  constructor(private readonly now: () => number = () => Date.now(), private readonly approveAfterMs = 4000) {}

  supports(): boolean {
    return true;
  }

  async collect(req: CollectRequest): Promise<CollectOutcome> {
    if (!Number.isSafeInteger(req.amountMinor) || req.amountMinor <= 0) return { kind: 'rejected', reason: 'invalid amount', retryable: false };
    return { kind: 'accepted', providerRef: `sbx_${this.now()}_${req.amountMinor}` };
  }

  async check(_reference: string, providerRef?: string): Promise<CollectCheck> {
    const m = /^sbx_(\d+)_(\d+)$/.exec(providerRef ?? '');
    if (!m) return notFound();
    const at = Number(m[1]);
    const amountMinor = Number(m[2]);
    if (this.now() - at < this.approveAfterMs) return { status: 'pending', providerRef };
    if (amountMinor % 100 === 90) return { status: 'failed', providerRef, reason: 'Declined on the phone (sandbox).' };
    return { status: 'paid', providerRef, amountMinor };
  }

  async refund(): Promise<CallOutcome> {
    return { kind: 'accepted', providerRef: `sbx_refund_${this.now()}` };
  }
}
