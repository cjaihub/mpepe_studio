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
import * as crypto from 'crypto';
import Stripe from 'stripe';
import { onCall, onRequest, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { optionalSecret } from '../optionalSecrets';

const db = () => getFirestore();
const RETURN_URL = 'https://oneova.web.app/';

/** Currencies Stripe charges without minor units. */
const ZERO_DECIMAL = new Set(['bif', 'clp', 'djf', 'gnf', 'jpy', 'kmf', 'krw', 'mga', 'pyg', 'rwf', 'ugx', 'vnd', 'vuv', 'xaf', 'xof', 'xpf']);
const minor = (amount: number, currency: string) =>
  ZERO_DECIMAL.has(currency) ? Math.round(amount) : Math.round(amount * 100);

/**
 * Motorbike delivery rates per currency: base + per km + per minute.
 * Rush hours (07–09, 17–20 local server time) add 20%.
 */
const RATES: Record<string, { base: number; perKm: number; perMin: number; min: number }> = {
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

async function stripe(): Promise<Stripe> {
  const key = await optionalSecret('STRIPE_SECRET_KEY');
  if (!key) throw new HttpsError('failed-precondition', 'Payments are being set up. Please try again soon.');
  return new Stripe(key, { apiVersion: '2025-02-24.acacia' });
}

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

// ───────────────────────────── Config ─────────────────────────────

/** Publishable key for the app's Payment Sheet (public by design). */
export const stripeConfig = onCall(async () => {
  const pk = (process.env.STRIPE_PUBLISHABLE_KEY ?? '').trim();
  return { publishableKey: pk.startsWith('pk_') ? pk : '', merchantName: 'Oneova' };
});

// ───────────────────────────── Payout accounts ─────────────────────────────

/** Creates (once) a Stripe Express account for a seller or rider and returns an onboarding link. */
export const stripeConnectOnboard = onCall(async (req) => {
  const me = uid(req);
  const s = await stripe();
  const ref = db().collection('payout_accounts').doc(me);
  let accountId = (await ref.get()).get('stripeAccountId') as string | undefined;
  if (!accountId) {
    const user = (await db().collection('users').doc(me).get()).data() ?? {};
    const country = typeof req.data?.country === 'string' && /^[A-Z]{2}$/.test(req.data.country) ? req.data.country : undefined;
    const acct = await s.accounts.create({
      type: 'express',
      country,
      email: typeof user.email === 'string' ? user.email : undefined,
      capabilities: { transfers: { requested: true } },
      business_profile: { product_description: 'Sells or delivers goods on Oneova Biz' },
      metadata: { uid: me },
    });
    accountId = acct.id;
    await ref.set({ uid: me, stripeAccountId: accountId, payoutsEnabled: false, detailsSubmitted: false, createdAt: FieldValue.serverTimestamp() }, { merge: true });
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
export const stripePayoutStatus = onCall(async (req) => {
  const me = uid(req);
  const ref = db().collection('payout_accounts').doc(me);
  const accountId = (await ref.get()).get('stripeAccountId') as string | undefined;
  if (!accountId) return { connected: false, payoutsEnabled: false };
  const acct = await (await stripe()).accounts.retrieve(accountId);
  const status = { payoutsEnabled: acct.payouts_enabled === true, detailsSubmitted: acct.details_submitted === true, transfersActive: acct.capabilities?.transfers === 'active' };
  await ref.set({ ...status, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { connected: true, ...status };
});

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

function deliveryFee(km: number, min: number, currency: string): number {
  const r = RATES[currency] ?? RATES.usd;
  const hour = new Date().getUTCHours();
  const rush = (hour >= 7 && hour < 9) || (hour >= 17 && hour < 20) ? 1.2 : 1;
  const fee = Math.max(r.min, (r.base + r.perKm * km + r.perMin * min) * rush);
  return ZERO_DECIMAL.has(currency) ? Math.round(fee) : Math.round(fee * 100) / 100;
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
  const currency = String(product.currency || 'usd').toLowerCase();
  const r = await route(pickup, dropoff);
  const fee = deliveryFee(r.km, r.min, currency);
  const ref = await db().collection('delivery_quotes').add({
    uid: me, productId, sellerId, pickup, dropoff, currency, fee,
    distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: r.polyline ?? null,
    expiresAt: Timestamp.fromMillis(Date.now() + 15 * 60_000), createdAt: FieldValue.serverTimestamp(),
  });
  return { quoteId: ref.id, fee, currency, distanceKm: Math.round(r.km * 10) / 10, durationMin: Math.round(r.min), polyline: r.polyline ?? null };
});

// ───────────────────────────── Checkout ─────────────────────────────

/** Creates the order and its PaymentIntent. The money is held on the platform until delivery. */
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
  const currency = String(product.currency || 'usd').toLowerCase();

  const seller = (await db().collection('payout_accounts').doc(sellerId).get()).data();
  if (!seller?.stripeAccountId || seller.payoutsEnabled !== true) {
    throw new HttpsError('failed-precondition', 'This shop can’t take payments yet.');
  }

  let delivery = 0;
  let quote: FirebaseFirestore.DocumentData | undefined;
  if (quoteId) {
    quote = (await db().collection('delivery_quotes').doc(quoteId).get()).data();
    if (!quote || quote.uid !== me || quote.productId !== productId) throw new HttpsError('invalid-argument', 'Please refresh the delivery price.');
    if ((quote.expiresAt as Timestamp).toMillis() < Date.now()) throw new HttpsError('deadline-exceeded', 'The delivery price expired. Please refresh it.');
    delivery = Number(quote.fee);
  }

  const items = price * qty;
  const total = items + delivery;
  const s = await stripe();

  const payRef = db().collection('payout_accounts').doc(me);
  let customer = (await payRef.get()).get('stripeCustomerId') as string | undefined;
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
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
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

export const stripeWebhook = onRequest(async (req, res) => {
  const secret = await optionalSecret('STRIPE_WEBHOOK_SECRET');
  if (!secret) {
    res.status(503).send('not configured');
    return;
  }
  let event: Stripe.Event;
  try {
    event = (await stripe()).webhooks.constructEvent(req.rawBody, String(req.headers['stripe-signature'] ?? ''), secret);
  } catch (e: any) {
    logger.warn('stripe webhook signature failed', e?.message);
    res.status(400).send('bad signature');
    return;
  }

  try {
    switch (event.type) {
      case 'payment_intent.succeeded': {
        const pi = event.data.object as Stripe.PaymentIntent;
        const orderId = pi.metadata?.orderId;
        if (!orderId) break;
        const ref = db().collection('orders').doc(orderId);
        await db().runTransaction(async (tx) => {
          const o = (await tx.get(ref)).data();
          if (!o || o.status !== 'awaiting_payment') return;
          tx.update(ref, {
            status: 'paid',
            chargeId: typeof pi.latest_charge === 'string' ? pi.latest_charge : pi.latest_charge?.id ?? null,
            paidAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          // The rider shows this code (QR) at handover; the buyer scans or types it.
          tx.set(db().collection('order_secrets').doc(orderId), {
            orderId, sellerId: o.sellerId, riderId: null,
            handoverCode: String(crypto.randomInt(1000, 10000)),
            createdAt: FieldValue.serverTimestamp(),
          });
          // Open job for delivery partners (no buyer details beyond the drop-off pin).
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
            title: 'New order', body: `${o.quantity} × ${o.productName} is paid. Get it ready for pickup.`,
            deepLink: `/biz/orders/${orderId}`, isRead: false, createdAt: FieldValue.serverTimestamp(),
          });
        });
        break;
      }
      case 'payment_intent.payment_failed': {
        const pi = event.data.object as Stripe.PaymentIntent;
        if (pi.metadata?.orderId) {
          await db().collection('orders').doc(pi.metadata.orderId).update({ status: 'payment_failed', updatedAt: FieldValue.serverTimestamp() }).catch(() => undefined);
        }
        break;
      }
      case 'account.updated': {
        const a = event.data.object as Stripe.Account;
        const owner = a.metadata?.uid;
        if (owner) {
          await db().collection('payout_accounts').doc(owner).set({
            payoutsEnabled: a.payouts_enabled === true,
            detailsSubmitted: a.details_submitted === true,
            transfersActive: a.capabilities?.transfers === 'active',
            updatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        break;
      }
    }
    res.status(200).send('ok');
  } catch (e: any) {
    logger.error('stripe webhook handling failed', event.type, e?.message ?? e);
    res.status(500).send('error');
  }
});

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
  const payout = (await db().collection('payout_accounts').doc(me).get()).data();
  const user = (await db().collection('users').doc(me).get()).data();
  if (user?.deliveryPartner !== true) throw new HttpsError('permission-denied', 'Turn on delivery partner mode first.');
  if (!payout?.stripeAccountId || payout.payoutsEnabled !== true) throw new HttpsError('failed-precondition', 'Set up your payout account first.');
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

  // Claim the release first so a double tap can't pay twice.
  await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur || !okStatus.includes(cur.status)) throw new HttpsError('failed-precondition', 'Already confirmed.');
    tx.update(ref, { status: 'releasing', deliveredAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  });

  const s = await stripe();
  const currency = String(o.currency);
  const sellerShare = Number(o.itemsAmount) * (1 - Number(o.commissionPercent ?? commissionPercent()) / 100);
  const [seller, rider] = await Promise.all([
    db().collection('payout_accounts').doc(o.sellerId).get().then((d) => d.data()),
    o.riderId ? db().collection('payout_accounts').doc(o.riderId).get().then((d) => d.data()) : Promise.resolve(undefined),
  ]);
  const transfers: Record<string, string> = {};
  try {
    if (seller?.stripeAccountId && sellerShare > 0) {
      transfers.seller = (await s.transfers.create({
        amount: minor(sellerShare, currency), currency, destination: seller.stripeAccountId,
        transfer_group: id, source_transaction: o.chargeId ?? undefined, metadata: { orderId: id, role: 'seller' },
      }, { idempotencyKey: `release_${id}_seller` })).id;
    }
    if (rider?.stripeAccountId && Number(o.deliveryFee) > 0) {
      transfers.rider = (await s.transfers.create({
        amount: minor(Number(o.deliveryFee), currency), currency, destination: rider.stripeAccountId,
        transfer_group: id, source_transaction: o.chargeId ?? undefined, metadata: { orderId: id, role: 'rider' },
      }, { idempotencyKey: `release_${id}_rider` })).id;
    }
    await ref.update({ status: 'completed', transfers, releasedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  } catch (e: any) {
    logger.error('escrow release failed', id, e?.message ?? e);
    await ref.update({ status: 'release_failed', transfers, releaseError: String(e?.message ?? e).slice(0, 300), updatedAt: FieldValue.serverTimestamp() });
    throw new HttpsError('internal', 'Delivery is confirmed. Paying the shop is taking longer than usual; our team will finish it.');
  }
  return { ok: true };
});

/** Buyer or seller cancels before pickup: full refund. */
export const cancelOrder = onCall(async (req) => {
  const me = uid(req);
  const { ref, o } = await orderFor(req.data?.orderId);
  if (o.buyerId !== me && o.sellerId !== me) throw new HttpsError('permission-denied', 'This isn’t your order.');
  if (o.status === 'awaiting_payment' || o.status === 'payment_failed') {
    await (await stripe()).paymentIntents.cancel(o.paymentIntentId).catch(() => undefined);
    await ref.update({ status: 'cancelled', cancelledBy: me, updatedAt: FieldValue.serverTimestamp() });
    return { ok: true, refunded: false };
  }
  if (!['paid', 'assigned'].includes(o.status)) {
    throw new HttpsError('failed-precondition', 'This order is already on its way, so it can’t be cancelled here.');
  }
  await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur || !['paid', 'assigned'].includes(cur.status)) throw new HttpsError('failed-precondition', 'Already changed.');
    tx.update(ref, { status: 'refunding', updatedAt: FieldValue.serverTimestamp() });
    tx.set(db().collection('delivery_jobs').doc(ref.id), { status: 'cancelled' }, { merge: true });
  });
  const refund = await (await stripe()).refunds.create({ payment_intent: o.paymentIntentId, metadata: { orderId: ref.id } }, { idempotencyKey: `refund_${ref.id}` });
  await ref.update({ status: 'refunded', refundId: refund.id, cancelledBy: me, updatedAt: FieldValue.serverTimestamp() });
  return { ok: true, refunded: true };
});
