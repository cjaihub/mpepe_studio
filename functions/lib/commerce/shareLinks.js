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
exports.shareLinkOpen = exports.shareLinkEvent = exports.shareLinkCreate = void 0;
exports.countShare = countShare;
/**
 * Tracked share links for shops and products: https://oneova.web.app/s/{code}
 *
 *   shareLinkCreate   one code per sharer per product / shop
 *   shareLinkOpen     the web page behind the link (Hosting rewrite /s/**):
 *                     counts the click, shows a preview, opens the app on the
 *                     product and sends people without the app to the store
 *   shareLinkEvent    the app reports that the link was opened inside it
 *
 * The code travels with the buyer (`?ref=`) to checkout, so every link shows
 * the whole path: clicks → opened in app → checkouts → paid orders
 * (orderEscrow.ts counts the last two).
 *
 * Buying happens only in the app; the web page never takes payment.
 */
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const shareLogic_1 = require("./shareLogic");
const db = () => (0, firestore_1.getFirestore)();
const SITE = 'https://oneova.web.app';
const PACKAGE = 'com.oneova.app';
const links = () => db().collection('share_links');
exports.shareLinkCreate = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    var _d;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const type = (_b = req.data) === null || _b === void 0 ? void 0 : _b.type;
    const targetId = (_c = req.data) === null || _c === void 0 ? void 0 : _c.targetId;
    if (!(0, shareLogic_1.validShareTarget)(type, targetId))
        throw new https_1.HttpsError('invalid-argument', 'Nothing to share.');
    const indexRef = db().doc(`share_link_index/${uid}_${type}_${targetId}`);
    const known = (await indexRef.get()).get('code');
    if ((0, shareLogic_1.validShareCode)(known))
        return { code: known, url: `${SITE}/s/${known}` };
    const target = await db().collection(type === 'product' ? 'products' : 'biz_shops').doc(targetId).get();
    if (!target.exists)
        throw new https_1.HttpsError('not-found', 'This is no longer available.');
    const sellerId = type === 'product' ? String((_d = target.get('ownerId')) !== null && _d !== void 0 ? _d : '') : targetId;
    const code = (0, shareLogic_1.newShareCode)();
    await links().doc(code).create({
        type, targetId, sellerId, createdBy: uid,
        clicks: 0, opens: 0, checkouts: 0, purchases: 0,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await indexRef.set({ code, createdAt: firestore_1.FieldValue.serverTimestamp() });
    return { code, url: `${SITE}/s/${code}` };
});
exports.shareLinkEvent = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const code = (_b = req.data) === null || _b === void 0 ? void 0 : _b.code;
    if (!(0, shareLogic_1.validShareCode)(code))
        return { ok: false };
    const seen = db().doc(`share_link_seen/${code}_${uid}`);
    const counted = await db().runTransaction(async (tx) => {
        const [link, s] = await Promise.all([tx.get(links().doc(code)), tx.get(seen)]);
        if (!link.exists || s.exists || link.get('createdBy') === uid)
            return false;
        tx.set(seen, { at: firestore_1.FieldValue.serverTimestamp() });
        tx.update(link.ref, { opens: firestore_1.FieldValue.increment(1), lastOpenAt: firestore_1.FieldValue.serverTimestamp() });
        return true;
    });
    return { ok: true, counted };
});
/** Called by checkout and the paid-order handler. Never throws. */
async function countShare(code, field, amountMinor = 0, currency = '') {
    if (!(0, shareLogic_1.validShareCode)(code))
        return;
    await links().doc(code).update(Object.assign({ [field]: firestore_1.FieldValue.increment(1) }, (field === 'purchases' && currency ? { [`revenueMinor.${currency}`]: firestore_1.FieldValue.increment(amountMinor) } : {}))).catch((e) => { var _a; return logger.warn('share count failed', code, (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e); });
}
async function previewOf(type, targetId) {
    var _a, _b, _c, _d, _e, _f, _g;
    if (type === 'product') {
        const p = (await db().collection('products').doc(targetId).get()).data();
        if (!p || p.active === false)
            return null;
        const price = typeof p.price === 'number' && p.price > 0 ? `${String((_a = p.currency) !== null && _a !== void 0 ? _a : 'usd').toUpperCase()} ${p.price.toLocaleString('en-US')}` : '';
        return {
            title: String((_c = (_b = p.name) !== null && _b !== void 0 ? _b : p.title) !== null && _c !== void 0 ? _c : 'Product').slice(0, 120),
            text: String((_d = p.description) !== null && _d !== void 0 ? _d : '').slice(0, 180),
            image: typeof p.imageUrl === 'string' && p.imageUrl.startsWith('https://') ? p.imageUrl : '',
            price,
        };
    }
    const s = (await db().collection('biz_shops').doc(targetId).get()).data();
    if (!s || s.status !== 'open')
        return null;
    return {
        title: String((_e = s.name) !== null && _e !== void 0 ? _e : 'Shop').slice(0, 60),
        text: String((_g = (_f = s.tagline) !== null && _f !== void 0 ? _f : s.bio) !== null && _g !== void 0 ? _g : '').slice(0, 180),
        image: typeof s.bannerUrl === 'string' && s.bannerUrl.startsWith('https://') ? s.bannerUrl
            : (typeof s.avatarUrl === 'string' && s.avatarUrl.startsWith('https://') ? s.avatarUrl : ''),
        price: '',
    };
}
function page(code, type, targetId, p, platform) {
    const route = (0, shareLogic_1.shareRoute)(type, targetId, code);
    const store = `https://play.google.com/store/apps/details?id=${PACKAGE}&referrer=${encodeURIComponent(`share=${code}`)}`;
    // Android opens the app on the product; without the app the same link lands on the store.
    const intent = `intent://app${route}#Intent;scheme=oneova;package=${PACKAGE};S.browser_fallback_url=${encodeURIComponent(store)};end`;
    const scheme = `oneova://app${route}`;
    const open = platform === 'android' ? intent : scheme;
    const title = (0, shareLogic_1.escapeHtml)(p ? `${p.title} on Oneova` : 'Oneova');
    const desc = (0, shareLogic_1.escapeHtml)(p ? [p.price, p.text].filter(Boolean).join(' · ') || 'See it in 3D on Oneova.' : 'This is no longer available.');
    const image = (p === null || p === void 0 ? void 0 : p.image) ? (0, shareLogic_1.escapeHtml)(p.image) : `${SITE}/favicon.png`;
    const auto = p && (platform === 'android' || platform === 'ios');
    return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<meta name="description" content="${desc}">
<meta property="og:type" content="${type === 'product' ? 'product' : 'website'}">
<meta property="og:site_name" content="Oneova">
<meta property="og:title" content="${title}">
<meta property="og:description" content="${desc}">
<meta property="og:image" content="${image}">
<meta property="og:url" content="${SITE}/s/${code}">
<meta name="twitter:card" content="summary_large_image">
<meta name="robots" content="noindex">
<style>
:root{--blue:#0C4FA8;--bg:#fff;--card:#F8FAFC;--line:#E2E8F0;--text:#0F172A;--muted:#475569}
@media(prefers-color-scheme:dark){:root{--bg:#0A0A0A;--card:#141414;--line:#262626;--text:#F3F4F6;--muted:#9CA3AF}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center;padding:16px}
.c{width:100%;max-width:380px;background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden}
.i{width:100%;aspect-ratio:1;object-fit:cover;display:block;background:var(--line)}
.b{padding:14px 16px 16px}.k{font-size:10px;font-weight:800;letter-spacing:.8px;color:var(--blue)}
h1{font-size:18px;line-height:1.25;margin:4px 0 2px;letter-spacing:-.3px}.p{font-weight:700;margin:2px 0}.d{color:var(--muted);font-size:13px;margin:4px 0 14px}
a.btn{display:block;text-align:center;text-decoration:none;font-weight:700;border-radius:12px;padding:11px 16px;font-size:14px}
a.pri{background:var(--blue);color:#fff}a.sec{color:var(--text);border:1px solid var(--line);margin-top:8px}
.n{color:var(--muted);font-size:11.5px;text-align:center;margin-top:10px}
</style></head><body><main class="c">
${(p === null || p === void 0 ? void 0 : p.image) ? `<img class="i" src="${(0, shareLogic_1.escapeHtml)(p.image)}" alt="">` : ''}
<div class="b"><div class="k">ONEOVA 3D SHOPS</div>
<h1>${(0, shareLogic_1.escapeHtml)(p ? p.title : 'This is no longer available')}</h1>
${(p === null || p === void 0 ? void 0 : p.price) ? `<div class="p">${(0, shareLogic_1.escapeHtml)(p.price)}</div>` : ''}
<p class="d">${(0, shareLogic_1.escapeHtml)(p ? (p.text || 'Rotate it, zoom in and place it in your room before you buy.') : 'The seller may have removed it. Open Oneova to find more.')}</p>
${platform === 'desktop'
        ? `<a class="btn pri" href="${store}">Get Oneova for Android</a><div class="n">Open this link on your phone to see it in 3D and buy in the app.</div>`
        : `<a class="btn pri" id="open" href="${(0, shareLogic_1.escapeHtml)(open)}">Open in Oneova</a><a class="btn sec" href="${store}">Get the app</a><div class="n">3D view, live shopping and checkout are in the app.</div>`}
</div></main>
${auto ? `<script>
(function(){var open=${JSON.stringify(open)},store=${JSON.stringify(store)},android=${JSON.stringify(platform === 'android')};
 if(sessionStorage.getItem('o')) return; sessionStorage.setItem('o','1');
 var t=Date.now(); location.href=open;
 if(!android) setTimeout(function(){ if(!document.hidden && Date.now()-t<2600) location.href=store; },1800);
})();
</script>` : ''}
</body></html>`;
}
exports.shareLinkOpen = (0, https_1.onRequest)({ memory: '256MiB', maxInstances: 20 }, async (req, res) => {
    var _a, _b;
    const code = req.path.split('/').filter(Boolean).pop();
    if (!(0, shareLogic_1.validShareCode)(code)) {
        res.redirect(302, SITE);
        return;
    }
    const platform = (0, shareLogic_1.sharePlatform)(String((_a = req.headers['user-agent']) !== null && _a !== void 0 ? _a : ''));
    try {
        const link = await links().doc(code).get();
        if (!link.exists) {
            res.redirect(302, SITE);
            return;
        }
        const type = link.get('type');
        const targetId = String(link.get('targetId'));
        const preview = await previewOf(type, targetId);
        if (platform !== 'bot') {
            const day = new Date().toISOString().slice(0, 10).replace(/-/g, '');
            await link.ref.update({
                clicks: firestore_1.FieldValue.increment(1),
                [`platforms.${platform}`]: firestore_1.FieldValue.increment(1),
                [`days.${day}`]: firestore_1.FieldValue.increment(1),
                lastClickAt: firestore_1.FieldValue.serverTimestamp(),
            }).catch(() => undefined);
        }
        res.set('Cache-Control', 'private, no-store');
        res.status(preview ? 200 : 404).send(page(code, type, targetId, preview, platform));
    }
    catch (e) {
        logger.error('share link failed', code, (_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : e);
        res.redirect(302, SITE);
    }
});
//# sourceMappingURL=shareLinks.js.map