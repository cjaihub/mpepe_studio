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
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { canFulfil, codeDiscount, FULFILMENT, Fulfilment, nextRating, normalizeCode, StoreRuleError } from './storeLogic';

const db = () => getFirestore();

function uid(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

const safeId = (v: unknown) => {
  const s = String(v ?? '');
  if (!s || s.includes('/') || s.length > 128) throw new HttpsError('invalid-argument', 'Missing id.');
  return s;
};

const day = (ms = Date.now()) => new Date(ms).toISOString().slice(0, 10).replace(/-/g, '');

function rethrow(e: unknown): never {
  if (e instanceof StoreRuleError) throw new HttpsError(e.code, e.message);
  throw e;
}

const FULFIL_TEXT: Record<Fulfilment, string> = {
  new: 'Order received',
  packed: 'Your order is packed',
  ready: 'Your order is ready for pickup or delivery',
  shipped: 'Your order is on its way',
};

export const bizSetFulfilment = onCall(async (req) => {
  const me = uid(req);
  const orderId = safeId(req.data?.orderId);
  const step = String(req.data?.step ?? '') as Fulfilment;
  if (!FULFILMENT.includes(step)) throw new HttpsError('invalid-argument', 'Unknown step.');
  const note = String(req.data?.note ?? '').trim().slice(0, 200);
  const ref = db().collection('orders').doc(orderId);
  const o = await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur) throw new HttpsError('not-found', 'Order not found.');
    if (cur.sellerId !== me) throw new HttpsError('permission-denied', 'This isn’t your order.');
    if (!['paid', 'assigned', 'in_transit'].includes(String(cur.status))) {
      throw new HttpsError('failed-precondition', 'Only paid orders can be prepared.');
    }
    if (!canFulfil(cur.fulfilment, step)) throw new HttpsError('failed-precondition', 'That step is already done.');
    tx.update(ref, {
      fulfilment: step,
      fulfilmentTimeline: FieldValue.arrayUnion({ step, note, at: Date.now() }),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return cur;
  });
  await db().collection('notifications').doc(`order_${orderId}_${step}`).set({
    userId: o.buyerId, recipientId: o.buyerId, actorId: me, category: 'system', priority: 'normal', type: 'commerce',
    title: FULFIL_TEXT[step], body: note || String(o.productName ?? 'Your order'), deepLink: `/biz/orders/${orderId}`,
    isRead: false, createdAt: FieldValue.serverTimestamp(),
  }).catch(() => undefined);
  return { ok: true, fulfilment: step };
});

export const bizSubmitReview = onCall(async (req) => {
  const me = uid(req);
  const orderId = safeId(req.data?.orderId);
  const stars = Number(req.data?.rating);
  if (!Number.isFinite(stars) || stars < 1 || stars > 5) throw new HttpsError('invalid-argument', 'Choose 1 to 5 stars.');
  const text = String(req.data?.text ?? '').trim().slice(0, 1000);
  const orderRef = db().collection('orders').doc(orderId);
  const reviewRef = db().collection('product_reviews').doc(orderId);
  await db().runTransaction(async (tx) => {
    const o = (await tx.get(orderRef)).data();
    if (!o || o.buyerId !== me) throw new HttpsError('permission-denied', 'Only the buyer can review this order.');
    if (o.status !== 'completed') throw new HttpsError('failed-precondition', 'You can review once the order is delivered.');
    if ((await tx.get(reviewRef)).exists) throw new HttpsError('already-exists', 'You already reviewed this order.');
    const productRef = db().collection('products').doc(String(o.productId));
    const shopRef = db().collection('biz_shops').doc(String(o.sellerId));
    const [p, s, u] = await Promise.all([tx.get(productRef), tx.get(shopRef), tx.get(db().collection('users').doc(me))]);
    const user = u.data() ?? {};
    tx.set(reviewRef, {
      orderId, productId: o.productId, sellerId: o.sellerId, buyerId: me,
      buyerName: String(user.displayName || user.username || 'Buyer').slice(0, 60),
      buyerAvatar: typeof user.profilePhotoUrl === 'string' ? user.profilePhotoUrl : null,
      variantName: o.variantName ?? null, rating: Math.round(stars), text, verifiedPurchase: true,
      createdAt: FieldValue.serverTimestamp(),
    });
    if (p.exists) tx.update(productRef, nextRating(p.get('rating'), p.get('reviewCount'), stars));
    if (s.exists) tx.update(shopRef, nextRating(s.get('rating'), s.get('reviewCount'), stars));
  });
  return { ok: true };
});

export const bizTrackEvent = onCall(async (req) => {
  const me = uid(req);
  const shopId = safeId(req.data?.shopId);
  const kind = String(req.data?.kind ?? '');
  if (!['view', 'cart', 'save'].includes(kind)) throw new HttpsError('invalid-argument', 'Unknown event.');
  const productId = req.data?.productId == null ? '' : safeId(req.data.productId);
  if (me === shopId) return { ok: true, counted: false }; // the seller's own visits don't count
  const d = day();
  const seen = db().collection('biz_shop_seen').doc(`${shopId}_${me}_${d}_${kind}_${productId || 'shop'}`);
  const counted = await db().runTransaction(async (tx) => {
    if ((await tx.get(seen)).exists) return false;
    tx.set(seen, { at: FieldValue.serverTimestamp(), expireAt: new Date(Date.now() + 3 * 86400_000) });
    tx.set(db().doc(`biz_shops/${shopId}/daily/${d}`), {
      day: d,
      [`${kind}s`]: FieldValue.increment(1),
      ...(productId ? { [`byProduct.${productId}.${kind}s`]: FieldValue.increment(1) } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  });
  return { ok: true, counted };
});

export const bizCheckCode = onCall(async (req) => {
  uid(req);
  const sellerId = safeId(req.data?.sellerId);
  const code = normalizeCode(req.data?.code);
  if (!code) throw new HttpsError('invalid-argument', 'Enter a code.');
  const items = Number(req.data?.itemsAmount);
  const currency = String(req.data?.currency ?? 'USD');
  const doc = (await db().doc(`biz_shops/${sellerId}/codes/${code}`).get()).data();
  try {
    const off = codeDiscount(doc ? { ...doc, endsAtMs: doc.endsAt?.toMillis?.() } as any : null, Number.isFinite(items) ? items : 0, currency, Date.now());
    return { ok: true, code, discount: off };
  } catch (e) {
    rethrow(e);
  }
});
