/**
 * Creator payouts: the rules, with no I/O so they can be unit tested.
 *
 * Money model
 *   - Coins are bought with Google Play and are platform credit. They are
 *     never withdrawable.
 *   - Diamonds are what a creator earns from gifts (`wallets/{uid}`):
 *       pendingCoins    held for HOLD_DAYS (refunds / chargebacks window)
 *       availableCoins  withdrawable
 *       lockedCoins     inside a withdrawal that is not finished yet
 *     1 Diamond = DIAMOND_USD.
 *
 * Withdrawal states: pending → processing → paid
 *                    pending → cancelled (by the creator) | failed (rejected)
 *                    processing → failed (provider said no; Diamonds go back)
 */

export const DIAMOND_USD = 0.01;
export const HOLD_DAYS = 7;
/** One Diamond; the real floor is 1 unit of the payout currency after fees (see requestWithdrawal). */
export const MIN_WITHDRAW_USD = 0.01;
export const MAX_WITHDRAW_USD = 2000;
export const MAX_REQUESTS_PER_DAY = 3;

export type Rail = 'mobile_money' | 'bank';
export type Provider = 'flutterwave' | 'paystack';
export type WithdrawalStatus = 'pending' | 'processing' | 'paid' | 'failed' | 'cancelled';

const NEXT: Record<WithdrawalStatus, WithdrawalStatus[]> = {
  pending: ['processing', 'cancelled', 'failed'],
  processing: ['paid', 'failed'],
  paid: [],
  failed: [],
  cancelled: [],
};

export function canMove(from: WithdrawalStatus, to: WithdrawalStatus): boolean {
  return NEXT[from]?.includes(to) ?? false;
}

export const isFinal = (s: WithdrawalStatus) => NEXT[s]?.length === 0;

export interface MomoNetwork {
  id: string;
  label: string;
  /** Flutterwave `account_bank` for this network. */
  flw: string;
  /** Paystack `bank_code` for a mobile_money recipient, when Paystack supports it. */
  paystack?: string;
}

export interface AfricaCountry {
  name: string;
  currency: string;
  dial: string;
  networks: MomoNetwork[];
  /** Bank transfers through Flutterwave / Paystack. */
  bank: boolean;
  paystack?: boolean;
}

/**
 * African countries we pay out to locally. Network codes follow the
 * Flutterwave and Paystack transfer docs; check them against your dashboard
 * before going live in a new country.
 */
export const AFRICA: Record<string, AfricaCountry> = {
  KE: { name: 'Kenya', currency: 'KES', dial: '254', bank: true, paystack: true, networks: [
    { id: 'MPESA', label: 'M-Pesa', flw: 'MPS', paystack: 'MPESA' },
    { id: 'AIRTEL', label: 'Airtel Money', flw: 'MPX' },
  ] },
  GH: { name: 'Ghana', currency: 'GHS', dial: '233', bank: true, paystack: true, networks: [
    { id: 'MTN', label: 'MTN MoMo', flw: 'MTN', paystack: 'MTN' },
    { id: 'TELECEL', label: 'Telecel Cash', flw: 'VODAFONE', paystack: 'VOD' },
    { id: 'AIRTELTIGO', label: 'AirtelTigo Money', flw: 'TIGO', paystack: 'ATL' },
  ] },
  UG: { name: 'Uganda', currency: 'UGX', dial: '256', bank: true, networks: [
    { id: 'MTN', label: 'MTN MoMo', flw: 'MPS' },
    { id: 'AIRTEL', label: 'Airtel Money', flw: 'MPS' },
  ] },
  TZ: { name: 'Tanzania', currency: 'TZS', dial: '255', bank: true, networks: [
    { id: 'MPESA', label: 'M-Pesa', flw: 'MPS' },
    { id: 'AIRTEL', label: 'Airtel Money', flw: 'MPS' },
    { id: 'TIGO', label: 'Mixx by Yas', flw: 'MPS' },
  ] },
  RW: { name: 'Rwanda', currency: 'RWF', dial: '250', bank: true, networks: [
    { id: 'MTN', label: 'MTN MoMo', flw: 'MPS' },
    { id: 'AIRTEL', label: 'Airtel Money', flw: 'MPS' },
  ] },
  ZM: { name: 'Zambia', currency: 'ZMW', dial: '260', bank: true, networks: [
    { id: 'MTN', label: 'MTN MoMo', flw: 'MPS' },
    { id: 'AIRTEL', label: 'Airtel Money', flw: 'MPS' },
  ] },
  MW: { name: 'Malawi', currency: 'MWK', dial: '265', bank: true, networks: [
    { id: 'AIRTEL', label: 'Airtel Money', flw: 'MPS' },
    { id: 'TNM', label: 'TNM Mpamba', flw: 'MPS' },
  ] },
  CM: { name: 'Cameroon', currency: 'XAF', dial: '237', bank: false, networks: [
    { id: 'MTN', label: 'MTN MoMo', flw: 'FMM' },
    { id: 'ORANGE', label: 'Orange Money', flw: 'FMM' },
  ] },
  SN: { name: 'Senegal', currency: 'XOF', dial: '221', bank: false, networks: [
    { id: 'ORANGE', label: 'Orange Money', flw: 'FMM' },
    { id: 'WAVE', label: 'Wave', flw: 'FMM' },
    { id: 'FREE', label: 'Free Money', flw: 'FMM' },
  ] },
  CI: { name: "Côte d'Ivoire", currency: 'XOF', dial: '225', bank: false, networks: [
    { id: 'ORANGE', label: 'Orange Money', flw: 'FMM' },
    { id: 'MTN', label: 'MTN MoMo', flw: 'FMM' },
    { id: 'MOOV', label: 'Moov Money', flw: 'FMM' },
    { id: 'WAVE', label: 'Wave', flw: 'FMM' },
  ] },
  BJ: { name: 'Benin', currency: 'XOF', dial: '229', bank: false, networks: [
    { id: 'MTN', label: 'MTN MoMo', flw: 'FMM' },
    { id: 'MOOV', label: 'Moov Money', flw: 'FMM' },
  ] },
  BF: { name: 'Burkina Faso', currency: 'XOF', dial: '226', bank: false, networks: [
    { id: 'ORANGE', label: 'Orange Money', flw: 'FMM' },
    { id: 'MOOV', label: 'Moov Money', flw: 'FMM' },
  ] },
  NG: { name: 'Nigeria', currency: 'NGN', dial: '234', bank: true, paystack: true, networks: [] },
  ZA: { name: 'South Africa', currency: 'ZAR', dial: '27', bank: true, paystack: true, networks: [] },
  EG: { name: 'Egypt', currency: 'EGP', dial: '20', bank: true, networks: [] },
  ET: { name: 'Ethiopia', currency: 'ETB', dial: '251', bank: true, networks: [] },
};

/** Fee for a payout of [usd] on [rail], in USD (2 dp). */
export function payoutFeeUsd(rail: Rail, usd: number): number {
  const fee = rail === 'mobile_money' ? Math.max(0.2, usd * 0.015) : Math.max(0.5, usd * 0.01);
  return Math.round(fee * 100) / 100;
}

export const diamondsToUsd = (diamonds: number) => Math.floor(diamonds) * DIAMOND_USD;
export const usdToDiamonds = (usd: number) => Math.round(usd / DIAMOND_USD);

/** Rounds a local-currency amount the way providers expect it. */
export function roundLocal(amount: number, currency: string): number {
  const whole = ['UGX', 'TZS', 'RWF', 'XAF', 'XOF', 'MWK', 'NGN', 'KES', 'JPY', 'KRW'];
  return whole.includes(currency) ? Math.floor(amount) : Math.floor(amount * 100) / 100;
}

export interface RailOption {
  rail: Rail;
  provider: Provider;
  label: string;
  networks?: { id: string; label: string }[];
}

/** Payout rails for a country, given which providers are configured. */
export function railsFor(country: string, configured: { flutterwave: boolean; paystack: boolean }): RailOption[] {
  const a = AFRICA[country];
  if (!a) return [];
  const out: RailOption[] = [];
  const africaProvider: Provider | null = configured.flutterwave ? 'flutterwave' : configured.paystack && a.paystack ? 'paystack' : null;
  if (africaProvider) {
    const nets = africaProvider === 'paystack' ? a.networks.filter((n) => n.paystack) : a.networks;
    if (nets.length) out.push({ rail: 'mobile_money', provider: africaProvider, label: 'Mobile money', networks: nets.map((n) => ({ id: n.id, label: n.label })) });
    if (a.bank) out.push({ rail: 'bank', provider: africaProvider, label: 'Bank account' });
  }
  return out;
}

/** Strips a phone number to digits and adds the country's dial code. */
export function normalizeMsisdn(raw: string, country: string): string | null {
  const a = AFRICA[country];
  let d = String(raw ?? '').replace(/[^0-9]/g, '');
  if (!a || d.length < 7) return null;
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith(a.dial)) return d.length >= a.dial.length + 7 && d.length <= a.dial.length + 10 ? d : null;
  if (d.startsWith('0')) d = d.slice(1);
  const full = a.dial + d;
  return d.length >= 7 && d.length <= 10 ? full : null;
}

export interface FraudInput {
  amountUsd: number;
  accountAgeDays: number;
  deviceAgeHours: number | null;
  /** Paid withdrawals before this one. */
  paidBefore: number;
  kycCountry: string | null;
  locationCountry: string | null;
  payoutCountry: string;
}

/**
 * Reasons this withdrawal should wait for a person to look at it.
 * Empty means it can go straight to the provider.
 */
export function fraudReasons(f: FraudInput): string[] {
  const r: string[] = [];
  if (f.accountAgeDays < 7) r.push('new_account');
  if (f.deviceAgeHours !== null && f.deviceAgeHours < 72 && f.paidBefore > 0) r.push('new_device');
  if (f.kycCountry && f.kycCountry !== f.payoutCountry) r.push('id_country_mismatch');
  if (f.locationCountry && f.locationCountry !== f.payoutCountry) r.push('location_mismatch');
  if (f.paidBefore === 0 && f.amountUsd > 500) r.push('large_first_withdrawal');
  return r;
}

const AFRICA_EXTRA = new Set(['DZ', 'AO', 'BW', 'BI', 'CV', 'CF', 'TD', 'KM', 'CD', 'CG', 'DJ', 'GQ', 'ER', 'SZ', 'GA', 'GM', 'GN', 'GW', 'LS', 'LR', 'LY', 'MG', 'ML', 'MR', 'MU', 'MA', 'MZ', 'NA', 'NE', 'ST', 'SC', 'SL', 'SO', 'SS', 'SD', 'TG', 'TN', 'ZW']);
export const isAfrica = (c: string) => c in AFRICA || AFRICA_EXTRA.has(c);
