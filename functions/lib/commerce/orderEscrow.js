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
exports.cancelOrder = exports.confirmDelivery = exports.startJourney = exports.acceptDelivery = exports.createOrderCheckout = exports.quoteDelivery = exports.payPayoutStatus = exports.orderCurrency = void 0;
exports.orderMinor = orderMinor;
exports.liveDealFor = liveDealFor;
exports.dealPrice = dealPrice;
exports.payoutReady = payoutReady;
exports.applyOrderPaid = applyOrderPaid;
/**
 * Oneova Biz orders on Oneova Pay, with escrow until the buyer has the goods.
 *
 *   buyer           → quoteDelivery: live route price (Directions API)
 *                   → createOrderCheckout: the order, priced here
 *                   → payCreate (pay/intents.ts): pays it (phone prompt,
 *                     partner page or Oneova balance)
 *   Oneova Pay      → applyOrderPaid: order "paid", money held in
 *                     `escrow:{orderId}` on the ledger
 *   rider           → acceptDelivery / startJourney
 *   buyer           → confirmDelivery(code): escrow released on the ledger —
 *                     items − commission → seller balance, delivery fee →
 *                     rider balance, commission → platform
 *   buyer / seller  → cancelOrder before pickup → refund
 *
 * Sellers and riders withdraw their balance with payWithdraw
 * (pay/balancePayouts.ts) to their verified payout method.
 *
 * Money never moves on the client's word: amounts are computed here from the
 * product docs and the stored quote, and only a confirmed pay-in marks an
 * order paid.
 *
 * Secrets: GOOGLE_MAPS_SERVER_KEY. Param: COMMERCE_COMMISSION_PERCENT (default 10).
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const optionalSecrets_1 = require("../optionalSecrets");
const variant_logic_1 = require("./variant_logic");
const storeLogic_1 = require("./storeLogic");
const provider_1 = require("../payments/provider");
const payLogic_1 = require("../pay/payLogic");
const ledger_1 = require("../pay/ledger");
const payConfig_1 = require("../pay/payConfig");
const fx_1 = require("./fx");
const shareLinks_1 = require("./shareLinks");
const shareLogic_1 = require("./shareLogic");
const db = () => (0, firestore_1.getFirestore)();
/**
 * Motorbike delivery rates per currency: base + per km + per minute.
 * Rush hours (07–09, 17–20 UTC) add 20%.
 */
const RATES = {
    USD: { base: 1.5, perKm: 0.6, perMin: 0.05, min: 2.5 },
    EUR: { base: 1.4, perKm: 0.55, perMin: 0.05, min: 2.3 },
    GBP: { base: 1.2, perKm: 0.5, perMin: 0.04, min: 2.0 },
    ZAR: { base: 20, perKm: 7, perMin: 0.6, min: 35 },
    KES: { base: 100, perKm: 40, perMin: 3, min: 150 },
    NGN: { base: 800, perKm: 250, perMin: 20, min: 1200 },
    GHS: { base: 10, perKm: 4, perMin: 0.3, min: 15 },
    TZS: { base: 1500, perKm: 600, perMin: 40, min: 2500 },
    UGX: { base: 3000, perKm: 1200, perMin: 80, min: 5000 },
    RWF: { base: 800, perKm: 300, perMin: 20, min: 1200 },
};
function uid(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
function num(v) {
    const n = typeof v === 'number' ? v : Number(v);
    return Number.isFinite(n) ? n : null;
}
const commissionPercent = () => {
    var _a;
    const p = Number((_a = process.env.COMMERCE_COMMISSION_PERCENT) !== null && _a !== void 0 ? _a : 10);
    return Number.isFinite(p) && p >= 0 && p <= 50 ? p : 10;
};
/** Order currency as ISO upper case (older orders stored it lower case). */
const orderCurrency = (o) => String(o.currency || 'USD').toUpperCase();
exports.orderCurrency = orderCurrency;
/** Order totals in minor units (older orders only had decimal amounts). */
function orderMinor(o) {
    const cur = (0, exports.orderCurrency)(o);
    const items = Number.isSafeInteger(o.itemsMinor) ? Number(o.itemsMinor) : (0, provider_1.toMinor)(Number(o.itemsAmount) || 0, cur);
    const delivery = Number.isSafeInteger(o.deliveryMinor) ? Number(o.deliveryMinor) : (0, provider_1.toMinor)(Number(o.deliveryFee) || 0, cur);
    return { currency: cur, items, delivery, total: items + delivery };
}
/** A product's currency; one saved without one uses the seller's local currency. */
async function productCurrency(product, sellerId) {
    var _a;
    const c = String((_a = product.currency) !== null && _a !== void 0 ? _a : '').trim();
    if (/^[A-Za-z]{3}$/.test(c))
        return c.toUpperCase();
    const { countryOf } = await Promise.resolve().then(() => __importStar(require('../pay/intents')));
    return (0, payLogic_1.currencyFor)(await countryOf(sellerId));
}
/**
 * The seller's live deal (`biz_shops/{uid}.liveDeal`) when it is running now
 * and covers [productId] (empty productIds = the whole shop).
 */
function liveDealFor(raw, productId, nowMs) {
    if (!raw || typeof raw !== 'object')
        return null;
    const d = raw;
    const pct = typeof d.percentOff === 'number' ? Math.floor(d.percentOff) : 0;
    const ends = d.endsAt;
    const endsMs = typeof (ends === null || ends === void 0 ? void 0 : ends.toMillis) === 'function' ? ends.toMillis() : 0;
    if (pct < 1 || pct > 80 || endsMs <= nowMs)
        return null;
    const ids = Array.isArray(d.productIds) ? d.productIds.filter((x) => typeof x === 'string') : [];
    if (ids.length && !ids.includes(productId))
        return null;
    return { title: typeof d.title === 'string' && d.title.trim() ? d.title.trim().slice(0, 80) : 'Live deal', percentOff: pct };
}
/** Deal price: price × (100 − percent) / 100, to the currency's smallest unit (2 dp, whole for UGX/XOF…). */
function dealPrice(price, percentOff, currency) {
    const e = (0, provider_1.exponent)(currency);
    const f = 10 ** e;
    return Math.round((price * (100 - percentOff) / 100) * f) / f;
}
// ───────────────────────────── Payout readiness ─────────────────────────────
/** A seller or rider can be paid: verified identity and a saved payout method. */
async function payoutReady(who) {
    var _a;
    const [kyc, methods] = await Promise.all([
        db().doc(`kyc/${who}`).get(),
        db().collection(`payout_methods/${who}/methods`).limit(5).get(),
    ]);
    const kycStatus = String((_a = kyc.get('status')) !== null && _a !== void 0 ? _a : 'none');
    const ready = kycStatus === 'verified' && methods.size > 0;
    return { kycStatus, methods: methods.size, ready };
}
/** Readiness + balances for the payouts screen. */
exports.payPayoutStatus = (0, https_1.onCall)(async (req) => {
    var _a;
    const me = uid(req);
    const [r, bal] = await Promise.all([payoutReady(me), (0, ledger_1.balanceRef)(me).get()]);
    const balances = {};
    for (const [k, v] of Object.entries((_a = bal.data()) !== null && _a !== void 0 ? _a : {})) {
        if (!/^[A-Z]{3}$/.test(k) || typeof v !== 'object' || v === null)
            continue;
        balances[k] = { available: (0, ledger_1.bucketOf)(bal.data(), k, 'available'), pending: (0, ledger_1.bucketOf)(bal.data(), k, 'pending'), locked: (0, ledger_1.bucketOf)(bal.data(), k, 'locked') };
    }
    return Object.assign(Object.assign({}, r), { payoutsEnabled: r.ready, balances });
});
async function canReceive(who) {
    if ((await payoutReady(who)).ready)
        return true;
    // The sandbox lets test shops sell before their identity check is done.
    return (await (0, payConfig_1.payRuntime)()).cfg.sandbox;
}
function latLng(v) {
    const o = v;
    const lat = num(o === null || o === void 0 ? void 0 : o.lat), lng = num(o === null || o === void 0 ? void 0 : o.lng);
    return lat !== null && lng !== null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : null;
}
async function route(from, to) {
    var _a, _b, _c, _d, _e, _f;
    var _g;
    const key = await (0, optionalSecrets_1.optionalSecret)('GOOGLE_MAPS_SERVER_KEY');
    if (key) {
        const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
        url.searchParams.set('origin', `${from.lat},${from.lng}`);
        url.searchParams.set('destination', `${to.lat},${to.lng}`);
        url.searchParams.set('mode', 'driving');
        url.searchParams.set('avoid', 'highways');
        url.searchParams.set('key', key);
        const res = await fetch(url).then((r) => r.json()).catch(() => null);
        const leg = (_c = (_b = (_a = res === null || res === void 0 ? void 0 : res.routes) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.legs) === null || _c === void 0 ? void 0 : _c[0];
        if ((_d = leg === null || leg === void 0 ? void 0 : leg.distance) === null || _d === void 0 ? void 0 : _d.value) {
            return { km: leg.distance.value / 1000, min: ((_g = (_e = leg.duration) === null || _e === void 0 ? void 0 : _e.value) !== null && _g !== void 0 ? _g : 0) / 60, polyline: (_f = res.routes[0].overview_polyline) === null || _f === void 0 ? void 0 : _f.points };
        }
    }
    // No route service: straight-line distance × 1.3 for streets, at 25 km/h.
    const R = 6371, dLat = (to.lat - from.lat) * Math.PI / 180, dLng = (to.lng - from.lng) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(from.lat * Math.PI / 180) * Math.cos(to.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
    const km = 2 * R * Math.asin(Math.sqrt(a)) * 1.3;
    return { km, min: km / 25 * 60 };
}
async function deliveryFee(km, min, currency) {
    // Currencies without their own table use the USD rates converted at today's rate.
    const local = RATES[currency];
    const fx = local ? 1 : await (0, fx_1.storedUsdRate)(currency);
    if (!fx)
        throw new https_1.HttpsError('unavailable', 'Delivery prices for this currency are not available right now. Try again in a minute.');
    const r = local !== null && local !== void 0 ? local : RATES.USD;
    const hour = new Date().getUTCHours();
    const rush = (hour >= 7 && hour < 9) || (hour >= 17 && hour < 20) ? 1.2 : 1;
    const fee = Math.max(r.min, (r.base + r.perKm * km + r.perMin * min) * rush) * fx;
    const e = (0, provider_1.exponent)(currency);
    return e === 0 ? Math.round(fee) : Math.round(fee * 10 ** e) / 10 ** e;
}
async function pickupFor(sellerId) {
    var _a, _b;
    const shop = (await db().collection('biz_shops').doc(sellerId).get()).data();
    const user = shop ? null : (await db().collection('users').doc(sellerId).get()).data();
    return (_b = (_a = latLng(shop === null || shop === void 0 ? void 0 : shop.location)) !== null && _a !== void 0 ? _a : latLng(user === null || user === void 0 ? void 0 : user.shopLocation)) !== null && _b !== void 0 ? _b : latLng(user === null || user === void 0 ? void 0 : user.geo);
}
/** Live delivery price for a product to the buyer's location. Valid for 15 minutes. */
exports.quoteDelivery = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c, _d, _e, _f;
    const me = uid(req);
    const productId = String((_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.productId) !== null && _c !== void 0 ? _c : '');
    const dropoff = latLng((_b = req.data) === null || _b === void 0 ? void 0 : _b.dropoff);
    if (!productId || !dropoff)
        throw new https_1.HttpsError('invalid-argument', 'Choose a product and a delivery spot.');
    const product = (await db().collection('products').doc(productId).get()).data();
    if (!product)
        throw new https_1.HttpsError('not-found', 'This product is no longer available.');
    const sellerId = String(product.ownerId || product.userId || product.uid || '');
    const pickup = (_d = latLng(product.location)) !== null && _d !== void 0 ? _d : await pickupFor(sellerId);
    if (!pickup)
        throw new https_1.HttpsError('failed-precondition', 'This shop has not set its pickup location yet.');
    const currency = await productCurrency(product, sellerId);
    const r = await route(pickup, dropoff);
    const fee = await deliveryFee(r.km, r.min, currency);
    const ref = await db().collection('delivery_quotes').add({
        uid: me, productId, sellerId, pickup, dropoff, currency, fee,
        distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: (_e = r.polyline) !== null && _e !== void 0 ? _e : null,
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + 15 * 60000), createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return { quoteId: ref.id, fee, currency, distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: (_f = r.polyline) !== null && _f !== void 0 ? _f : null };
});
// ───────────────────────────── Checkout ─────────────────────────────
/** Creates the priced order. The app then pays it with Oneova Pay (payCreate, purpose "order"). */
exports.createOrderCheckout = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    var _l, _m, _o, _p, _q, _r, _s, _t;
    const me = uid(req);
    const productId = String((_l = (_a = req.data) === null || _a === void 0 ? void 0 : _a.productId) !== null && _l !== void 0 ? _l : '');
    const qty = Math.min(Math.max(Math.floor((_m = num((_b = req.data) === null || _b === void 0 ? void 0 : _b.quantity)) !== null && _m !== void 0 ? _m : 1), 1), 20);
    const quoteId = String((_o = (_c = req.data) === null || _c === void 0 ? void 0 : _c.quoteId) !== null && _o !== void 0 ? _o : '');
    const address = String((_p = (_d = req.data) === null || _d === void 0 ? void 0 : _d.address) !== null && _p !== void 0 ? _p : '').slice(0, 300);
    const product = (await db().collection('products').doc(productId).get()).data();
    if (!product)
        throw new https_1.HttpsError('not-found', 'This product is no longer available.');
    const sellerId = String(product.ownerId || product.userId || product.uid || '');
    if (!sellerId)
        throw new https_1.HttpsError('failed-precondition', 'This product has no seller.');
    if (sellerId === me)
        throw new https_1.HttpsError('failed-precondition', 'You can’t buy your own product.');
    const price = num(product.price);
    if (price === null || price <= 0)
        throw new https_1.HttpsError('failed-precondition', 'This product has no price yet.');
    if (product.inStock === false || (typeof product.stock === 'number' && product.stock < qty)) {
        throw new https_1.HttpsError('failed-precondition', 'Not enough in stock.');
    }
    let variant = null;
    try {
        variant = (0, variant_logic_1.pickVariant)(product, (_e = req.data) === null || _e === void 0 ? void 0 : _e.variantId, qty);
    }
    catch (e) {
        if (e instanceof variant_logic_1.VariantError)
            throw new https_1.HttpsError(e.code, e.message);
        throw e;
    }
    const currency = await productCurrency(product, sellerId);
    // A live deal the seller is running right now lowers the base price;
    // the buyer's customization extras are added on top at full price.
    const deal = liveDealFor((await db().collection('biz_shops').doc(sellerId).get()).get('liveDeal'), productId, Date.now());
    let custom;
    try {
        custom = (0, storeLogic_1.priceCustomization)(product, (_f = req.data) === null || _f === void 0 ? void 0 : _f.customization);
    }
    catch (e) {
        if (e instanceof storeLogic_1.StoreRuleError)
            throw new https_1.HttpsError(e.code, e.message);
        throw e;
    }
    const basePrice = deal ? dealPrice(price, deal.percentOff, currency) : price;
    const unitPrice = basePrice + (0, storeLogic_1.customizationExtra)(custom);
    if (!(await canReceive(sellerId)))
        throw new https_1.HttpsError('failed-precondition', 'This shop can’t take payments yet.');
    let deliveryMinor = 0;
    let quote;
    if (quoteId) {
        quote = (await db().collection('delivery_quotes').doc(quoteId).get()).data();
        if (!quote || quote.uid !== me || quote.productId !== productId)
            throw new https_1.HttpsError('invalid-argument', 'Please refresh the delivery price.');
        if (quote.expiresAt.toMillis() < Date.now())
            throw new https_1.HttpsError('deadline-exceeded', 'The delivery price expired. Please refresh it.');
        deliveryMinor = (0, provider_1.toMinor)(Number(quote.fee), currency);
    }
    const major = (m) => m / 10 ** (0, provider_1.exponent)(currency);
    const grossItemsMinor = (0, provider_1.toMinor)(unitPrice, currency) * qty;
    // Seller discount code on the items part (uses counted when the order is paid).
    let discountCode = null;
    let discountMinor = 0;
    const rawCode = (0, storeLogic_1.normalizeCode)((_g = req.data) === null || _g === void 0 ? void 0 : _g.code);
    if (rawCode) {
        const codeDoc = (await db().doc(`biz_shops/${sellerId}/codes/${rawCode}`).get()).data();
        try {
            const off = (0, storeLogic_1.codeDiscount)(codeDoc ? Object.assign(Object.assign({}, codeDoc), { endsAtMs: (_j = (_h = codeDoc.endsAt) === null || _h === void 0 ? void 0 : _h.toMillis) === null || _j === void 0 ? void 0 : _j.call(_h) }) : null, major(grossItemsMinor), currency, Date.now());
            discountMinor = Math.min((0, provider_1.toMinor)(off, currency), grossItemsMinor);
            discountCode = rawCode;
        }
        catch (e) {
            if (e instanceof storeLogic_1.StoreRuleError)
                throw new https_1.HttpsError(e.code, e.message);
            throw e;
        }
    }
    const itemsMinor = grossItemsMinor - discountMinor;
    const totalMinor = itemsMinor + deliveryMinor;
    // The tracked share link that brought the buyer here, if any.
    const shareCode = (0, shareLogic_1.validShareCode)((_k = req.data) === null || _k === void 0 ? void 0 : _k.shareCode) ? req.data.shareCode : null;
    const orderRef = db().collection('orders').doc();
    await orderRef.set({
        buyerId: me,
        sellerId,
        participants: [me, sellerId],
        productId,
        productName: String(product.name || product.title || 'Item').slice(0, 120),
        imageUrl: typeof product.imageUrl === 'string' ? product.imageUrl : null,
        variantId: (_q = variant === null || variant === void 0 ? void 0 : variant.id) !== null && _q !== void 0 ? _q : null,
        variantName: (_r = variant === null || variant === void 0 ? void 0 : variant.name) !== null && _r !== void 0 ? _r : null,
        quantity: qty,
        currency,
        listPrice: price,
        unitPrice,
        dealPercent: (_s = deal === null || deal === void 0 ? void 0 : deal.percentOff) !== null && _s !== void 0 ? _s : null,
        dealTitle: (_t = deal === null || deal === void 0 ? void 0 : deal.title) !== null && _t !== void 0 ? _t : null,
        customization: custom,
        grossItemsMinor,
        discountCode,
        discountAmount: major(discountMinor),
        discountMinor,
        itemsAmount: major(itemsMinor),
        deliveryFee: major(deliveryMinor),
        totalAmount: major(totalMinor),
        itemsMinor,
        deliveryMinor,
        totalMinor,
        commissionPercent: commissionPercent(),
        delivery: quote ? { pickup: quote.pickup, dropoff: quote.dropoff, address, distanceKm: quote.distanceKm, durationMin: quote.durationMin, polyline: quote.polyline } : null,
        shareCode,
        status: 'awaiting_payment',
        payIntentId: null,
        riderId: null,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await (0, shareLinks_1.countShare)(shareCode, 'checkouts');
    return { orderId: orderRef.id, total: major(totalMinor), totalMinor, currency };
});
/**
 * Writes for a confirmed pay-in on an order (inside the intents transaction,
 * after its reads): stock off the shelf, handover code, delivery job, seller
 * notification. The escrow ledger posting is written by the caller.
 */
function applyOrderPaid(tx, orderId, o, product, intentId) {
    var _a;
    const ref = db().collection('orders').doc(orderId);
    let stockShortfall = false;
    if (product) {
        const s = (0, variant_logic_1.stockAfterSale)(product, (_a = o.variantId) !== null && _a !== void 0 ? _a : null, Number(o.quantity) || 1);
        stockShortfall = s.shortfall;
        if (Object.keys(s.update).length)
            tx.update(db().collection('products').doc(String(o.productId)), Object.assign(Object.assign({}, s.update), { updatedAt: firestore_1.FieldValue.serverTimestamp() }));
    }
    if (typeof o.discountCode === 'string' && o.discountCode) {
        // merge: a code the seller deleted meanwhile must not fail the payment.
        tx.set(db().doc(`biz_shops/${o.sellerId}/codes/${o.discountCode}`), { uses: firestore_1.FieldValue.increment(1) }, { merge: true });
    }
    if ((0, shareLogic_1.validShareCode)(o.shareCode)) {
        tx.set(db().collection('share_links').doc(o.shareCode), {
            purchases: firestore_1.FieldValue.increment(1),
            revenueMinor: { [(0, exports.orderCurrency)(o)]: firestore_1.FieldValue.increment(Number(o.totalMinor) || 0) },
        }, { merge: true });
    }
    tx.update(ref, {
        stockShortfall,
        status: 'paid',
        payIntentId: intentId,
        paidAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    // The rider shows this code (QR) at handover; the buyer scans or types it.
    tx.set(db().collection('order_secrets').doc(orderId), {
        orderId, sellerId: o.sellerId, riderId: null,
        handoverCode: String(crypto.randomInt(1000, 10000)),
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    if (o.delivery) {
        tx.set(db().collection('delivery_jobs').doc(orderId), {
            orderId, status: 'open', pickup: o.delivery.pickup, dropoff: o.delivery.dropoff,
            distanceKm: o.delivery.distanceKm, durationMin: o.delivery.durationMin,
            payout: o.deliveryFee, currency: o.currency, productName: o.productName,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    tx.set(db().collection('notifications').doc(`order_paid_${orderId}`), {
        userId: o.sellerId, recipientId: o.sellerId, actorId: o.buyerId, category: 'system', priority: 'high', type: 'commerce',
        title: stockShortfall ? 'New order — check stock' : 'New order',
        body: stockShortfall
            ? `${o.quantity} × ${o.productName} is paid, but your listed stock ran out. Confirm you can fill it or cancel.`
            : `${o.quantity} × ${o.productName}${o.variantName ? ` (${o.variantName})` : ''} is paid. Get it ready for pickup.`,
        deepLink: `/biz/orders/${orderId}`, isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    // Buyer's receipt.
    tx.set(db().collection('notifications').doc(`order_receipt_${orderId}`), {
        userId: o.buyerId, recipientId: o.buyerId, actorId: o.sellerId, category: 'system', priority: 'normal', type: 'commerce',
        title: 'Payment received',
        body: `${o.productName} is paid and held safely until you confirm delivery.`,
        deepLink: `/biz/orders/${orderId}`, isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
}
// ───────────────────────────── Delivery flow ─────────────────────────────
async function orderFor(orderId) {
    const id = String(orderId !== null && orderId !== void 0 ? orderId : '');
    if (!id || id.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Missing order.');
    const ref = db().collection('orders').doc(id);
    const o = (await ref.get()).data();
    if (!o)
        throw new https_1.HttpsError('not-found', 'Order not found.');
    return { ref, o, id };
}
/** A delivery partner takes a paid order. */
exports.acceptDelivery = (0, https_1.onCall)(async (req) => {
    var _a;
    const me = uid(req);
    const { ref, id } = await orderFor((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    const user = (await db().collection('users').doc(me).get()).data();
    if ((user === null || user === void 0 ? void 0 : user.deliveryPartner) !== true)
        throw new https_1.HttpsError('permission-denied', 'Turn on delivery partner mode first.');
    if (!(await canReceive(me)))
        throw new https_1.HttpsError('failed-precondition', 'Verify your identity and add a payout method first.');
    await db().runTransaction(async (tx) => {
        const o = (await tx.get(ref)).data();
        if (!o || o.status !== 'paid' || o.riderId)
            throw new https_1.HttpsError('failed-precondition', 'Someone else took this delivery.');
        if (o.buyerId === me || o.sellerId === me)
            throw new https_1.HttpsError('failed-precondition', 'You can’t deliver your own order.');
        tx.update(ref, { riderId: me, participants: firestore_1.FieldValue.arrayUnion(me), status: 'assigned', assignedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
        tx.update(db().collection('order_secrets').doc(id), { riderId: me });
        tx.set(db().collection('delivery_jobs').doc(id), { status: 'taken', riderId: me, takenAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    });
    return { ok: true };
});
/** The rider has the goods and starts the trip. */
exports.startJourney = (0, https_1.onCall)(async (req) => {
    var _a;
    const me = uid(req);
    const { ref, o } = await orderFor((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    if (o.riderId !== me)
        throw new https_1.HttpsError('permission-denied', 'This isn’t your delivery.');
    if (o.status !== 'assigned')
        throw new https_1.HttpsError('failed-precondition', 'This delivery can’t start now.');
    await ref.update({ status: 'in_transit', pickedUpAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    return { ok: true };
});
/** The buyer confirms they have the goods with the handover code; the escrow is released. */
exports.confirmDelivery = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c;
    const me = uid(req);
    const { ref, o, id } = await orderFor((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    if (o.buyerId !== me)
        throw new https_1.HttpsError('permission-denied', 'Only the buyer can confirm delivery.');
    const okStatus = o.delivery ? ['in_transit', 'assigned'] : ['paid'];
    if (!okStatus.includes(o.status))
        throw new https_1.HttpsError('failed-precondition', 'This order can’t be confirmed now.');
    const secret = (await db().collection('order_secrets').doc(id).get()).data();
    const code = String((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.code) !== null && _c !== void 0 ? _c : '').trim();
    if (!secret || !code || !crypto.timingSafeEqual(Buffer.from(code.padEnd(8)), Buffer.from(String(secret.handoverCode).padEnd(8)))) {
        throw new https_1.HttpsError('invalid-argument', 'That code doesn’t match. Ask the rider to show it again.');
    }
    // One transaction: the status check, the release and the balances, so a
    // double tap can't pay twice.
    const release = (0, ledger_1.ledgerRef)(`release_${id}`);
    await db().runTransaction(async (tx) => {
        var _a;
        const [cur, done] = await Promise.all([tx.get(ref), tx.get(release)]);
        const c = cur.data();
        if (!c || !okStatus.includes(c.status))
            throw new https_1.HttpsError('failed-precondition', 'Already confirmed.');
        const m = orderMinor(c);
        const split = (0, payLogic_1.orderSplit)(m.items, m.delivery, Number((_a = c.commissionPercent) !== null && _a !== void 0 ? _a : commissionPercent()));
        const riderGets = c.riderId ? split.rider : 0;
        const lines = [
            { account: `escrow:${id}`, currency: m.currency, amountMinor: -m.total },
            // A sale lands in the seller's business balance; the rider is paid personally.
            { account: `biz:${c.sellerId}`, currency: m.currency, amountMinor: split.seller, bucket: 'available' },
            ...(riderGets ? [{ account: `user:${c.riderId}`, currency: m.currency, amountMinor: riderGets, bucket: 'available' }] : []),
            // No rider (pickup in person): the delivery part stays with the platform.
            { account: 'platform:revenue', currency: m.currency, amountMinor: split.platform + (split.rider - riderGets) },
        ];
        (0, ledger_1.writeLedger)(tx, release.id, done.exists, 'order_release', lines.filter((l) => l.amountMinor !== 0), { orderId: id });
        tx.update(ref, {
            status: 'completed',
            sellerEarnedMinor: split.seller,
            riderEarnedMinor: riderGets,
            deliveredAt: firestore_1.FieldValue.serverTimestamp(),
            releasedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.set(db().collection('notifications').doc(`order_done_${id}`), {
            userId: c.sellerId, recipientId: c.sellerId, actorId: me, category: 'system', priority: 'high', type: 'commerce',
            title: 'Order delivered — money is yours',
            body: `${c.productName} was delivered. Your earnings are in your Oneova balance, ready to withdraw.`,
            deepLink: '/biz/payouts', isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return { ok: true };
});
/** Buyer or seller cancels before pickup: the payment is returned. */
exports.cancelOrder = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const me = uid(req);
    const { ref, o } = await orderFor((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    if (o.buyerId !== me && o.sellerId !== me)
        throw new https_1.HttpsError('permission-denied', 'This isn’t your order.');
    if (o.status === 'awaiting_payment' || o.status === 'payment_failed') {
        if (o.payIntentId) {
            await db().doc(`pay_intents/${o.payIntentId}`).set({ cancelRequested: true }, { merge: true }).catch(() => undefined);
        }
        await ref.update({ status: 'cancelled', cancelledBy: me, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        return { ok: true, refunded: false };
    }
    if (!['paid', 'assigned'].includes(o.status)) {
        throw new https_1.HttpsError('failed-precondition', 'This order is already on its way, so it can’t be cancelled here.');
    }
    await db().runTransaction(async (tx) => {
        const cur = (await tx.get(ref)).data();
        if (!cur || !['paid', 'assigned'].includes(cur.status))
            throw new https_1.HttpsError('failed-precondition', 'Already changed.');
        tx.update(ref, { status: 'refunding', cancelledBy: me, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        tx.set(db().collection('delivery_jobs').doc(ref.id), { status: 'cancelled' }, { merge: true });
    });
    const { refundIntent } = await Promise.resolve().then(() => __importStar(require('../pay/intents')));
    const r = await refundIntent(String((_b = o.payIntentId) !== null && _b !== void 0 ? _b : ''), `order_${ref.id}`);
    logger.info('order refund', ref.id, r);
    await ref.update({ status: r === 'review' ? 'refund_review' : 'refunded', updatedAt: firestore_1.FieldValue.serverTimestamp() });
    return { ok: true, refunded: r !== 'review' };
});
//# sourceMappingURL=orderEscrow.js.map