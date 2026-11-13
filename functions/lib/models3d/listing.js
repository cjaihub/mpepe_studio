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
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.shopListingDraft = void 0;
exports.ownPhotoPath = ownPhotoPath;
/**
 * shopListingDraft: the seller adds photos, Ova writes the listing.
 *
 * Gemini (Vertex AI) looks at up to four of the seller's own product photos
 * together with their shop profile and returns the name, description,
 * category, colours, tags and a price band in the seller's currency. Prices
 * of similar products already on Oneova outrank the model's estimate when
 * there are enough of them (listingLogic.priceBand).
 *
 * Everything returned is a suggestion the seller confirms; nothing is saved
 * here.
 */
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const vertexAi_1 = require("../vertexAi");
const listingLogic_1 = require("./listingLogic");
const db = () => (0, firestore_1.getFirestore)();
const DAILY_LIMIT = 80;
/** Storage path of one of the caller's own shop or model photos, or null. */
function ownPhotoPath(url, uid) {
    if (typeof url !== 'string' || !url.startsWith('https://firebasestorage.googleapis.com/'))
        return null;
    const m = /\/o\/([^?]+)/.exec(url);
    if (!m)
        return null;
    let path;
    try {
        path = decodeURIComponent(m[1]);
    }
    catch (_a) {
        return null;
    }
    return path.startsWith(`shops/${uid}/products/`) || path.startsWith(`users/${uid}/models3d/`) ? path : null;
}
const SCHEMA = {
    type: 'OBJECT',
    properties: {
        name: { type: 'STRING' },
        description: { type: 'STRING' },
        category: { type: 'STRING' },
        condition: { type: 'STRING', enum: ['new', 'used', 'refurbished'] },
        material: { type: 'STRING' },
        colors: { type: 'ARRAY', items: { type: 'OBJECT', properties: { name: { type: 'STRING' }, hex: { type: 'STRING' } }, required: ['name', 'hex'] } },
        tags: { type: 'ARRAY', items: { type: 'STRING' } },
        price: { type: 'OBJECT', properties: { low: { type: 'NUMBER' }, typical: { type: 'NUMBER' }, high: { type: 'NUMBER' } }, required: ['low', 'typical', 'high'] },
        confidence: { type: 'NUMBER' },
        photoTip: { type: 'STRING' },
    },
    required: ['name', 'description', 'category', 'confidence'],
};
exports.shopListingDraft = (0, https_1.onCall)({ memory: '1GiB', timeoutSeconds: 90 }, async (req) => {
    var _a, _b, _c, _d, _e;
    var _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const paths = (Array.isArray((_b = req.data) === null || _b === void 0 ? void 0 : _b.imageUrls) ? req.data.imageUrls : [])
        .map((u) => ownPhotoPath(u, uid)).filter((p) => !!p).slice(0, 4);
    if (paths.length === 0)
        throw new https_1.HttpsError('invalid-argument', 'Add a photo first.');
    const currency = String((_f = (_c = req.data) === null || _c === void 0 ? void 0 : _c.currency) !== null && _f !== void 0 ? _f : 'USD').toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency))
        throw new https_1.HttpsError('invalid-argument', 'Unknown currency.');
    const country = String((_g = (_d = req.data) === null || _d === void 0 ? void 0 : _d.country) !== null && _g !== void 0 ? _g : '').toUpperCase().slice(0, 2);
    const hint = String((_h = (_e = req.data) === null || _e === void 0 ? void 0 : _e.hint) !== null && _h !== void 0 ? _h : '').trim().slice(0, 200);
    const day = new Date().toISOString().slice(0, 10);
    const limitRef = db().doc(`rateLimits/listing_${uid}_${day}`);
    const used = Number((_j = (await limitRef.get()).get('count')) !== null && _j !== void 0 ? _j : 0);
    if (used >= DAILY_LIMIT)
        throw new https_1.HttpsError('resource-exhausted', 'You’ve used today’s AI drafts. Fill this one in by hand or try tomorrow.');
    await limitRef.set({ count: firestore_1.FieldValue.increment(1), expireAt: new Date(Date.now() + 2 * 86400000) }, { merge: true });
    const shop = (_k = (await db().collection('biz_shops').doc(uid).get()).data()) !== null && _k !== void 0 ? _k : {};
    const images = await Promise.all(paths.map(async (p) => {
        const file = (0, storage_1.getStorage)().bucket().file(p);
        const [[meta], [bytes]] = await Promise.all([file.getMetadata(), file.download()]);
        return { inlineData: { mimeType: String(meta.contentType || 'image/jpeg'), data: bytes.toString('base64') } };
    }));
    const prompt = [
        'You write product listings for a seller on Oneova, a shopping app.',
        'Look at the photos (all of the same product) and describe exactly what is shown. Do not invent a brand, model number, size or material you cannot see; leave a field empty instead.',
        `Shop: ${String((_l = shop.name) !== null && _l !== void 0 ? _l : '').slice(0, 60)}. ${String((_m = shop.tagline) !== null && _m !== void 0 ? _m : '').slice(0, 90)} Categories: ${(Array.isArray(shop.categories) ? shop.categories : []).join(', ')}.`,
        country ? `The seller is in country ${country} and sells in ${currency}.` : `The seller sells in ${currency}.`,
        hint ? `The seller says: "${hint}".` : '',
        'Return:',
        '- name: a clear product title, under 70 characters, no emojis, no ALL CAPS.',
        '- description: 2 to 4 short sentences a buyer needs (what it is, material, look, use). Plain text.',
        '- category: one or two words (e.g. Sneakers, Handbags, Phone cases).',
        '- colors: the product\'s own colours as it appears (name + 6-digit hex), most dominant first, at most 4.',
        '- tags: up to 8 search words, lowercase.',
        `- price: what this kind of product typically sells for in that country, in ${currency} (low, typical, high). Leave it out if you cannot tell.`,
        '- confidence: 0 to 1, how sure you are about what the product is.',
        '- photoTip: one short tip only if the photo would hurt sales or 3D capture (dark, cluttered, cropped); otherwise empty.',
    ].filter(Boolean).join('\n');
    let draft;
    try {
        const res = await (0, vertexAi_1.generateVertexContent)({
            contents: [{ role: 'user', parts: [...images, { text: prompt }] }],
            config: { responseMimeType: 'application/json', responseSchema: SCHEMA, temperature: 0.3, maxOutputTokens: 1200 },
        });
        draft = (0, listingLogic_1.cleanListing)(JSON.parse((_o = res.text) !== null && _o !== void 0 ? _o : '{}'));
    }
    catch (e) {
        logger.error('listing draft failed', (_p = e === null || e === void 0 ? void 0 : e.message) !== null && _p !== void 0 ? _p : e);
        throw new https_1.HttpsError('unavailable', 'Ova couldn’t read these photos right now. Fill it in by hand or try again.');
    }
    if (!draft.name)
        throw new https_1.HttpsError('unavailable', 'Ova couldn’t tell what this is. Try a clearer photo.');
    // What similar products sell for on Oneova, in the same currency.
    let comparables = [];
    if (draft.category) {
        const snap = await db().collection('products')
            .where('category', '==', draft.category).where('currency', '==', currency.toLowerCase()).limit(60).get()
            .catch(() => null);
        comparables = ((_q = snap === null || snap === void 0 ? void 0 : snap.docs) !== null && _q !== void 0 ? _q : [])
            .filter((d) => d.get('ownerId') !== uid && d.get('active') !== false)
            .map((d) => Number(d.get('price'))).filter((n) => n > 0);
    }
    const { price } = draft, rest = __rest(draft, ["price"]);
    return Object.assign(Object.assign({}, rest), { currency, price: (0, listingLogic_1.priceBand)(price, comparables, currency) });
});
//# sourceMappingURL=listing.js.map