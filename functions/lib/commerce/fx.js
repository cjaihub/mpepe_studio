"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.fxRefresh = void 0;
exports.refreshRates = refreshRates;
exports.storedUsdRate = storedUsdRate;
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
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const SOURCE = 'https://open.er-api.com/v6/latest/USD';
async function refreshRates() {
    var _a;
    const res = (await fetch(SOURCE, { signal: AbortSignal.timeout(20000) }).then((r) => r.json()));
    if ((res === null || res === void 0 ? void 0 : res.result) !== 'success' || !res.rates || typeof res.rates !== 'object')
        throw new Error('rates source answered without rates');
    const rates = {};
    for (const [code, value] of Object.entries(res.rates)) {
        if (/^[A-Z]{3}$/.test(code) && typeof value === 'number' && Number.isFinite(value) && value > 0)
            rates[code] = value;
    }
    if (Object.keys(rates).length < 100)
        throw new Error('rates source answered with too few currencies');
    await (0, firestore_1.getFirestore)().doc('fx_rates/USD').set({
        rates,
        fetchedAt: firestore_1.FieldValue.serverTimestamp(),
        sourceUpdatedAt: Number((_a = res.time_last_update_unix) !== null && _a !== void 0 ? _a : 0) * 1000 || null,
        source: 'open.er-api.com',
    });
    return Object.keys(rates).length;
}
exports.fxRefresh = (0, scheduler_1.onSchedule)({ schedule: 'every 60 minutes', timeoutSeconds: 60 }, async () => {
    var _a;
    try {
        logger.info('fx rates refreshed', await refreshRates());
    }
    catch (e) {
        // The last good rates stay in place.
        logger.warn('fx refresh failed', (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e);
    }
});
/** Units of [currency] per 1 USD from the stored rates, or null. */
async function storedUsdRate(currency) {
    var _a;
    if (currency === 'USD')
        return 1;
    const r = (_a = (await (0, firestore_1.getFirestore)().doc('fx_rates/USD').get()).get('rates')) === null || _a === void 0 ? void 0 : _a[currency];
    return typeof r === 'number' && Number.isFinite(r) && r > 0 ? r : null;
}
//# sourceMappingURL=fx.js.map