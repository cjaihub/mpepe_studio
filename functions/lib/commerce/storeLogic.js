"use strict";
/**
 * Store rules with no I/O (unit tested): buyer customizations of a product
 * and seller discount codes. Checkout calls these so the price a buyer pays
 * is always computed on the server.
 *
 * Product `customization` (written by the seller):
 *   [{ id, label, type: 'choice' | 'text', required?, maxLength?, priceDelta?,
 *      choices?: [{ id, label, priceDelta?, colorHex?, modelVariant? }] }]
 * Buyer selection (sent to checkout): { [optionId]: choiceId | text }
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.FULFILMENT = exports.normalizeCode = exports.customizationExtra = exports.StoreRuleError = void 0;
exports.priceCustomization = priceCustomization;
exports.codeDiscount = codeDiscount;
exports.canFulfil = canFulfil;
exports.nextRating = nextRating;
class StoreRuleError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
}
exports.StoreRuleError = StoreRuleError;
const MAX_OPTIONS = 12;
const MAX_TEXT = 60;
/** Validates a buyer's selection against the product and returns the priced lines. */
function priceCustomization(product, raw) {
    var _a, _b, _c;
    const options = Array.isArray(product.customization) ? product.customization.slice(0, MAX_OPTIONS) : [];
    const sel = raw && typeof raw === 'object' ? raw : {};
    const out = [];
    for (const o of options) {
        if (!o || typeof o !== 'object')
            continue;
        const id = String((_a = o.id) !== null && _a !== void 0 ? _a : '');
        const label = String((_b = o.label) !== null && _b !== void 0 ? _b : 'Option').slice(0, 60);
        const type = o.type === 'text' ? 'text' : 'choice';
        const required = o.required === true;
        const value = sel[id];
        if (value == null || value === '') {
            if (required)
                throw new StoreRuleError('invalid-argument', `Choose ${label.toLowerCase()}.`);
            continue;
        }
        if (type === 'text') {
            const max = Math.min(Number(o.maxLength) || MAX_TEXT, MAX_TEXT);
            const text = String(value).trim();
            if (!text)
                continue;
            if (text.length > max)
                throw new StoreRuleError('invalid-argument', `${label} can be up to ${max} characters.`);
            out.push({ optionId: id, label, value: text, priceDelta: money(o.priceDelta) });
            continue;
        }
        const choices = Array.isArray(o.choices) ? o.choices : [];
        const c = choices.find((x) => x && String(x.id) === String(value));
        if (!c)
            throw new StoreRuleError('invalid-argument', `That ${label.toLowerCase()} is not available.`);
        out.push(Object.assign({ optionId: id, label, value: String((_c = c.label) !== null && _c !== void 0 ? _c : c.id).slice(0, 60), priceDelta: money(c.priceDelta) }, (typeof c.modelVariant === 'string' && c.modelVariant ? { modelVariant: c.modelVariant } : {})));
    }
    return out;
}
const money = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? Math.min(n, 1000000) : 0;
};
const customizationExtra = (lines) => lines.reduce((s, l) => s + l.priceDelta, 0);
exports.customizationExtra = customizationExtra;
/** Discount for [itemsAmount] with a seller code, or an error the buyer can read. */
function codeDiscount(code, itemsAmount, currency, nowMs) {
    var _a, _b, _c;
    if (!code || code.active === false)
        throw new StoreRuleError('failed-precondition', 'That code isn’t valid.');
    if (code.endsAtMs != null && code.endsAtMs <= nowMs)
        throw new StoreRuleError('failed-precondition', 'That code has expired.');
    if (code.maxUses != null && ((_a = code.uses) !== null && _a !== void 0 ? _a : 0) >= code.maxUses)
        throw new StoreRuleError('failed-precondition', 'That code has been used up.');
    if (code.minSpend != null && itemsAmount < code.minSpend) {
        throw new StoreRuleError('failed-precondition', `Spend at least ${code.minSpend} to use this code.`);
    }
    let off = 0;
    const pct = Number((_b = code.percentOff) !== null && _b !== void 0 ? _b : 0);
    if (pct > 0)
        off = itemsAmount * Math.min(pct, 90) / 100;
    else if (Number((_c = code.amountOff) !== null && _c !== void 0 ? _c : 0) > 0) {
        if (code.currency && code.currency.toUpperCase() !== currency.toUpperCase()) {
            throw new StoreRuleError('failed-precondition', 'That code is for another currency.');
        }
        off = Number(code.amountOff);
    }
    return Math.max(0, Math.min(off, itemsAmount));
}
/** Codes are stored upper-case, letters and digits only. */
const normalizeCode = (raw) => String(raw !== null && raw !== void 0 ? raw : '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 20);
exports.normalizeCode = normalizeCode;
/** Seller fulfilment steps on top of the escrow status. */
exports.FULFILMENT = ['new', 'packed', 'ready', 'shipped'];
function canFulfil(from, to) {
    const a = exports.FULFILMENT.indexOf((from !== null && from !== void 0 ? from : 'new'));
    const b = exports.FULFILMENT.indexOf(to);
    return a >= 0 && b === a + 1;
}
/** Running average after one more rating. */
function nextRating(avg, count, stars) {
    const n = Math.max(0, Number(count) || 0);
    const a = Number(avg) || 0;
    const s = Math.min(5, Math.max(1, Math.round(stars)));
    return { rating: Math.round(((a * n + s) / (n + 1)) * 100) / 100, reviewCount: n + 1 };
}
//# sourceMappingURL=storeLogic.js.map