/**
 * Which Oneova Pay partners are switched on, from Secret Manager. A partner
 * with no keys is simply off; nothing else changes when its keys arrive.
 *
 * Secrets (read at run time with optionalSecret):
 *   MPESA_CONSUMER_KEY, MPESA_CONSUMER_SECRET, MPESA_SHORTCODE, MPESA_PASSKEY
 *   MTN_MOMO_SUBSCRIPTION_KEY, MTN_MOMO_API_USER, MTN_MOMO_API_KEY
 *   FLUTTERWAVE_SECRET_KEY, PAYSTACK_SECRET_KEY (shared with payouts)
 * Env params (functions/.env.mpepe-2b4bd):
 *   MPESA_ENV=sandbox|production, MTN_MOMO_ENV=sandbox|mtnuganda|mtnghana|...
 *   PAY_SANDBOX=true      sandbox rails for testing (no money moves)
 *   PAY_WALLET_ENABLED=true  stored Oneova balance (needs the e-money licence)
 *   PAY_RETURN_URL        where hosted pages send the payer back
 */
import { optionalSecret } from '../optionalSecrets';
import { Collector, FetchFn, ProviderId } from '../payments/provider';
import {
  FlutterwaveCollector, MomoCollector, MpesaCollector, PaystackCollector, SandboxCollector,
} from '../payments/collectAdapters';
import { AFRICA } from '../creator/payoutLogic';
import { PayConfig } from './payLogic';

const REGION = 'us-central1';

function projectId(): string {
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  try {
    return JSON.parse(process.env.FIREBASE_CONFIG ?? '{}').projectId ?? '';
  } catch {
    return '';
  }
}

/** Public URL of an HTTP function in this project (partner callbacks). */
export const functionUrl = (name: string) => `https://${REGION}-${projectId()}.cloudfunctions.net/${name}`;

/** Where a partner's secure page sends the payer back (our payReturn page by default). */
export const returnUrl = () => (process.env.PAY_RETURN_URL ?? '').trim() || functionUrl('payReturn');

const flag = (name: string) => (process.env[name] ?? '').trim().toLowerCase() === 'true';

export interface PayRuntime {
  cfg: PayConfig;
  collectors: Partial<Record<ProviderId, Collector>>;
}

export async function payRuntime(): Promise<PayRuntime> {
  const [mk, ms, sc, pk, msub, muser, mkey, flw, ps] = await Promise.all([
    optionalSecret('MPESA_CONSUMER_KEY'), optionalSecret('MPESA_CONSUMER_SECRET'), optionalSecret('MPESA_SHORTCODE'), optionalSecret('MPESA_PASSKEY'),
    optionalSecret('MTN_MOMO_SUBSCRIPTION_KEY'), optionalSecret('MTN_MOMO_API_USER'), optionalSecret('MTN_MOMO_API_KEY'),
    optionalSecret('FLUTTERWAVE_SECRET_KEY'), optionalSecret('PAYSTACK_SECRET_KEY'),
  ]);
  const f = fetch as unknown as FetchFn;
  const collectors: Partial<Record<ProviderId, Collector>> = {};
  if (mk && ms && sc && pk) {
    collectors.mpesa = new MpesaCollector({
      consumerKey: mk, consumerSecret: ms, shortcode: sc, passkey: pk,
      env: process.env.MPESA_ENV === 'production' ? 'production' : 'sandbox',
      callbackUrl: functionUrl('payWebhookMpesa'),
    }, f);
  }
  if (msub && muser && mkey) {
    collectors.mtn_momo = new MomoCollector({
      subscriptionKey: msub, apiUser: muser, apiKey: mkey,
      env: (process.env.MTN_MOMO_ENV ?? 'sandbox').trim() || 'sandbox',
      callbackUrl: functionUrl('payWebhookMomo'),
    }, f);
  }
  if (flw) collectors.flutterwave = new FlutterwaveCollector(flw, f, Object.keys(AFRICA));
  if (ps) collectors.paystack = new PaystackCollector(ps, f);
  const sandbox = flag('PAY_SANDBOX');
  if (sandbox) collectors.sandbox = new SandboxCollector();
  return {
    cfg: {
      sandbox,
      wallet: flag('PAY_WALLET_ENABLED') || sandbox,
      mpesa: !!collectors.mpesa,
      momo: !!collectors.mtn_momo,
      flutterwave: !!collectors.flutterwave,
      paystack: !!collectors.paystack,
    },
    collectors,
  };
}
