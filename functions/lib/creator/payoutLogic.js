"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.isAfrica = exports.usdToDiamonds = exports.diamondsToUsd = exports.AFRICA = exports.isFinal = exports.MAX_REQUESTS_PER_DAY = exports.MAX_WITHDRAW_USD = exports.MIN_WITHDRAW_USD = exports.HOLD_DAYS = exports.DIAMOND_USD = void 0;
exports.canMove = canMove;
exports.payoutFeeUsd = payoutFeeUsd;
exports.roundLocal = roundLocal;
exports.railsFor = railsFor;
exports.normalizeMsisdn = normalizeMsisdn;
exports.fraudReasons = fraudReasons;
exports.DIAMOND_USD = 0.01;
exports.HOLD_DAYS = 7;
/** One Diamond; the real floor is 1 unit of the payout currency after fees (see requestWithdrawal). */
exports.MIN_WITHDRAW_USD = 0.01;
exports.MAX_WITHDRAW_USD = 2000;
exports.MAX_REQUESTS_PER_DAY = 3;
const NEXT = {
    pending: ['processing', 'cancelled', 'failed'],
    processing: ['paid', 'failed'],
    paid: [],
    failed: [],
    cancelled: [],
};
function canMove(from, to) {
    var _a;
    var _b;
    return (_b = (_a = NEXT[from]) === null || _a === void 0 ? void 0 : _a.includes(to)) !== null && _b !== void 0 ? _b : false;
}
const isFinal = (s) => { var _a; return ((_a = NEXT[s]) === null || _a === void 0 ? void 0 : _a.length) === 0; };
exports.isFinal = isFinal;
/**
 * African countries we pay out to locally. Network codes follow the
 * Flutterwave and Paystack transfer docs; check them against your dashboard
 * before going live in a new country.
 */
exports.AFRICA = {
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
function payoutFeeUsd(rail, usd) {
    const fee = rail === 'mobile_money' ? Math.max(0.2, usd * 0.015) : Math.max(0.5, usd * 0.01);
    return Math.round(fee * 100) / 100;
}
const diamondsToUsd = (diamonds) => Math.floor(diamonds) * exports.DIAMOND_USD;
exports.diamondsToUsd = diamondsToUsd;
const usdToDiamonds = (usd) => Math.round(usd / exports.DIAMOND_USD);
exports.usdToDiamonds = usdToDiamonds;
/** Rounds a local-currency amount the way providers expect it. */
function roundLocal(amount, currency) {
    const whole = ['UGX', 'TZS', 'RWF', 'XAF', 'XOF', 'MWK', 'NGN', 'KES', 'JPY', 'KRW'];
    return whole.includes(currency) ? Math.floor(amount) : Math.floor(amount * 100) / 100;
}
/** Payout rails for a country, given which providers are configured. */
function railsFor(country, configured) {
    const a = exports.AFRICA[country];
    if (!a)
        return [];
    const out = [];
    const africaProvider = configured.flutterwave ? 'flutterwave' : configured.paystack && a.paystack ? 'paystack' : null;
    if (africaProvider) {
        const nets = africaProvider === 'paystack' ? a.networks.filter((n) => n.paystack) : a.networks;
        if (nets.length)
            out.push({ rail: 'mobile_money', provider: africaProvider, label: 'Mobile money', networks: nets.map((n) => ({ id: n.id, label: n.label })) });
        if (a.bank)
            out.push({ rail: 'bank', provider: africaProvider, label: 'Bank account' });
    }
    return out;
}
/** Strips a phone number to digits and adds the country's dial code. */
function normalizeMsisdn(raw, country) {
    const a = exports.AFRICA[country];
    let d = String(raw !== null && raw !== void 0 ? raw : '').replace(/[^0-9]/g, '');
    if (!a || d.length < 7)
        return null;
    if (d.startsWith('00'))
        d = d.slice(2);
    if (d.startsWith(a.dial))
        return d.length >= a.dial.length + 7 && d.length <= a.dial.length + 10 ? d : null;
    if (d.startsWith('0'))
        d = d.slice(1);
    const full = a.dial + d;
    return d.length >= 7 && d.length <= 10 ? full : null;
}
/**
 * Reasons this withdrawal should wait for a person to look at it.
 * Empty means it can go straight to the provider.
 */
function fraudReasons(f) {
    const r = [];
    if (f.accountAgeDays < 7)
        r.push('new_account');
    if (f.deviceAgeHours !== null && f.deviceAgeHours < 72 && f.paidBefore > 0)
        r.push('new_device');
    if (f.kycCountry && f.kycCountry !== f.payoutCountry)
        r.push('id_country_mismatch');
    if (f.locationCountry && f.locationCountry !== f.payoutCountry)
        r.push('location_mismatch');
    if (f.paidBefore === 0 && f.amountUsd > 500)
        r.push('large_first_withdrawal');
    return r;
}
const AFRICA_EXTRA = new Set(['DZ', 'AO', 'BW', 'BI', 'CV', 'CF', 'TD', 'KM', 'CD', 'CG', 'DJ', 'GQ', 'ER', 'SZ', 'GA', 'GM', 'GN', 'GW', 'LS', 'LR', 'LY', 'MG', 'ML', 'MR', 'MU', 'MA', 'MZ', 'NA', 'NE', 'ST', 'SC', 'SL', 'SO', 'SS', 'SD', 'TG', 'TN', 'ZW']);
const isAfrica = (c) => c in exports.AFRICA || AFRICA_EXTRA.has(c);
exports.isAfrica = isAfrica;
//# sourceMappingURL=payoutLogic.js.map