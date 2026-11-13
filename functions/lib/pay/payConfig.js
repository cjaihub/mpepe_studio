"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.returnUrl = exports.functionUrl = void 0;
exports.payRuntime = payRuntime;
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
const optionalSecrets_1 = require("../optionalSecrets");
const collectAdapters_1 = require("../payments/collectAdapters");
const payoutLogic_1 = require("../creator/payoutLogic");
const REGION = 'us-central1';
function projectId() {
    var _a, _b;
    if (process.env.GCLOUD_PROJECT)
        return process.env.GCLOUD_PROJECT;
    try {
        return (_b = JSON.parse((_a = process.env.FIREBASE_CONFIG) !== null && _a !== void 0 ? _a : '{}').projectId) !== null && _b !== void 0 ? _b : '';
    }
    catch (_c) {
        return '';
    }
}
/** Public URL of an HTTP function in this project (partner callbacks). */
const functionUrl = (name) => `https://${REGION}-${projectId()}.cloudfunctions.net/${name}`;
exports.functionUrl = functionUrl;
/** Where a partner's secure page sends the payer back (our payReturn page by default). */
const returnUrl = () => { var _a; return ((_a = process.env.PAY_RETURN_URL) !== null && _a !== void 0 ? _a : '').trim() || (0, exports.functionUrl)('payReturn'); };
exports.returnUrl = returnUrl;
const flag = (name) => { var _a; return ((_a = process.env[name]) !== null && _a !== void 0 ? _a : '').trim().toLowerCase() === 'true'; };
async function payRuntime() {
    var _a;
    const [mk, ms, sc, pk, msub, muser, mkey, flw, ps] = await Promise.all([
        (0, optionalSecrets_1.optionalSecret)('MPESA_CONSUMER_KEY'), (0, optionalSecrets_1.optionalSecret)('MPESA_CONSUMER_SECRET'), (0, optionalSecrets_1.optionalSecret)('MPESA_SHORTCODE'), (0, optionalSecrets_1.optionalSecret)('MPESA_PASSKEY'),
        (0, optionalSecrets_1.optionalSecret)('MTN_MOMO_SUBSCRIPTION_KEY'), (0, optionalSecrets_1.optionalSecret)('MTN_MOMO_API_USER'), (0, optionalSecrets_1.optionalSecret)('MTN_MOMO_API_KEY'),
        (0, optionalSecrets_1.optionalSecret)('FLUTTERWAVE_SECRET_KEY'), (0, optionalSecrets_1.optionalSecret)('PAYSTACK_SECRET_KEY'),
    ]);
    const f = fetch;
    const collectors = {};
    if (mk && ms && sc && pk) {
        collectors.mpesa = new collectAdapters_1.MpesaCollector({
            consumerKey: mk, consumerSecret: ms, shortcode: sc, passkey: pk,
            env: process.env.MPESA_ENV === 'production' ? 'production' : 'sandbox',
            callbackUrl: (0, exports.functionUrl)('payWebhookMpesa'),
        }, f);
    }
    if (msub && muser && mkey) {
        collectors.mtn_momo = new collectAdapters_1.MomoCollector({
            subscriptionKey: msub, apiUser: muser, apiKey: mkey,
            env: ((_a = process.env.MTN_MOMO_ENV) !== null && _a !== void 0 ? _a : 'sandbox').trim() || 'sandbox',
            callbackUrl: (0, exports.functionUrl)('payWebhookMomo'),
        }, f);
    }
    if (flw)
        collectors.flutterwave = new collectAdapters_1.FlutterwaveCollector(flw, f, Object.keys(payoutLogic_1.AFRICA));
    if (ps)
        collectors.paystack = new collectAdapters_1.PaystackCollector(ps, f);
    const sandbox = flag('PAY_SANDBOX');
    if (sandbox)
        collectors.sandbox = new collectAdapters_1.SandboxCollector();
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
//# sourceMappingURL=payConfig.js.map