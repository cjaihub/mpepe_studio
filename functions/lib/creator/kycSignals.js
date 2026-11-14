"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanCountrySignals = cleanCountrySignals;
exports.countryMismatch = countryMismatch;
/**
 * Country signals the app sends with KYC (see lib/shared/location/country_detector.dart):
 * where the phone is (GPS through the phone's own geocoder), its mobile network,
 * SIM, phone number and region. Reviewers see them next to the country on the
 * ID; a mismatch is a hint for review, never an automatic rejection (people
 * live abroad).
 */
const KEYS = ['location', 'network', 'sim', 'phone', 'region'];
function cleanCountrySignals(v) {
    const out = {};
    if (!v || typeof v !== 'object' || Array.isArray(v))
        return out;
    const o = v;
    for (const k of KEYS) {
        const c = o[k];
        if (typeof c === 'string' && /^[A-Za-z]{2}$/.test(c))
            out[k] = c.toUpperCase();
    }
    return out;
}
/** True when the strongest "where you are" signal differs from the ID country. */
function countryMismatch(declared, s) {
    var _a, _b;
    const where = (_b = (_a = s.location) !== null && _a !== void 0 ? _a : s.network) !== null && _b !== void 0 ? _b : s.sim;
    return !!where && where !== declared;
}
//# sourceMappingURL=kycSignals.js.map