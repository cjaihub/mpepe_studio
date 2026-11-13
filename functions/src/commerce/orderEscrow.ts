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
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp, Transaction } from 'firebase-admin/firestore';
import { optionalSecret } from '../optionalSecrets';
import { pickVariant, stockAfterSale, VariantError } from './variant_logic';
import { StoreRuleError, codeDiscount, customizationExtra, normalizeCode, priceCustomization } from './storeLogic';
import { exponent, toMinor } from '../payments/provider';
import { LedgerLine, currencyFor, orderSplit } from '../pay/payLogic';
import { bucketOf, balanceRef, ledgerRef, writeLedger } from '../pay/ledger';
import { payRuntime } from '../pay/payConfig';
import { storedUsdRate } from './fx';
import { countShare } from './shareLinks';
import { validShareCode } from './shareLogic';

const db = () => getFirestore();

/**
 * Motorbike delivery rates per currency: base + per km + per minute.
 * Rush hours (07–09, 17–20 UTC) add 20%.
 */
const RATES: Record<string, { base: number; perKm: number; perMin: number; min: number }> = {
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

function uid(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

function num(v: unknown): number | null {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

const commissionPercent = () => {
  const p = Number(process.env.COMMERCE_COMMISSION_PERCENT ?? 10);
  return Number.isFinite(p) && p >= 0 && p <= 50 ? p : 10;
};

/** Order currency as ISO upper case (older orders stored it lower case). */
export const orderCurrency = (o: FirebaseFirestore.DocumentData) => String(o.currency || 'USD').toUpperCase();

/** Order totals in minor units (older orders only had decimal amounts). */
export function orderMinor(o: FirebaseFirestore.DocumentData) {
  const cur = orderCurrency(o);
  const items = Number.isSafeInteger(o.itemsMinor) ? Number(o.itemsMinor) : toMinor(Number(o.itemsAmount) || 0, cur);
  const delivery = Number.isSafeInteger(o.deliveryMinor) ? Number(o.deliveryMinor) : toMinor(Number(o.deliveryFee) || 0, cur);
  return { currency: cur, items, delivery, total: items + delivery };
}

/** A product's currency; one saved without one uses the seller's local currency. */
async function productCurrency(product: FirebaseFirestore.DocumentData, sellerId: string): Promise<string> {
  const c = String(product.currency ?? '').trim();
  if (/^[A-Za-z]{3}$/.test(c)) return c.toUpperCase();
  const { countryOf } = await import('../pay/intents');
  return currencyFor(await countryOf(sellerId));
}

// ───────────────────────────── Live deals ─────────────────────────────

export interface ActiveDeal {
  title: string;
  percentOff: number;
}

/**
 * The seller's live deal (`biz_shops/{uid}.liveDeal`) when it is running now
 * and covers [productId] (empty productIds = the whole shop).
 */
export function liveDealFor(raw: unknown, productId: string, nowMs: number): ActiveDeal | null {
  if (!raw || typeof raw !== 'object') return null;
  const d = raw as Record<string, unknown>;
  const pct = typeof d.percentOff === 'number' ? Math.floor(d.percentOff) : 0;
  const ends = d.endsAt as { toMillis?: () => number } | undefined;
  const endsMs = typeof ends?.toMillis === 'function' ? ends.toMillis() : 0;
  if (pct < 1 || pct > 80 || endsMs <= nowMs) return null;
  const ids = Array.isArray(d.productIds) ? d.productIds.filter((x): x is string => typeof x === 'string') : [];
  if (ids.length && !ids.includes(productId)) return null;
  return { title: typeof d.title === 'string' && d.title.trim() ? d.title.trim().slice(0, 80) : 'Live deal', percentOff: pct };
}

/** Deal price: price × (100 − percent) / 100, to the currency's smallest unit (2 dp, whole for UGX/XOF…). */
export function dealPrice(price: number, percentOff: number, currency: string): number {
  const e = exponent(currency);
  const f = 10 ** e;
  return Math.round((price * (100 - percentOff) / 100) * f) / f;
}

// ───────────────────────────── Payout readiness ─────────────────────────────

/** A seller or rider can be paid: verified identity and a saved payout method. */
export async function payoutReady(who: string): Promise<{ kycStatus: string; methods: number; ready: boolean }> {
  const [kyc, methods] = await Promise.all([
    db().doc(`kyc/${who}`).get(),
    db().collection(`payout_methods/${who}/methods`).limit(5).get(),
  ]);
  const kycStatus = String(kyc.get('status') ?? 'none');
  const ready = kycStatus === 'verified' && methods.size > 0;
  return { kycStatus, methods: methods.size, ready };
}

/** Readiness + balances for the payouts screen. */
export const payPayoutStatus = onCall(async (req) => {
  const me = uid(req);
  const [r, bal] = await Promise.all([payoutReady(me), balanceRef(me).get()]);
  const balances: Record<string, { available: number; pending: number; locked: number }> = {};
  for (const [k, v] of Object.entries(bal.data() ?? {})) {
    if (!/^[A-Z]{3}$/.test(k) || typeof v !== 'object' || v === null) continue;
    balances[k] = { available: bucketOf(bal.data(), k, 'available'), pending: bucketOf(bal.data(), k, 'pending'), locked: bucketOf(bal.data(), k, 'locked') };
  }
  return { ...r, payoutsEnabled: r.ready, balances };
});

async function canReceive(who: string): Promise<boolean> {
  if ((await payoutReady(who)).ready) return true;
  // The sandbox lets test shops sell before their identity check is done.
  return (await payRuntime()).cfg.sandbox;
}

// ───────────────────────────── Delivery quote ─────────────────────────────

type LatLng = { lat: number; lng: number };
function latLng(v: unknown): LatLng | null {
  const o = v as Record<string, unknown> | undefined;
  const lat = num(o?.lat), lng = num(o?.lng);
  return lat !== null && lng !== null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : null;
}

async function route(from: LatLng, to: LatLng): Promise<{ km: number; min: number; polyline?: string }> {
  const key = await optionalSecret('GOOGLE_MAPS_SERVER_KEY');
  if (key) {
    const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
    url.searchParams.set('origin', `${from.lat},${from.lng}`);
    url.searchParams.set('destination', `${to.lat},${to.lng}`);
    url.searchParams.set('mode', 'driving');
    url.searchParams.set('avoid', 'highways');
    url.searchParams.set('key', key);
    const res = await fetch(url).then((r) => r.json()).catch(() => null) as any;
    const leg = res?.routes?.[0]?.legs?.[0];
    if (leg?.distance?.value) {
      return { km: leg.distance.value / 1000, min: (leg.duration?.value ?? 0) / 60, polyline: res.routes[0].overview_polyline?.points };
    }
  }
  // No route service: straight-line distance × 1.3 for streets, at 25 km/h.
  const R = 6371, dLat = (to.lat - from.lat) * Math.PI / 180, dLng = (to.lng - from.lng) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(from.lat * Math.PI / 180) * Math.cos(to.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  const km = 2 * R * Math.asin(Math.sqrt(a)) * 1.3;
  return { km, min: km / 25 * 60 };
}

async function deliveryFee(km: number, min: number, currency: string): Promise<number> {
  // Currencies without their own table use the USD rates converted at today's rate.
  const local = RATES[currency];
  const fx = local ? 1 : await storedUsdRate(currency);
  if (!fx) throw new HttpsError('unavailable', 'Delivery prices for this currency are not available right now. Try again in a minute.');
  const r = local ?? RATES.USD;
  const hour = new Date().getUTCHours();
  const rush = (hour >= 7 && hour < 9) || (hour >= 17 && hour < 20) ? 1.2 : 1;
  const fee = Math.max(r.min, (r.base + r.perKm * km + r.perMin * min) * rush) * fx;
  const e = exponent(currency);
  return e === 0 ? Math.round(fee) : Math.round(fee * 10 ** e) / 10 ** e;
}

async function pickupFor(sellerId: string): Promise<LatLng | null> {
  const shop = (await db().collection('biz_shops').doc(sellerId).get()).data();
  const user = shop ? null : (await db().collection('users').doc(sellerId).get()).data();
  return latLng(shop?.location) ?? latLng(user?.shopLocation) ?? latLng(user?.geo);
}

/** Live delivery price for a product to the buyer's location. Valid for 15 minutes. */
export const quoteDelivery = onCall(async (req) => {
  const me = uid(req);
  const productId = String(req.data?.productId ?? '');
  const dropoff = latLng(req.data?.dropoff);
  if (!productId || !dropoff) throw new HttpsError('invalid-argument', 'Choose a product and a delivery spot.');
  const product = (await db().collection('products').doc(productId).get()).data();
  if (!product) throw new HttpsError('not-found', 'This product is no longer available.');
  const sellerId = String(product.ownerId || product.userId || product.uid || '');
  const pickup = latLng(product.location) ?? await pickupFor(sellerId);
  if (!pickup) throw new HttpsError('failed-precondition', 'This shop has not set its pickup location yet.');
  const currency = await productCurrency(product, sellerId);
  const r = await route(pickup, dropoff);
  const fee = await deliveryFee(r.km, r.min, currency);
  const ref = await db().collection('delivery_quotes').add({
    uid: me, productId, sellerId, pickup, dropoff, currency, fee,
    distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: r.polyline ?? null,
    expiresAt: Timestamp.fromMillis(Date.now() + 15 * 60_000), createdAt: FieldValue.serverTimestamp(),
  });
  return { quoteId: ref.id, fee, currency, distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: r.polyline ?? null };
});

// ───────────────────────────── Checkout ─────────────────────────────

/** Creates the priced order. The app then pays it with Oneova Pay (payCreate, purpose "order"). */
export const createOrderCheckout = onCall(async (req) => {
  const me = uid(req);
  const productId = String(req.data?.productId ?? '');
  const qty = Math.min(Math.max(Math.floor(num(req.data?.quantity) ?? 1), 1), 20);
  const quoteId = String(req.data?.quoteId ?? '');
  const address = String(req.data?.address ?? '').slice(0, 300);

  const product = (await db().collection('products').doc(productId).get()).data();
  if (!product) throw new HttpsError('not-found', 'This product is no longer available.');
  const sellerId = String(product.ownerId || product.userId || product.uid || '');
  if (!sellerId) throw new HttpsError('failed-precondition', 'This product has no seller.');
  if (sellerId === me) throw new HttpsError('failed-precondition', 'You can’t buy your own product.');
  const price = num(product.price);
  if (price === null || price <= 0) throw new HttpsError('failed-precondition', 'This product has no price yet.');
  if (product.inStock === false || (typeof product.stock === 'number' && product.stock < qty)) {
    throw new HttpsError('failed-precondition', 'Not enough in stock.');
  }
  let variant: ReturnType<typeof pickVariant> = null;
  try {
    variant = pickVariant(product, req.data?.variantId, qty);
  } catch (e) {
    if (e instanceof VariantError) throw new HttpsError(e.code, e.message);
    throw e;
  }
  const currency = await productCurrency(product, sellerId);
  // A live deal the seller is running right now lowers the base price;
  // the buyer's customization extras are added on top at full price.
  const deal = liveDealFor((await db().collection('biz_shops').doc(sellerId).get()).get('liveDeal'), productId, Date.now());
  let custom: ReturnType<typeof priceCustomization>;
  try {
    custom = priceCustomization(product, req.data?.customization);
  } catch (e) {
    if (e instanceof StoreRuleError) throw new HttpsError(e.code, e.message);
    throw e;
  }
  const basePrice = deal ? dealPrice(price, deal.percentOff, currency) : price;
  const unitPrice = basePrice + customizationExtra(custom);
  if (!(await canReceive(sellerId))) throw new HttpsError('failed-precondition', 'This shop can’t take payments yet.');

  let deliveryMinor = 0;
  let quote: FirebaseFirestore.DocumentData | undefined;
  if (quoteId) {
    quote = (await db().collection('delivery_quotes').doc(quoteId).get()).data();
    if (!quote || quote.uid !== me || quote.productId !== productId) throw new HttpsError('invalid-argument', 'Please refresh the delivery price.');
    if ((quote.expiresAt as Timestamp).toMillis() < Date.now()) throw new HttpsError('deadline-exceeded', 'The delivery price expired. Please refresh it.');
    deliveryMinor = toMinor(Number(quote.fee), currency);
  }
  const major = (m: number) => m / 10 ** exponent(currency);
  const grossItemsMinor = toMinor(unitPrice, currency) * qty;

  // Seller discount code on the items part (uses counted when the order is paid).
  let discountCode: string | null = null;
  let discountMinor = 0;
  const rawCode = normalizeCode(req.data?.code);
  if (rawCode) {
    const codeDoc = (await db().doc(`biz_shops/${sellerId}/codes/${rawCode}`).get()).data();
    try {
      const off = codeDiscount(
        codeDoc ? { ...codeDoc, endsAtMs: (codeDoc.endsAt as Timestamp | undefined)?.toMillis?.() } : null,
        major(grossItemsMinor), currency, Date.now(),
      );
      discountMinor = Math.min(toMinor(off, currency), grossItemsMinor);
      discountCode = rawCode;
    } catch (e) {
      if (e instanceof StoreRuleError) throw new HttpsError(e.code, e.message);
      throw e;
    }
  }
  const itemsMinor = grossItemsMinor - discountMinor;
  const totalMinor = itemsMinor + deliveryMinor;

  // The tracked share link that brought the buyer here, if any.
  const shareCode = validShareCode(req.data?.shareCode) ? (req.data.shareCode as string) : null;
  const orderRef = db().collection('orders').doc();
  await orderRef.set({
    buyerId: me,
    sellerId,
    participants: [me, sellerId],
    productId,
    productName: String(product.name || product.title || 'Item').slice(0, 120),
    imageUrl: typeof product.imageUrl === 'string' ? product.imageUrl : null,
    variantId: variant?.id ?? null,
    variantName: variant?.name ?? null,
    quantity: qty,
    currency,
    listPrice: price,
    unitPrice,
    dealPercent: deal?.percentOff ?? null,
    dealTitle: deal?.title ?? null,
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
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await countShare(shareCode, 'checkouts');
  return { orderId: orderRef.id, total: major(totalMinor), totalMinor, currency };
});

/**
 * Writes for a confirmed pay-in on an order (inside the intents transaction,
 * after its reads): stock off the shelf, handover code, delivery job, seller
 * notification. The escrow ledger posting is written by the caller.
 */
export function applyOrderPaid(
  tx: Transaction,
  orderId: string,
  o: FirebaseFirestore.DocumentData,
  product: FirebaseFirestore.DocumentData | undefined,
  intentId: string,
): void {
  const ref = db().collection('orders').doc(orderId);
  let stockShortfall = false;
  if (product) {
    const s = stockAfterSale(product, o.variantId ?? null, Number(o.quantity) || 1);
    stockShortfall = s.shortfall;
    if (Object.keys(s.update).length) tx.update(db().collection('products').doc(String(o.productId)), { ...s.update, updatedAt: FieldValue.serverTimestamp() });
  }
  if (typeof o.discountCode === 'string' && o.discountCode) {
    // merge: a code the seller deleted meanwhile must not fail the payment.
    tx.set(db().doc(`biz_shops/${o.sellerId}/codes/${o.discountCode}`), { uses: FieldValue.increment(1) }, { merge: true });
  }
  if (validShareCode(o.shareCode)) {
    tx.set(db().collection('share_links').doc(o.shareCode), {
      purchases: FieldValue.increment(1),
      revenueMinor: { [orderCurrency(o)]: FieldValue.increment(Number(o.totalMinor) || 0) },
    }, { merge: true });
  }
  tx.update(ref, {
    stockShortfall,
    status: 'paid',
    payIntentId: intentId,
    paidAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  // The rider shows this code (QR) at handover; the buyer scans or types it.
  tx.set(db().collection('order_secrets').doc(orderId), {
    orderId, sellerId: o.sellerId, riderId: null,
    handoverCode: String(crypto.randomInt(1000, 10000)),
    createdAt: FieldValue.serverTimestamp(),
  });
  if (o.delivery) {
    tx.set(db().collection('delivery_jobs').doc(orderId), {
      orderId, status: 'open', pickup: o.delivery.pickup, dropoff: o.delivery.dropoff,
      distanceKm: o.delivery.distanceKm, durationMin: o.delivery.durationMin,
      payout: o.deliveryFee, currency: o.currency, productName: o.productName,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  tx.set(db().collection('notifications').doc(`order_paid_${orderId}`), {
    userId: o.sellerId, recipientId: o.sellerId, actorId: o.buyerId, category: 'system', priority: 'high', type: 'commerce',
    title: stockShortfall ? 'New order — check stock' : 'New order',
    body: stockShortfall
      ? `${o.quantity} × ${o.productName} is paid, but your listed stock ran out. Confirm you can fill it or cancel.`
      : `${o.quantity} × ${o.productName}${o.variantName ? ` (${o.variantName})` : ''} is paid. Get it ready for pickup.`,
    deepLink: `/biz/orders/${orderId}`, isRead: false, createdAt: FieldValue.serverTimestamp(),
  });
  // Buyer's receipt.
  tx.set(db().collection('notifications').doc(`order_receipt_${orderId}`), {
    userId: o.buyerId, recipientId: o.buyerId, actorId: o.sellerId, category: 'system', priority: 'normal', type: 'commerce',
    title: 'Payment received',
    body: `${o.productName} is paid and held safely until you confirm delivery.`,
    deepLink: `/biz/orders/${orderId}`, isRead: false, createdAt: FieldValue.serverTimestamp(),
  });
}

// ───────────────────────────── Delivery flow ─────────────────────────────

async function orderFor(orderId: unknown) {
  const id = String(orderId ?? '');
  if (!id || id.includes('/')) throw new HttpsError('invalid-argument', 'Missing order.');
  const ref = db().collection('orders').doc(id);
  const o = (await ref.get()).data();
  if (!o) throw new HttpsError('not-found', 'Order not found.');
  return { ref, o, id };
}

/** A delivery partner takes a paid order. */
export const acceptDelivery = onCall(async (req) => {
  const me = uid(req);
  const { ref, id } = await orderFor(req.data?.orderId);
  const user = (await db().collection('users').doc(me).get()).data();
  if (user?.deliveryPartner !== true) throw new HttpsError('permission-denied', 'Turn on delivery partner mode first.');
  if (!(await canReceive(me))) throw new HttpsError('failed-precondition', 'Verify your identity and add a payout method first.');
  await db().runTransaction(async (tx) => {
    const o = (await tx.get(ref)).data();
    if (!o || o.status !== 'paid' || o.riderId) throw new HttpsError('failed-precondition', 'Someone else took this delivery.');
    if (o.buyerId === me || o.sellerId === me) throw new HttpsError('failed-precondition', 'You can’t deliver your own order.');
    tx.update(ref, { riderId: me, participants: FieldValue.arrayUnion(me), status: 'assigned', assignedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    tx.update(db().collection('order_secrets').doc(id), { riderId: me });
    tx.set(db().collection('delivery_jobs').doc(id), { status: 'taken', riderId: me, takenAt: FieldValue.serverTimestamp() }, { merge: true });
  });
  return { ok: true };
});

/** The rider has the goods and starts the trip. */
export const startJourney = onCall(async (req) => {
  const me = uid(req);
  const { ref, o } = await orderFor(req.data?.orderId);
  if (o.riderId !== me) throw new HttpsError('permission-denied', 'This isn’t your delivery.');
  if (o.status !== 'assigned') throw new HttpsError('failed-precondition', 'This delivery can’t start now.');
  await ref.update({ status: 'in_transit', pickedUpAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  return { ok: true };
});

/** The buyer confirms they have the goods with the handover code; the escrow is released. */
export const confirmDelivery = onCall(async (req) => {
  const me = uid(req);
  const { ref, o, id } = await orderFor(req.data?.orderId);
  if (o.buyerId !== me) throw new HttpsError('permission-denied', 'Only the buyer can confirm delivery.');
  const okStatus = o.delivery ? ['in_transit', 'assigned'] : ['paid'];
  if (!okStatus.includes(o.status)) throw new HttpsError('failed-precondition', 'This order can’t be confirmed now.');
  const secret = (await db().collection('order_secrets').doc(id).get()).data();
  const code = String(req.data?.code ?? '').trim();
  if (!secret || !code || !crypto.timingSafeEqual(Buffer.from(code.padEnd(8)), Buffer.from(String(secret.handoverCode).padEnd(8)))) {
    throw new HttpsError('invalid-argument', 'That code doesn’t match. Ask the rider to show it again.');
  }

  // One transaction: the status check, the release and the balances, so a
  // double tap can't pay twice.
  const release = ledgerRef(`release_${id}`);
  await db().runTransaction(async (tx) => {
    const [cur, done] = await Promise.all([tx.get(ref), tx.get(release)]);
    const c = cur.data();
    if (!c || !okStatus.includes(c.status)) throw new HttpsError('failed-precondition', 'Already confirmed.');
    const m = orderMinor(c);
    const split = orderSplit(m.items, m.delivery, Number(c.commissionPercent ?? commissionPercent()));
    const riderGets = c.riderId ? split.rider : 0;
    const lines: LedgerLine[] = [
      { account: `escrow:${id}`, currency: m.currency, amountMinor: -m.total },
      { account: `user:${c.sellerId}`, currency: m.currency, amountMinor: split.seller, bucket: 'available' },
      ...(riderGets ? [{ account: `user:${c.riderId}`, currency: m.currency, amountMinor: riderGets, bucket: 'available' as const }] : []),
      // No rider (pickup in person): the delivery part stays with the platform.
      { account: 'platform:revenue', currency: m.currency, amountMinor: split.platform + (split.rider - riderGets) },
    ];
    writeLedger(tx, release.id, done.exists, 'order_release', lines.filter((l) => l.amountMinor !== 0), { orderId: id });
    tx.update(ref, {
      status: 'completed',
      sellerEarnedMinor: split.seller,
      riderEarnedMinor: riderGets,
      deliveredAt: FieldValue.serverTimestamp(),
      releasedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(db().collection('notifications').doc(`order_done_${id}`), {
      userId: c.sellerId, recipientId: c.sellerId, actorId: me, category: 'system', priority: 'high', type: 'commerce',
      title: 'Order delivered — money is yours',
      body: `${c.productName} was delivered. Your earnings are in your Oneova balance, ready to withdraw.`,
      deepLink: '/biz/payouts', isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});

/** Buyer or seller cancels before pickup: the payment is returned. */
export const cancelOrder = onCall(async (req) => {
  const me = uid(req);
  const { ref, o } = await orderFor(req.data?.orderId);
  if (o.buyerId !== me && o.sellerId !== me) throw new HttpsError('permission-denied', 'This isn’t your order.');
  if (o.status === 'awaiting_payment' || o.status === 'payment_failed') {
    if (o.payIntentId) {
      await db().doc(`pay_intents/${o.payIntentId}`).set({ cancelRequested: true }, { merge: true }).catch(() => undefined);
    }
    await ref.update({ status: 'cancelled', cancelledBy: me, updatedAt: FieldValue.serverTimestamp() });
    return { ok: true, refunded: false };
  }
  if (!['paid', 'assigned'].includes(o.status)) {
    throw new HttpsError('failed-precondition', 'This order is already on its way, so it can’t be cancelled here.');
  }
  await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur || !['paid', 'assigned'].includes(cur.status)) throw new HttpsError('failed-precondition', 'Already changed.');
    tx.update(ref, { status: 'refunding', cancelledBy: me, updatedAt: FieldValue.serverTimestamp() });
    tx.set(db().collection('delivery_jobs').doc(ref.id), { status: 'cancelled' }, { merge: true });
  });
  const { refundIntent } = await import('../pay/intents');
  const r = await refundIntent(String(o.payIntentId ?? ''), `order_${ref.id}`);
  logger.info('order refund', ref.id, r);
  await ref.update({ status: r === 'review' ? 'refund_review' : 'refunded', updatedAt: FieldValue.serverTimestamp() });
  return { ok: true, refunded: r !== 'review' };
});
