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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.cancelOrder = exports.confirmDelivery = exports.startJourney = exports.acceptDelivery = exports.stripeWebhook = exports.createOrderCheckout = exports.quoteDelivery = exports.stripePayoutStatus = exports.stripeConnectOnboard = exports.stripeConfig = void 0;
/**
 * Oneova Biz payments on Stripe Connect, with escrow until the buyer has the goods.
 *
 *   seller / rider  → stripeConnectOnboard: Express account + onboarding link
 *   buyer           → quoteDelivery: live route price (Directions API)
 *                   → createOrderCheckout: order + PaymentIntent on the platform
 *   Stripe          → stripeWebhook: payment_intent.succeeded → order "paid" (held)
 *   rider           → acceptDelivery / startJourney
 *   buyer           → confirmDelivery(code): releases the money with Transfers:
 *                     items − commission → seller, delivery fee → rider
 *   buyer / seller  → cancelOrder before pickup → full refund
 *
 * Money never moves on the client's word: amounts are computed here from the
 * product docs and the stored quote, and only the webhook marks an order paid.
 *
 * Secrets (Secret Manager, read at run time so they never block a deploy):
 *   STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, GOOGLE_MAPS_SERVER_KEY
 * Params (functions/.env.mpepe-2b4bd): STRIPE_PUBLISHABLE_KEY (public),
 *   COMMERCE_COMMISSION_PERCENT (default 10).
 */
const crypto = __importStar(require("crypto"));
const stripe_1 = __importDefault(require("stripe"));
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const optionalSecrets_1 = require("../optionalSecrets");
const db = () => (0, firestore_1.getFirestore)();
const RETURN_URL = 'https://mpepe-2b4bd.web.app/';
/** Currencies Stripe charges without minor units. */
const ZERO_DECIMAL = new Set(['bif', 'clp', 'djf', 'gnf', 'jpy', 'kmf', 'krw', 'mga', 'pyg', 'rwf', 'ugx', 'vnd', 'vuv', 'xaf', 'xof', 'xpf']);
const minor = (amount, currency) => ZERO_DECIMAL.has(currency) ? Math.round(amount) : Math.round(amount * 100);
/**
 * Motorbike delivery rates per currency: base + per km + per minute.
 * Rush hours (07–09, 17–20 local server time) add 20%.
 */
const RATES = {
    usd: { base: 1.5, perKm: 0.6, perMin: 0.05, min: 2.5 },
    eur: { base: 1.4, perKm: 0.55, perMin: 0.05, min: 2.3 },
    gbp: { base: 1.2, perKm: 0.5, perMin: 0.04, min: 2.0 },
    zar: { base: 20, perKm: 7, perMin: 0.6, min: 35 },
    kes: { base: 100, perKm: 40, perMin: 3, min: 150 },
    ngn: { base: 800, perKm: 250, perMin: 20, min: 1200 },
    ghs: { base: 10, perKm: 4, perMin: 0.3, min: 15 },
    tzs: { base: 1500, perKm: 600, perMin: 40, min: 2500 },
    ugx: { base: 3000, perKm: 1200, perMin: 80, min: 5000 },
};
async function stripe() {
    const key = await (0, optionalSecrets_1.optionalSecret)('STRIPE_SECRET_KEY');
    if (!key)
        throw new https_1.HttpsError('failed-precondition', 'Payments are being set up. Please try again soon.');
    return new stripe_1.default(key, { apiVersion: '2025-02-24.acacia' });
}
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
// ───────────────────────────── Config ─────────────────────────────
/** Publishable key for the app's Payment Sheet (public by design). */
exports.stripeConfig = (0, https_1.onCall)(async () => {
    var _a;
    const pk = ((_a = process.env.STRIPE_PUBLISHABLE_KEY) !== null && _a !== void 0 ? _a : '').trim();
    return { publishableKey: pk.startsWith('pk_') ? pk : '', merchantName: 'Oneova' };
});
// ───────────────────────────── Payout accounts ─────────────────────────────
/** Creates (once) a Stripe Express account for a seller or rider and returns an onboarding link. */
exports.stripeConnectOnboard = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const me = uid(req);
    const s = await stripe();
    const ref = db().collection('payout_accounts').doc(me);
    let accountId = (await ref.get()).get('stripeAccountId');
    if (!accountId) {
        const user = (_b = (await db().collection('users').doc(me).get()).data()) !== null && _b !== void 0 ? _b : {};
        const country = typeof ((_a = req.data) === null || _a === void 0 ? void 0 : _a.country) === 'string' && /^[A-Z]{2}$/.test(req.data.country) ? req.data.country : undefined;
        const acct = await s.accounts.create({
            type: 'express',
            country,
            email: typeof user.email === 'string' ? user.email : undefined,
            capabilities: { transfers: { requested: true } },
            business_profile: { product_description: 'Sells or delivers goods on Oneova Biz' },
            metadata: { uid: me },
        });
        accountId = acct.id;
        await ref.set({ uid: me, stripeAccountId: accountId, payoutsEnabled: false, detailsSubmitted: false, createdAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    }
    const link = await s.accountLinks.create({
        account: accountId,
        type: 'account_onboarding',
        refresh_url: RETURN_URL,
        return_url: RETURN_URL,
    });
    return { url: link.url };
});
/** Refreshes and returns the caller's payout status. */
exports.stripePayoutStatus = (0, https_1.onCall)(async (req) => {
    var _a;
    const me = uid(req);
    const ref = db().collection('payout_accounts').doc(me);
    const accountId = (await ref.get()).get('stripeAccountId');
    if (!accountId)
        return { connected: false, payoutsEnabled: false };
    const acct = await (await stripe()).accounts.retrieve(accountId);
    const status = { payoutsEnabled: acct.payouts_enabled === true, detailsSubmitted: acct.details_submitted === true, transfersActive: ((_a = acct.capabilities) === null || _a === void 0 ? void 0 : _a.transfers) === 'active' };
    await ref.set(Object.assign(Object.assign({}, status), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    return Object.assign({ connected: true }, status);
});
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
function deliveryFee(km, min, currency) {
    var _a;
    const r = (_a = RATES[currency]) !== null && _a !== void 0 ? _a : RATES.usd;
    const hour = new Date().getUTCHours();
    const rush = (hour >= 7 && hour < 9) || (hour >= 17 && hour < 20) ? 1.2 : 1;
    const fee = Math.max(r.min, (r.base + r.perKm * km + r.perMin * min) * rush);
    return ZERO_DECIMAL.has(currency) ? Math.round(fee) : Math.round(fee * 100) / 100;
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
    const currency = String(product.currency || 'usd').toLowerCase();
    const r = await route(pickup, dropoff);
    const fee = deliveryFee(r.km, r.min, currency);
    const ref = await db().collection('delivery_quotes').add({
        uid: me, productId, sellerId, pickup, dropoff, currency, fee,
        distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: (_e = r.polyline) !== null && _e !== void 0 ? _e : null,
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + 15 * 60000), createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return { quoteId: ref.id, fee, currency, distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: (_f = r.polyline) !== null && _f !== void 0 ? _f : null };
});
// ───────────────────────────── Checkout ─────────────────────────────
/** Creates the order and its PaymentIntent. The money is held on the platform until delivery. */
exports.createOrderCheckout = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h;
    const me = uid(req);
    const productId = String((_e = (_a = req.data) === null || _a === void 0 ? void 0 : _a.productId) !== null && _e !== void 0 ? _e : '');
    const qty = Math.min(Math.max(Math.floor((_f = num((_b = req.data) === null || _b === void 0 ? void 0 : _b.quantity)) !== null && _f !== void 0 ? _f : 1), 1), 20);
    const quoteId = String((_g = (_c = req.data) === null || _c === void 0 ? void 0 : _c.quoteId) !== null && _g !== void 0 ? _g : '');
    const address = String((_h = (_d = req.data) === null || _d === void 0 ? void 0 : _d.address) !== null && _h !== void 0 ? _h : '').slice(0, 300);
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
    const currency = String(product.currency || 'usd').toLowerCase();
    const seller = (await db().collection('payout_accounts').doc(sellerId).get()).data();
    if (!(seller === null || seller === void 0 ? void 0 : seller.stripeAccountId) || seller.payoutsEnabled !== true) {
        throw new https_1.HttpsError('failed-precondition', 'This shop can’t take payments yet.');
    }
    let delivery = 0;
    let quote;
    if (quoteId) {
        quote = (await db().collection('delivery_quotes').doc(quoteId).get()).data();
        if (!quote || quote.uid !== me || quote.productId !== productId)
            throw new https_1.HttpsError('invalid-argument', 'Please refresh the delivery price.');
        if (quote.expiresAt.toMillis() < Date.now())
            throw new https_1.HttpsError('deadline-exceeded', 'The delivery price expired. Please refresh it.');
        delivery = Number(quote.fee);
    }
    const items = price * qty;
    const total = items + delivery;
    const s = await stripe();
    const payRef = db().collection('payout_accounts').doc(me);
    let customer = (await payRef.get()).get('stripeCustomerId');
    if (!customer) {
        customer = (await s.customers.create({ metadata: { uid: me } })).id;
        await payRef.set({ uid: me, stripeCustomerId: customer }, { merge: true });
    }
    const orderRef = db().collection('orders').doc();
    const intent = await s.paymentIntents.create({
        amount: minor(total, currency),
        currency,
        customer,
        automatic_payment_methods: { enabled: true },
        transfer_group: orderRef.id,
        description: `Oneova order ${orderRef.id}`,
        metadata: { orderId: orderRef.id, buyerId: me, sellerId },
    }, { idempotencyKey: `order_${orderRef.id}` });
    const ephemeral = await s.ephemeralKeys.create({ customer }, { apiVersion: '2025-02-24.acacia' });
    await orderRef.set({
        buyerId: me,
        sellerId,
        participants: [me, sellerId],
        productId,
        productName: String(product.name || product.title || 'Item').slice(0, 120),
        imageUrl: typeof product.imageUrl === 'string' ? product.imageUrl : null,
        quantity: qty,
        currency,
        itemsAmount: items,
        deliveryFee: delivery,
        totalAmount: total,
        commissionPercent: commissionPercent(),
        delivery: quote ? { pickup: quote.pickup, dropoff: quote.dropoff, address, distanceKm: quote.distanceKm, durationMin: quote.durationMin, polyline: quote.polyline } : null,
        status: 'awaiting_payment',
        paymentIntentId: intent.id,
        riderId: null,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return {
        orderId: orderRef.id,
        clientSecret: intent.client_secret,
        customerId: customer,
        ephemeralKey: ephemeral.secret,
        total,
        currency,
    };
});
// ───────────────────────────── Webhook ─────────────────────────────
exports.stripeWebhook = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c, _d;
    var _e, _f;
    const secret = await (0, optionalSecrets_1.optionalSecret)('STRIPE_WEBHOOK_SECRET');
    if (!secret) {
        res.status(503).send('not configured');
        return;
    }
    let event;
    try {
        event = (await stripe()).webhooks.constructEvent(req.rawBody, String((_e = req.headers['stripe-signature']) !== null && _e !== void 0 ? _e : ''), secret);
    }
    catch (e) {
        logger.warn('stripe webhook signature failed', e === null || e === void 0 ? void 0 : e.message);
        res.status(400).send('bad signature');
        return;
    }
    try {
        switch (event.type) {
            case 'payment_intent.succeeded': {
                const pi = event.data.object;
                const orderId = (_a = pi.metadata) === null || _a === void 0 ? void 0 : _a.orderId;
                if (!orderId)
                    break;
                const ref = db().collection('orders').doc(orderId);
                await db().runTransaction(async (tx) => {
                    var _a;
                    var _b;
                    const o = (await tx.get(ref)).data();
                    if (!o || o.status !== 'awaiting_payment')
                        return;
                    tx.update(ref, {
                        status: 'paid',
                        chargeId: typeof pi.latest_charge === 'string' ? pi.latest_charge : (_b = (_a = pi.latest_charge) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null,
                        paidAt: firestore_1.FieldValue.serverTimestamp(),
                        updatedAt: firestore_1.FieldValue.serverTimestamp(),
                    });
                    // The rider shows this code (QR) at handover; the buyer scans or types it.
                    tx.set(db().collection('order_secrets').doc(orderId), {
                        orderId, sellerId: o.sellerId, riderId: null,
                        handoverCode: String(crypto.randomInt(1000, 10000)),
                        createdAt: firestore_1.FieldValue.serverTimestamp(),
                    });
                    // Open job for delivery partners (no buyer details beyond the drop-off pin).
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
                        title: 'New order', body: `${o.quantity} × ${o.productName} is paid. Get it ready for pickup.`,
                        deepLink: `/biz/orders/${orderId}`, isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
                    });
                });
                break;
            }
            case 'payment_intent.payment_failed': {
                const pi = event.data.object;
                if ((_b = pi.metadata) === null || _b === void 0 ? void 0 : _b.orderId) {
                    await db().collection('orders').doc(pi.metadata.orderId).update({ status: 'payment_failed', updatedAt: firestore_1.FieldValue.serverTimestamp() }).catch(() => undefined);
                }
                break;
            }
            case 'account.updated': {
                const a = event.data.object;
                const owner = (_c = a.metadata) === null || _c === void 0 ? void 0 : _c.uid;
                if (owner) {
                    await db().collection('payout_accounts').doc(owner).set({
                        payoutsEnabled: a.payouts_enabled === true,
                        detailsSubmitted: a.details_submitted === true,
                        transfersActive: ((_d = a.capabilities) === null || _d === void 0 ? void 0 : _d.transfers) === 'active',
                        updatedAt: firestore_1.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
                break;
            }
        }
        res.status(200).send('ok');
    }
    catch (e) {
        logger.error('stripe webhook handling failed', event.type, (_f = e === null || e === void 0 ? void 0 : e.message) !== null && _f !== void 0 ? _f : e);
        res.status(500).send('error');
    }
});
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
    const payout = (await db().collection('payout_accounts').doc(me).get()).data();
    const user = (await db().collection('users').doc(me).get()).data();
    if ((user === null || user === void 0 ? void 0 : user.deliveryPartner) !== true)
        throw new https_1.HttpsError('permission-denied', 'Turn on delivery partner mode first.');
    if (!(payout === null || payout === void 0 ? void 0 : payout.stripeAccountId) || payout.payoutsEnabled !== true)
        throw new https_1.HttpsError('failed-precondition', 'Set up your payout account first.');
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
    var _c, _d, _e, _f, _g, _h;
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
    // Claim the release first so a double tap can't pay twice.
    await db().runTransaction(async (tx) => {
        const cur = (await tx.get(ref)).data();
        if (!cur || !okStatus.includes(cur.status))
            throw new https_1.HttpsError('failed-precondition', 'Already confirmed.');
        tx.update(ref, { status: 'releasing', deliveredAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
    const s = await stripe();
    const currency = String(o.currency);
    const sellerShare = Number(o.itemsAmount) * (1 - Number((_d = o.commissionPercent) !== null && _d !== void 0 ? _d : commissionPercent()) / 100);
    const [seller, rider] = await Promise.all([
        db().collection('payout_accounts').doc(o.sellerId).get().then((d) => d.data()),
        o.riderId ? db().collection('payout_accounts').doc(o.riderId).get().then((d) => d.data()) : Promise.resolve(undefined),
    ]);
    const transfers = {};
    try {
        if ((seller === null || seller === void 0 ? void 0 : seller.stripeAccountId) && sellerShare > 0) {
            transfers.seller = (await s.transfers.create({
                amount: minor(sellerShare, currency), currency, destination: seller.stripeAccountId,
                transfer_group: id, source_transaction: (_e = o.chargeId) !== null && _e !== void 0 ? _e : undefined, metadata: { orderId: id, role: 'seller' },
            }, { idempotencyKey: `release_${id}_seller` })).id;
        }
        if ((rider === null || rider === void 0 ? void 0 : rider.stripeAccountId) && Number(o.deliveryFee) > 0) {
            transfers.rider = (await s.transfers.create({
                amount: minor(Number(o.deliveryFee), currency), currency, destination: rider.stripeAccountId,
                transfer_group: id, source_transaction: (_f = o.chargeId) !== null && _f !== void 0 ? _f : undefined, metadata: { orderId: id, role: 'rider' },
            }, { idempotencyKey: `release_${id}_rider` })).id;
        }
        await ref.update({ status: 'completed', transfers, releasedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp() });
    }
    catch (e) {
        logger.error('escrow release failed', id, (_g = e === null || e === void 0 ? void 0 : e.message) !== null && _g !== void 0 ? _g : e);
        await ref.update({ status: 'release_failed', transfers, releaseError: String((_h = e === null || e === void 0 ? void 0 : e.message) !== null && _h !== void 0 ? _h : e).slice(0, 300), updatedAt: firestore_1.FieldValue.serverTimestamp() });
        throw new https_1.HttpsError('internal', 'Delivery is confirmed. Paying the shop is taking longer than usual; our team will finish it.');
    }
    return { ok: true };
});
/** Buyer or seller cancels before pickup: full refund. */
exports.cancelOrder = (0, https_1.onCall)(async (req) => {
    var _a;
    const me = uid(req);
    const { ref, o } = await orderFor((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    if (o.buyerId !== me && o.sellerId !== me)
        throw new https_1.HttpsError('permission-denied', 'This isn’t your order.');
    if (o.status === 'awaiting_payment' || o.status === 'payment_failed') {
        await (await stripe()).paymentIntents.cancel(o.paymentIntentId).catch(() => undefined);
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
        tx.update(ref, { status: 'refunding', updatedAt: firestore_1.FieldValue.serverTimestamp() });
        tx.set(db().collection('delivery_jobs').doc(ref.id), { status: 'cancelled' }, { merge: true });
    });
    const refund = await (await stripe()).refunds.create({ payment_intent: o.paymentIntentId, metadata: { orderId: ref.id } }, { idempotencyKey: `refund_${ref.id}` });
    await ref.update({ status: 'refunded', refundId: refund.id, cancelledBy: me, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    return { ok: true, refunded: true };
});
//# sourceMappingURL=stripeEscrow.js.map