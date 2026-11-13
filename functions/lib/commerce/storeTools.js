"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.bizCheckCode = exports.bizTrackEvent = exports.bizSubmitReview = exports.bizSetFulfilment = void 0;
/**
 * Seller and buyer store tools for the Business portal (no money moves here;
 * checkout and escrow live in orderEscrow.ts).
 *
 *   seller → bizSetFulfilment  new → packed → ready → shipped (buyer notified)
 *   buyer  → bizSubmitReview   once per completed order; updates product and
 *                              shop rating (server-only fields)
 *   anyone → bizTrackEvent     view / cart counters per shop per day, one per
 *                              person per item per day
 *   buyer  → bizCheckCode      preview a seller's discount code (checkout
 *                              applies and counts it)
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const storeLogic_1 = require("./storeLogic");
const db = () => (0, firestore_1.getFirestore)();
function uid(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
const safeId = (v) => {
    const s = String(v !== null && v !== void 0 ? v : '');
    if (!s || s.includes('/') || s.length > 128)
        throw new https_1.HttpsError('invalid-argument', 'Missing id.');
    return s;
};
const day = (ms = Date.now()) => new Date(ms).toISOString().slice(0, 10).replace(/-/g, '');
function rethrow(e) {
    if (e instanceof storeLogic_1.StoreRuleError)
        throw new https_1.HttpsError(e.code, e.message);
    throw e;
}
const FULFIL_TEXT = {
    new: 'Order received',
    packed: 'Your order is packed',
    ready: 'Your order is ready for pickup or delivery',
    shipped: 'Your order is on its way',
};
exports.bizSetFulfilment = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d, _e, _f;
    const me = uid(req);
    const orderId = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    const step = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.step) !== null && _d !== void 0 ? _d : '');
    if (!storeLogic_1.FULFILMENT.includes(step))
        throw new https_1.HttpsError('invalid-argument', 'Unknown step.');
    const note = String((_e = (_c = req.data) === null || _c === void 0 ? void 0 : _c.note) !== null && _e !== void 0 ? _e : '').trim().slice(0, 200);
    const ref = db().collection('orders').doc(orderId);
    const o = await db().runTransaction(async (tx) => {
        const cur = (await tx.get(ref)).data();
        if (!cur)
            throw new https_1.HttpsError('not-found', 'Order not found.');
        if (cur.sellerId !== me)
            throw new https_1.HttpsError('permission-denied', 'This isn’t your order.');
        if (!['paid', 'assigned', 'in_transit'].includes(String(cur.status))) {
            throw new https_1.HttpsError('failed-precondition', 'Only paid orders can be prepared.');
        }
        if (!(0, storeLogic_1.canFulfil)(cur.fulfilment, step))
            throw new https_1.HttpsError('failed-precondition', 'That step is already done.');
        tx.update(ref, {
            fulfilment: step,
            fulfilmentTimeline: firestore_1.FieldValue.arrayUnion({ step, note, at: Date.now() }),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return cur;
    });
    await db().collection('notifications').doc(`order_${orderId}_${step}`).set({
        userId: o.buyerId, recipientId: o.buyerId, actorId: me, category: 'system', priority: 'normal', type: 'commerce',
        title: FULFIL_TEXT[step], body: note || String((_f = o.productName) !== null && _f !== void 0 ? _f : 'Your order'), deepLink: `/biz/orders/${orderId}`,
        isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    }).catch(() => undefined);
    return { ok: true, fulfilment: step };
});
exports.bizSubmitReview = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d;
    const me = uid(req);
    const orderId = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.orderId);
    const stars = Number((_b = req.data) === null || _b === void 0 ? void 0 : _b.rating);
    if (!Number.isFinite(stars) || stars < 1 || stars > 5)
        throw new https_1.HttpsError('invalid-argument', 'Choose 1 to 5 stars.');
    const text = String((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.text) !== null && _d !== void 0 ? _d : '').trim().slice(0, 1000);
    const orderRef = db().collection('orders').doc(orderId);
    const reviewRef = db().collection('product_reviews').doc(orderId);
    await db().runTransaction(async (tx) => {
        var _a, _b;
        const o = (await tx.get(orderRef)).data();
        if (!o || o.buyerId !== me)
            throw new https_1.HttpsError('permission-denied', 'Only the buyer can review this order.');
        if (o.status !== 'completed')
            throw new https_1.HttpsError('failed-precondition', 'You can review once the order is delivered.');
        if ((await tx.get(reviewRef)).exists)
            throw new https_1.HttpsError('already-exists', 'You already reviewed this order.');
        const productRef = db().collection('products').doc(String(o.productId));
        const shopRef = db().collection('biz_shops').doc(String(o.sellerId));
        const [p, s, u] = await Promise.all([tx.get(productRef), tx.get(shopRef), tx.get(db().collection('users').doc(me))]);
        const user = (_a = u.data()) !== null && _a !== void 0 ? _a : {};
        tx.set(reviewRef, {
            orderId, productId: o.productId, sellerId: o.sellerId, buyerId: me,
            buyerName: String(user.displayName || user.username || 'Buyer').slice(0, 60),
            buyerAvatar: typeof user.profilePhotoUrl === 'string' ? user.profilePhotoUrl : null,
            variantName: (_b = o.variantName) !== null && _b !== void 0 ? _b : null, rating: Math.round(stars), text, verifiedPurchase: true,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        if (p.exists)
            tx.update(productRef, (0, storeLogic_1.nextRating)(p.get('rating'), p.get('reviewCount'), stars));
        if (s.exists)
            tx.update(shopRef, (0, storeLogic_1.nextRating)(s.get('rating'), s.get('reviewCount'), stars));
    });
    return { ok: true };
});
exports.bizTrackEvent = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d;
    const me = uid(req);
    const shopId = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.shopId);
    const kind = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.kind) !== null && _d !== void 0 ? _d : '');
    if (!['view', 'cart', 'save'].includes(kind))
        throw new https_1.HttpsError('invalid-argument', 'Unknown event.');
    const productId = ((_c = req.data) === null || _c === void 0 ? void 0 : _c.productId) == null ? '' : safeId(req.data.productId);
    if (me === shopId)
        return { ok: true, counted: false }; // the seller's own visits don't count
    const d = day();
    const seen = db().collection('biz_shop_seen').doc(`${shopId}_${me}_${d}_${kind}_${productId || 'shop'}`);
    const counted = await db().runTransaction(async (tx) => {
        if ((await tx.get(seen)).exists)
            return false;
        tx.set(seen, { at: firestore_1.FieldValue.serverTimestamp(), expireAt: new Date(Date.now() + 3 * 86400000) });
        tx.set(db().doc(`biz_shops/${shopId}/daily/${d}`), Object.assign(Object.assign({ day: d, [`${kind}s`]: firestore_1.FieldValue.increment(1) }, (productId ? { [`byProduct.${productId}.${kind}s`]: firestore_1.FieldValue.increment(1) } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
        return true;
    });
    return { ok: true, counted };
});
exports.bizCheckCode = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e, _f;
    var _g;
    uid(req);
    const sellerId = safeId((_a = req.data) === null || _a === void 0 ? void 0 : _a.sellerId);
    const code = (0, storeLogic_1.normalizeCode)((_b = req.data) === null || _b === void 0 ? void 0 : _b.code);
    if (!code)
        throw new https_1.HttpsError('invalid-argument', 'Enter a code.');
    const items = Number((_c = req.data) === null || _c === void 0 ? void 0 : _c.itemsAmount);
    const currency = String((_g = (_d = req.data) === null || _d === void 0 ? void 0 : _d.currency) !== null && _g !== void 0 ? _g : 'USD');
    const doc = (await db().doc(`biz_shops/${sellerId}/codes/${code}`).get()).data();
    try {
        const off = (0, storeLogic_1.codeDiscount)(doc ? Object.assign(Object.assign({}, doc), { endsAtMs: (_f = (_e = doc.endsAt) === null || _e === void 0 ? void 0 : _e.toMillis) === null || _f === void 0 ? void 0 : _f.call(_e) }) : null, Number.isFinite(items) ? items : 0, currency, Date.now());
        return { ok: true, code, discount: off };
    }
    catch (e) {
        rethrow(e);
    }
});
//# sourceMappingURL=storeTools.js.map