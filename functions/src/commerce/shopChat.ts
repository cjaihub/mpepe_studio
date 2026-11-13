/**
 * Product questions on a shop stage, answered by Ova with the seller watching.
 *
 *   biz_shops/{shopId}/chats/{buyerId}            one conversation per buyer
 *   biz_shops/{shopId}/chats/{buyerId}/messages   from: buyer | ova | seller
 *
 * shopChatSend stores the buyer's message and, unless the seller has taken
 * the conversation over (`takenOver`), has Ova answer from the shop's own
 * catalog. The seller reads every conversation live, can take over at any
 * time and then answers directly (rules let the shop owner write seller
 * messages and flip `takenOver`); Ova stays quiet until they hand it back.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { generateVertexContent } from '../vertexAi';

const db = () => getFirestore();
const PER_HOUR = 40;

const idOk = (v: unknown): v is string => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);

export const shopChatSend = onCall({ timeoutSeconds: 60 }, async (req) => {
  const me = req.auth?.uid;
  if (!me) throw new HttpsError('unauthenticated', 'Sign in first.');
  const shopId = req.data?.shopId;
  const productId = req.data?.productId;
  const text = String(req.data?.text ?? '').trim().slice(0, 500);
  if (!idOk(shopId) || (productId != null && !idOk(productId)) || !text) throw new HttpsError('invalid-argument', 'Write a question first.');
  if (shopId === me) throw new HttpsError('failed-precondition', 'This is your own shop.');

  const hour = new Date().toISOString().slice(0, 13);
  const limitRef = db().doc(`rateLimits/shopchat_${me}_${hour}`);
  if (Number((await limitRef.get()).get('count') ?? 0) >= PER_HOUR) {
    throw new HttpsError('resource-exhausted', 'You’re sending a lot of questions. Try again in a little while.');
  }
  await limitRef.set({ count: FieldValue.increment(1), expireAt: new Date(Date.now() + 2 * 3600_000) }, { merge: true });

  const [shopSnap, userSnap, productSnap] = await Promise.all([
    db().collection('biz_shops').doc(shopId).get(),
    db().collection('users').doc(me).get(),
    productId ? db().collection('products').doc(productId).get() : Promise.resolve(null),
  ]);
  const shop = shopSnap.data();
  if (!shop || shop.status !== 'open') throw new HttpsError('not-found', 'This shop is not open.');
  const product = productSnap?.exists && productSnap.get('ownerId') === shopId ? productSnap.data()! : null;

  const chatRef = db().doc(`biz_shops/${shopId}/chats/${me}`);
  const chat = await chatRef.get();
  const takenOver = chat.get('takenOver') === true;
  const buyerName = String(userSnap.get('displayName') || userSnap.get('username') || 'Buyer').slice(0, 60);
  const messages = chatRef.collection('messages');
  await messages.add({ from: 'buyer', text, productId: productId ?? null, at: FieldValue.serverTimestamp() });
  await chatRef.set({
    buyerId: me, buyerName, buyerAvatar: userSnap.get('photoUrl') || userSnap.get('avatarUrl') || null,
    productId: productId ?? null, productName: product ? String(product.name ?? '').slice(0, 120) : null,
    lastText: text, lastFrom: 'buyer', unreadSeller: FieldValue.increment(1), takenOver,
    updatedAt: FieldValue.serverTimestamp(), ...(chat.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
  }, { merge: true });
  if (takenOver) return { reply: null, takenOver: true };

  const history = (await messages.orderBy('at', 'desc').limit(9).get()).docs.reverse()
    .map((d) => `${d.get('from') === 'buyer' ? 'Shopper' : d.get('from') === 'seller' ? 'Seller' : 'Ova'}: ${String(d.get('text')).slice(0, 300)}`);
  const catalog = (await db().collection('products').where('ownerId', '==', shopId).limit(30).get()).docs
    .filter((d) => d.get('active') !== false)
    .map((d) => {
      const p = d.data();
      const options = Array.isArray(p.variants) ? p.variants.map((v: any) => `${v.name}${typeof v.stock === 'number' ? ` (${v.stock} left)` : ''}`).join(', ') : '';
      return `- ${p.name}: ${String(p.currency ?? 'usd').toUpperCase()} ${p.price}${p.inStock === false ? ', sold out' : typeof p.stock === 'number' ? `, ${p.stock} in stock` : ''}${options ? `; options: ${options}` : ''}`;
    });
  const prompt = [
    `You are Ova, the shopping assistant in the "${String(shop.name).slice(0, 60)}" shop on Oneova. The seller can read this chat and may join it.`,
    'Answer the shopper in one to three short, friendly sentences, in the shopper\'s language, using only the facts below.',
    'If the facts do not answer the question (shipping times, exact sizes, materials you are not told), say you are asking the seller to confirm and they will reply here. Never invent prices, stock, sizes or delivery promises.',
    product ? `The shopper is looking at: ${product.name}. ${String(product.description ?? '').slice(0, 700)} Category: ${product.category ?? ''}.` : '',
    `Shop: ${String(shop.tagline ?? '')} ${String(shop.bio ?? '').slice(0, 300)}`,
    shop.policies?.returns ? `Returns: ${String(shop.policies.returns).slice(0, 300)}` : '',
    shop.policies?.shipping ? `Shipping: ${String(shop.policies.shipping).slice(0, 300)}` : '',
    `Products:\n${catalog.join('\n')}`,
    `Conversation:\n${history.join('\n')}`,
    'Ova:',
  ].filter(Boolean).join('\n');

  let reply = '';
  try {
    const res = await generateVertexContent({ contents: [{ role: 'user', parts: [{ text: prompt }] }], config: { temperature: 0.4, maxOutputTokens: 220 } });
    reply = String(res.text ?? '').trim().slice(0, 700);
  } catch (e: any) {
    logger.warn('shop chat reply failed', e?.message ?? e);
  }
  if (!reply) reply = 'I’ve passed your question to the seller. They’ll reply here.';
  // The seller may have taken over while Ova was thinking.
  if ((await chatRef.get()).get('takenOver') === true) return { reply: null, takenOver: true };
  await messages.add({ from: 'ova', text: reply, productId: productId ?? null, at: FieldValue.serverTimestamp() });
  await chatRef.set({ lastText: reply, lastFrom: 'ova', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { reply, takenOver: false };
});
