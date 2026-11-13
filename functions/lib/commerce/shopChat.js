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
exports.shopChatSend = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const vertexAi_1 = require("../vertexAi");
const db = () => (0, firestore_1.getFirestore)();
const PER_HOUR = 40;
const idOk = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);
exports.shopChatSend = (0, https_1.onCall)({ timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c, _d, _e, _f;
    var _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const me = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!me)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const shopId = (_b = req.data) === null || _b === void 0 ? void 0 : _b.shopId;
    const productId = (_c = req.data) === null || _c === void 0 ? void 0 : _c.productId;
    const text = String((_g = (_d = req.data) === null || _d === void 0 ? void 0 : _d.text) !== null && _g !== void 0 ? _g : '').trim().slice(0, 500);
    if (!idOk(shopId) || (productId != null && !idOk(productId)) || !text)
        throw new https_1.HttpsError('invalid-argument', 'Write a question first.');
    if (shopId === me)
        throw new https_1.HttpsError('failed-precondition', 'This is your own shop.');
    const hour = new Date().toISOString().slice(0, 13);
    const limitRef = db().doc(`rateLimits/shopchat_${me}_${hour}`);
    if (Number((_h = (await limitRef.get()).get('count')) !== null && _h !== void 0 ? _h : 0) >= PER_HOUR) {
        throw new https_1.HttpsError('resource-exhausted', 'You’re sending a lot of questions. Try again in a little while.');
    }
    await limitRef.set({ count: firestore_1.FieldValue.increment(1), expireAt: new Date(Date.now() + 2 * 3600000) }, { merge: true });
    const [shopSnap, userSnap, productSnap] = await Promise.all([
        db().collection('biz_shops').doc(shopId).get(),
        db().collection('users').doc(me).get(),
        productId ? db().collection('products').doc(productId).get() : Promise.resolve(null),
    ]);
    const shop = shopSnap.data();
    if (!shop || shop.status !== 'open')
        throw new https_1.HttpsError('not-found', 'This shop is not open.');
    const product = (productSnap === null || productSnap === void 0 ? void 0 : productSnap.exists) && productSnap.get('ownerId') === shopId ? productSnap.data() : null;
    const chatRef = db().doc(`biz_shops/${shopId}/chats/${me}`);
    const chat = await chatRef.get();
    const takenOver = chat.get('takenOver') === true;
    const buyerName = String(userSnap.get('displayName') || userSnap.get('username') || 'Buyer').slice(0, 60);
    const messages = chatRef.collection('messages');
    await messages.add({ from: 'buyer', text, productId: productId !== null && productId !== void 0 ? productId : null, at: firestore_1.FieldValue.serverTimestamp() });
    await chatRef.set(Object.assign({ buyerId: me, buyerName, buyerAvatar: userSnap.get('photoUrl') || userSnap.get('avatarUrl') || null, productId: productId !== null && productId !== void 0 ? productId : null, productName: product ? String((_j = product.name) !== null && _j !== void 0 ? _j : '').slice(0, 120) : null, lastText: text, lastFrom: 'buyer', unreadSeller: firestore_1.FieldValue.increment(1), takenOver, updatedAt: firestore_1.FieldValue.serverTimestamp() }, (chat.exists ? {} : { createdAt: firestore_1.FieldValue.serverTimestamp() })), { merge: true });
    if (takenOver)
        return { reply: null, takenOver: true };
    const history = (await messages.orderBy('at', 'desc').limit(9).get()).docs.reverse()
        .map((d) => `${d.get('from') === 'buyer' ? 'Shopper' : d.get('from') === 'seller' ? 'Seller' : 'Ova'}: ${String(d.get('text')).slice(0, 300)}`);
    const catalog = (await db().collection('products').where('ownerId', '==', shopId).limit(30).get()).docs
        .filter((d) => d.get('active') !== false)
        .map((d) => {
        var _a;
        const p = d.data();
        const options = Array.isArray(p.variants) ? p.variants.map((v) => `${v.name}${typeof v.stock === 'number' ? ` (${v.stock} left)` : ''}`).join(', ') : '';
        return `- ${p.name}: ${String((_a = p.currency) !== null && _a !== void 0 ? _a : 'usd').toUpperCase()} ${p.price}${p.inStock === false ? ', sold out' : typeof p.stock === 'number' ? `, ${p.stock} in stock` : ''}${options ? `; options: ${options}` : ''}`;
    });
    const prompt = [
        `You are Ova, the shopping assistant in the "${String(shop.name).slice(0, 60)}" shop on Oneova. The seller can read this chat and may join it.`,
        'Answer the shopper in one to three short, friendly sentences, in the shopper\'s language, using only the facts below.',
        'If the facts do not answer the question (shipping times, exact sizes, materials you are not told), say you are asking the seller to confirm and they will reply here. Never invent prices, stock, sizes or delivery promises.',
        product ? `The shopper is looking at: ${product.name}. ${String((_k = product.description) !== null && _k !== void 0 ? _k : '').slice(0, 700)} Category: ${(_l = product.category) !== null && _l !== void 0 ? _l : ''}.` : '',
        `Shop: ${String((_m = shop.tagline) !== null && _m !== void 0 ? _m : '')} ${String((_o = shop.bio) !== null && _o !== void 0 ? _o : '').slice(0, 300)}`,
        ((_e = shop.policies) === null || _e === void 0 ? void 0 : _e.returns) ? `Returns: ${String(shop.policies.returns).slice(0, 300)}` : '',
        ((_f = shop.policies) === null || _f === void 0 ? void 0 : _f.shipping) ? `Shipping: ${String(shop.policies.shipping).slice(0, 300)}` : '',
        `Products:\n${catalog.join('\n')}`,
        `Conversation:\n${history.join('\n')}`,
        'Ova:',
    ].filter(Boolean).join('\n');
    let reply = '';
    try {
        const res = await (0, vertexAi_1.generateVertexContent)({ contents: [{ role: 'user', parts: [{ text: prompt }] }], config: { temperature: 0.4, maxOutputTokens: 220 } });
        reply = String((_p = res.text) !== null && _p !== void 0 ? _p : '').trim().slice(0, 700);
    }
    catch (e) {
        logger.warn('shop chat reply failed', (_q = e === null || e === void 0 ? void 0 : e.message) !== null && _q !== void 0 ? _q : e);
    }
    if (!reply)
        reply = 'I’ve passed your question to the seller. They’ll reply here.';
    // The seller may have taken over while Ova was thinking.
    if ((await chatRef.get()).get('takenOver') === true)
        return { reply: null, takenOver: true };
    await messages.add({ from: 'ova', text: reply, productId: productId !== null && productId !== void 0 ? productId : null, at: firestore_1.FieldValue.serverTimestamp() });
    await chatRef.set({ lastText: reply, lastFrom: 'ova', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    return { reply, takenOver: false };
});
//# sourceMappingURL=shopChat.js.map