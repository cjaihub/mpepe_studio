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
exports.arEffectFavoriteRemoved = exports.arEffectFavoriteAdded = exports.arEffectUse = exports.arEffectCreateFromUpload = exports.arEffectGenerate = exports.arMakeupSuggest = void 0;
exports.keywordsFor = keywordsFor;
exports.chromaKey = chromaKey;
/**
 * AR camera effects catalog (`ar_effects`).
 *
 * - arEffectGenerate: "type to create". Gemini on Vertex AI turns the prompt
 *   into an effect spec (anchor, scale, category, makeup colors) and, for
 *   sprites and scenes, Gemini image generation draws the asset on a flat key
 *   color that is keyed out here into a transparent PNG.
 * - arEffectCreateFromUpload: a user's own transparent PNG becomes an effect.
 * - arEffectUse: counts one use per user per effect per day (ranking).
 * - favorites: users/{uid}/ar_favorites/{effectId} docs (one per user by id)
 *   drive favoriteCount and score.
 *
 * Catalog docs are only ever written here; clients read them.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const auth_1 = require("firebase-admin/auth");
const pngjs_1 = require("pngjs");
const jpeg = __importStar(require("jpeg-js"));
const vertexAi_1 = require("./vertexAi");
const TEXT_MODEL = 'gemini-2.5-flash';
const IMAGE_MODEL = 'gemini-2.5-flash-image';
const FALLBACK_IMAGE_MODEL = 'imagen-4.0-fast-generate-001';
const DAILY_GENERATIONS = 25;
const MAX_SPRITE = 768;
const MAX_SCENE = 1440;
const KINDS = ['sprite', 'makeup', 'background'];
const CATEGORIES = [
    'glasses', 'eyes', 'makeup', 'hats', 'hair', 'beards', 'masks',
    'jewelry', 'clothes', 'stickers', 'world', 'backgrounds',
];
const ANCHORS = [
    'eyes', 'forehead', 'headTop', 'hair', 'nose', 'mouth', 'chin',
    'face', 'neck', 'torso', 'world', 'screen',
];
const AUDIENCES = ['unisex', 'girls', 'boys'];
function pick(v, allowed, fallback) {
    return typeof v === 'string' && allowed.includes(v) ? v : fallback;
}
function num(v, min, max, fallback) {
    const n = typeof v === 'number' && Number.isFinite(v) ? v : fallback;
    return Math.min(max, Math.max(min, n));
}
function hex(v) {
    return typeof v === 'string' && /^#[0-9a-fA-F]{6}$/.test(v) ? v.toUpperCase() : null;
}
function cleanText(v, max) {
    return typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, max) : '';
}
/** Lowercase words plus their prefixes, for `array-contains` search. */
function keywordsFor(parts) {
    const out = new Set();
    for (const part of parts) {
        for (const w of part.toLowerCase().split(/[^a-z0-9]+/)) {
            if (w.length < 2)
                continue;
            const word = w.slice(0, 20);
            for (let i = 2; i <= word.length; i++)
                out.add(word.slice(0, i));
        }
    }
    return [...out].slice(0, 200);
}
async function underDailyCap(uid, kind = 'gen', limit = DAILY_GENERATIONS) {
    const day = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    // Top-level and rules-denied, so users can't reset their own counter.
    const ref = (0, firestore_2.getFirestore)().doc(`ar_effect_quotas/${uid}_${kind === 'gen' ? '' : `${kind}_`}${day}`);
    return (0, firestore_2.getFirestore)().runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(ref);
        const count = (_a = snap.get('count')) !== null && _a !== void 0 ? _a : 0;
        if (count >= limit)
            return false;
        tx.set(ref, { count: firestore_2.FieldValue.increment(1), updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    });
}
async function generateJson(system, user) {
    var _a;
    const res = await (0, vertexAi_1.vertexAi)().models.generateContent({
        model: TEXT_MODEL,
        contents: [{ role: 'user', parts: [{ text: user }] }],
        config: {
            systemInstruction: system,
            responseMimeType: 'application/json',
            temperature: 0.5,
            maxOutputTokens: 1200,
            thinkingConfig: { thinkingBudget: 0 },
        },
    });
    const raw = (_a = res.text) !== null && _a !== void 0 ? _a : '';
    try {
        return JSON.parse(raw);
    }
    catch (_b) {
        const m = raw.match(/\{[\s\S]*\}/);
        if (!m)
            throw new Error('bad_json');
        return JSON.parse(m[0]);
    }
}
const SPEC_SYSTEM = `You design live AR camera effects for Oneova, a social video app.
The phone tracks the face (468-point mesh with head pose), the shoulders and a person mask.
Reply ONLY with JSON:
{"safe":true|false,"reason":"","name":"2-4 words","description":"one short sentence",
"kind":"sprite"|"makeup"|"background","category":"${CATEGORIES.join('|')}",
"audience":"girls"|"boys"|"unisex","anchor":"${ANCHORS.join('|')}",
"scale":number,"offsetX":number,"offsetY":number,"tags":["up to 8 lowercase words"],
"keyColor":"green"|"magenta","imagePrompt":"what to draw",
"makeup":{"lipColor":"#RRGGBB","lipOpacity":0-1,"blushColor":"#RRGGBB","blushOpacity":0-1,
"eyeColor":"#RRGGBB","eyeOpacity":0-1,"eyeGlow":0-1,"linerColor":"#RRGGBB","linerOpacity":0-1,
"browColor":"#RRGGBB","browOpacity":0-1}}

Kinds:
- sprite: one object pinned to the anchor (glasses, hat, crown, beard, moustache, wig, mask, earrings, necklace, shirt, wings, a floating object).
- makeup: colors drawn on the tracked face. Use for lipstick, blush, eyeliner, brows, colored/glowing eyes, any "eye effect" that is light or color rather than an object. Set unused opacities to 0.
- background: a full scene that replaces what is behind the person (beach, space, neon city).

Sprite placement: the sprite's CENTER sits on the anchor. scale = sprite width / face width (cheek to cheek).
offsetX/offsetY move the center in face widths in the face's own frame (+offsetY is down).
Good defaults: glasses eyes 1.0/0/0; sunglasses eyes 1.05/0/0; hat headTop 1.25/0/-0.05; crown headTop 0.9/0/0.05;
beard chin 1.0/0/0.1; moustache mouth 0.55/0/-0.18; wig/long hair hair 1.75/0/0.45; bunny ears/horns headTop 1.1/0/-0.1;
full mask face 1.1/0/0; earrings pair face 1.45/0/0.25; necklace neck 0.9/0/0.15; shirt/jacket/dress torso 1.0/0/0;
nose (clown nose, piercing) nose 0.35/0/0; things floating in the room (butterflies, neon sign, hearts) world 1.0/0/0.
keyColor: a flat background the object will be cut out from; pick magenta if the object is green, else green.
imagePrompt: describe ONLY the object, as seen straight on from the front as if worn by someone facing the camera.
For backgrounds describe the scene, vertical, with no people.
audience: girls/boys only if the user asked for it or it is clearly gendered styling, else unisex.
safe=false for sexual content or nudity, real people's likeness, hate symbols, graphic violence or drugs.`;
async function generateImage(prompt, aspectRatio) {
    var _a, _b, _c, _d, _e, _f, _g;
    var _h;
    try {
        const res = await (0, vertexAi_1.vertexAi)().models.generateContent({
            model: IMAGE_MODEL,
            contents: [{ role: 'user', parts: [{ text: prompt }] }],
            config: { responseModalities: ['IMAGE'], imageConfig: { aspectRatio } },
        });
        for (const part of (_h = (_c = (_b = (_a = res.candidates) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.content) === null || _c === void 0 ? void 0 : _c.parts) !== null && _h !== void 0 ? _h : []) {
            const data = (_d = part.inlineData) === null || _d === void 0 ? void 0 : _d.data;
            if (data)
                return Buffer.from(data, 'base64');
        }
        throw new Error('no_image');
    }
    catch (e) {
        console.warn('arEffectGenerate: primary image model failed, trying fallback', e.message);
        const res = await (0, vertexAi_1.vertexAi)().models.generateImages({
            model: FALLBACK_IMAGE_MODEL,
            prompt,
            config: { numberOfImages: 1, aspectRatio },
        });
        const bytes = (_g = (_f = (_e = res.generatedImages) === null || _e === void 0 ? void 0 : _e[0]) === null || _f === void 0 ? void 0 : _f.image) === null || _g === void 0 ? void 0 : _g.imageBytes;
        if (!bytes)
            throw new https_1.HttpsError('internal', 'The image model returned nothing. Try rewording.');
        return Buffer.from(bytes, 'base64');
    }
}
function decode(buf) {
    if (buf[0] === 0x89 && buf[1] === 0x50) {
        const png = pngjs_1.PNG.sync.read(buf);
        return { width: png.width, height: png.height, data: png.data };
    }
    if (buf[0] === 0xff && buf[1] === 0xd8) {
        const img = jpeg.decode(buf, { useTArray: false, formatAsRGBA: true, maxMemoryUsageInMB: 256 });
        return { width: img.width, height: img.height, data: img.data };
    }
    throw new https_1.HttpsError('invalid-argument', 'Unsupported image format.');
}
function encodePng(img) {
    const png = new pngjs_1.PNG({ width: img.width, height: img.height });
    img.data.copy(png.data);
    return pngjs_1.PNG.sync.write(png);
}
/** Box-filter downscale (premultiplied, so keyed edges don't go dark). */
function resize(img, maxSide) {
    const scale = Math.min(1, maxSide / Math.max(img.width, img.height));
    if (scale >= 1)
        return img;
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));
    const out = Buffer.alloc(w * h * 4);
    const sx = img.width / w;
    const sy = img.height / h;
    for (let y = 0; y < h; y++) {
        const y0 = Math.floor(y * sy);
        const y1 = Math.max(y0 + 1, Math.floor((y + 1) * sy));
        for (let x = 0; x < w; x++) {
            const x0 = Math.floor(x * sx);
            const x1 = Math.max(x0 + 1, Math.floor((x + 1) * sx));
            let r = 0, g = 0, b = 0, a = 0, n = 0;
            for (let yy = y0; yy < y1; yy++) {
                for (let xx = x0; xx < x1; xx++) {
                    const i = (yy * img.width + xx) * 4;
                    const al = img.data[i + 3];
                    r += img.data[i] * al;
                    g += img.data[i + 1] * al;
                    b += img.data[i + 2] * al;
                    a += al;
                    n++;
                }
            }
            const o = (y * w + x) * 4;
            out[o] = a ? Math.round(r / a) : 0;
            out[o + 1] = a ? Math.round(g / a) : 0;
            out[o + 2] = a ? Math.round(b / a) : 0;
            out[o + 3] = Math.round(a / n);
        }
    }
    return { width: w, height: h, data: out };
}
/** Crops to the visible pixels plus a small margin. */
function cropToAlpha(img) {
    let minX = img.width, minY = img.height, maxX = -1, maxY = -1;
    for (let y = 0; y < img.height; y++) {
        for (let x = 0; x < img.width; x++) {
            if (img.data[(y * img.width + x) * 4 + 3] > 12) {
                if (x < minX)
                    minX = x;
                if (x > maxX)
                    maxX = x;
                if (y < minY)
                    minY = y;
                if (y > maxY)
                    maxY = y;
            }
        }
    }
    if (maxX < 0)
        return img;
    const pad = Math.round(Math.max(maxX - minX, maxY - minY) * 0.03);
    minX = Math.max(0, minX - pad);
    minY = Math.max(0, minY - pad);
    maxX = Math.min(img.width - 1, maxX + pad);
    maxY = Math.min(img.height - 1, maxY + pad);
    const w = maxX - minX + 1;
    const h = maxY - minY + 1;
    const out = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) {
        img.data.copy(out, y * w * 4, ((minY + y) * img.width + minX) * 4, ((minY + y) * img.width + minX + w) * 4);
    }
    return { width: w, height: h, data: out };
}
/**
 * Keys out the flat background. The real background color is measured from
 * the image border (models never paint the exact hex asked for), alpha ramps
 * with distance from it, and the key color is de-spilled from soft edges.
 */
function chromaKey(img) {
    var _a;
    const { width: w, height: h, data } = img;
    const border = [];
    const step = Math.max(1, Math.floor(Math.min(w, h) / 64));
    for (let x = 0; x < w; x += step) {
        for (const y of [0, 1, h - 2, h - 1]) {
            const i = (y * w + x) * 4;
            border.push([data[i], data[i + 1], data[i + 2]]);
        }
    }
    for (let y = 0; y < h; y += step) {
        for (const x of [0, 1, w - 2, w - 1]) {
            const i = (y * w + x) * 4;
            border.push([data[i], data[i + 1], data[i + 2]]);
        }
    }
    const median = (k) => {
        const v = border.map((p) => p[k]).sort((a, b) => a - b);
        return v[Math.floor(v.length / 2)];
    };
    const kr = median(0), kg = median(1), kb = median(2);
    const greenKey = kg >= kr && kg >= kb;
    const out = Buffer.from(data);
    let opaque = 0;
    const t0 = 38, t1 = 105;
    for (let i = 0; i < out.length; i += 4) {
        const r = out[i], g = out[i + 1], b = out[i + 2];
        const d = Math.sqrt((r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2);
        let a = Math.min(1, Math.max(0, (d - t0) / (t1 - t0)));
        a = a * a * (3 - 2 * a);
        if (a < 1) {
            if (greenKey && g > Math.max(r, b))
                out[i + 1] = Math.max(r, b);
            if (!greenKey && Math.min(r, b) > g) {
                out[i] = Math.round((r + g) / 2);
                out[i + 2] = Math.round((b + g) / 2);
            }
        }
        out[i + 3] = Math.round(a * ((_a = data[i + 3]) !== null && _a !== void 0 ? _a : 255));
        if (a > 0.5)
            opaque++;
    }
    return { img: { width: w, height: h, data: out }, coverage: opaque / (w * h) };
}
async function saveAsset(effectId, name, png) {
    const path = `ar_effects/${effectId}/${name}`;
    const file = (0, storage_1.getStorage)().bucket().file(path);
    await file.save(png, {
        contentType: 'image/png',
        resumable: false,
        metadata: { cacheControl: 'public, max-age=31536000, immutable' },
    });
    return { url: await (0, storage_1.getDownloadURL)(file), path };
}
async function creatorName(uid) {
    var _a;
    var _b, _c, _d;
    try {
        const snap = await (0, firestore_2.getFirestore)().doc(`users/${uid}`).get();
        const n = (_c = (_b = snap.get('displayName')) !== null && _b !== void 0 ? _b : snap.get('username')) !== null && _c !== void 0 ? _c : snap.get('name');
        if (typeof n === 'string' && n.trim())
            return n.trim().slice(0, 40);
        return (_d = (_a = (await (0, auth_1.getAuth)().getUser(uid)).displayName) === null || _a === void 0 ? void 0 : _a.slice(0, 40)) !== null && _d !== void 0 ? _d : '';
    }
    catch (_e) {
        return '';
    }
}
/** Sanitizes a makeup spec to the fields `ArMakeup.fromMap` reads. */
function makeupFrom(m) {
    const out = {};
    for (const k of ['lip', 'blush', 'eye', 'shadow', 'liner', 'brow', 'foundation']) {
        const color = hex(m === null || m === void 0 ? void 0 : m[`${k}Color`]);
        const opacity = num(m === null || m === void 0 ? void 0 : m[`${k}Opacity`], 0, 1, 0);
        if (color)
            out[`${k}Color`] = color;
        out[`${k}Opacity`] = color ? opacity : 0;
    }
    out.eyeGlow = num(m === null || m === void 0 ? void 0 : m.eyeGlow, 0, 1, 0);
    if (!out.eyeColor && out.eyeGlow > 0)
        out.eyeColor = '#4FC3FF';
    out.lipGloss = num(m === null || m === void 0 ? void 0 : m.lipGloss, 0, 1, 0);
    out.linerWidth = num(m === null || m === void 0 ? void 0 : m.linerWidth, 0, 1, 0.35);
    out.linerWing = num(m === null || m === void 0 ? void 0 : m.linerWing, 0, 1, 0);
    out.browWidth = num(m === null || m === void 0 ? void 0 : m.browWidth, 0, 1, 0.5);
    out.contourOpacity = num(m === null || m === void 0 ? void 0 : m.contourOpacity, 0, 1, 0);
    out.highlightOpacity = num(m === null || m === void 0 ? void 0 : m.highlightOpacity, 0, 1, 0);
    out.smoothing = num(m === null || m === void 0 ? void 0 : m.smoothing, 0, 1, 0);
    return out;
}
const MAKEUP_FIELDS = `{"lipColor":"#RRGGBB","lipOpacity":0-1,"lipGloss":0-1,"blushColor":"#RRGGBB","blushOpacity":0-1,
"eyeColor":"#RRGGBB (iris tint)","eyeOpacity":0-1,"eyeGlow":0-1,"shadowColor":"#RRGGBB (eyeshadow)","shadowOpacity":0-1,
"linerColor":"#RRGGBB","linerOpacity":0-1,"linerWidth":0-1,"linerWing":0-1,"browColor":"#RRGGBB","browOpacity":0-1,"browWidth":0-1,
"foundationColor":"#RRGGBB","foundationOpacity":0-1,"contourOpacity":0-1,"highlightOpacity":0-1,"smoothing":0-1}`;
const MAKEUP_SYSTEM = `You are a professional makeup artist for Oneova's live AR camera. The camera tracks the face and draws
makeup on it. Reply ONLY with JSON: {"name":"2-4 words","tip":"one short sentence for the user","makeup":${MAKEUP_FIELDS}}.
Opacities are strengths; 0 means not applied. Keep looks wearable: lips 0.3-0.85, blush 0.2-0.6, shadow 0.2-0.7,
foundation at most 0.4 and only close to the person's real skin tone, smoothing 0.2-0.6, eyeOpacity 0 unless colored
lenses are asked for, eyeGlow 0 unless a fantasy/glowing look is asked for. If a photo is given, read skin tone and
undertone (warm/cool/neutral), eye and hair color, and pick shades that flatter them; never comment on attractiveness,
weight, age or ethnicity. If the current makeup is given and the user asks for a change, adjust it instead of starting over.`;
/**
 * Makeup Studio AI: turns a description (and optionally a still of the
 * user's face, which is analyzed and never stored) into makeup settings.
 */
exports.arMakeupSuggest = (0, https_1.onCall)({ timeoutSeconds: 60, memory: '512MiB' }, async (request) => {
    var _a;
    var _b, _c;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to use AI makeup.');
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const prompt = cleanText(data.prompt, 300);
    const image = typeof data.image === 'string' && data.image.length < 2000000 ? data.image : '';
    if (prompt.length < 2 && !image)
        throw new https_1.HttpsError('invalid-argument', 'Describe a look or use your face.');
    if (!(await underDailyCap(uid, 'makeup', 80))) {
        throw new https_1.HttpsError('resource-exhausted', 'Daily AI makeup limit reached. Try again tomorrow.');
    }
    const current = data.current && typeof data.current === 'object' ? JSON.stringify(makeupFrom(data.current)) : '';
    const parts = [];
    if (image)
        parts.push({ inlineData: { mimeType: 'image/jpeg', data: image } });
    parts.push({
        text: [
            prompt ? `Look requested: "${prompt}".` : 'Pick a flattering everyday look for this face.',
            current ? `Current makeup: ${current}.` : '',
            image ? 'The photo is the user\'s live camera frame.' : '',
        ].filter(Boolean).join(' '),
    });
    let out;
    try {
        const res = await (0, vertexAi_1.vertexAi)().models.generateContent({
            model: TEXT_MODEL,
            contents: [{ role: 'user', parts }],
            config: {
                systemInstruction: MAKEUP_SYSTEM,
                responseMimeType: 'application/json',
                temperature: 0.6,
                maxOutputTokens: 900,
                thinkingConfig: { thinkingBudget: 0 },
            },
        });
        const raw = (_c = res.text) !== null && _c !== void 0 ? _c : '';
        try {
            out = JSON.parse(raw);
        }
        catch (_d) {
            const m = raw.match(/\{[\s\S]*\}/);
            out = m ? JSON.parse(m[0]) : null;
        }
    }
    catch (e) {
        console.error('arMakeupSuggest failed', e.message);
        throw new https_1.HttpsError('unavailable', 'AI is busy. Try again in a moment.');
    }
    if (!(out === null || out === void 0 ? void 0 : out.makeup))
        throw new https_1.HttpsError('internal', 'AI could not build that look. Try rewording.');
    return {
        name: cleanText(out.name, 40) || 'AI look',
        tip: cleanText(out.tip, 160),
        makeup: makeupFrom(out.makeup),
    };
});
exports.arEffectGenerate = (0, https_1.onCall)({ timeoutSeconds: 180, memory: '1GiB' }, async (request) => {
    var _a;
    var _b, _c;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to create effects.');
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const prompt = cleanText(data.prompt, 200);
    if (prompt.length < 3)
        throw new https_1.HttpsError('invalid-argument', 'Describe the effect in a few words.');
    const publish = data.publish !== false;
    if (!(await underDailyCap(uid))) {
        throw new https_1.HttpsError('resource-exhausted', `You can create ${DAILY_GENERATIONS} effects a day. Try again tomorrow.`);
    }
    const hints = [];
    if (typeof data.audience === 'string' && data.audience !== 'unisex')
        hints.push(`Made for ${data.audience}.`);
    if (typeof data.category === 'string')
        hints.push(`Preferred category: ${data.category}.`);
    let spec;
    try {
        spec = await generateJson(SPEC_SYSTEM, `Effect request: "${prompt}". ${hints.join(' ')}`);
    }
    catch (e) {
        console.error('arEffectGenerate spec failed', e.message);
        throw new https_1.HttpsError('unavailable', 'AI is busy. Try again in a moment.');
    }
    if ((spec === null || spec === void 0 ? void 0 : spec.safe) === false) {
        throw new https_1.HttpsError('failed-precondition', 'That effect is not allowed on Oneova. Try something else.');
    }
    const kind = pick(spec.kind, KINDS, 'sprite');
    const anchor = kind === 'background' ? 'screen' : pick(spec.anchor, ANCHORS, 'face');
    const category = kind === 'background'
        ? 'backgrounds'
        : kind === 'makeup'
            ? pick(spec.category, ['makeup', 'eyes'], 'makeup')
            : pick(spec.category, CATEGORIES, anchor === 'world' ? 'world' : 'stickers');
    const audience = pick((_c = data.audience) !== null && _c !== void 0 ? _c : spec.audience, AUDIENCES, 'unisex');
    const name = cleanText(spec.name, 40) || prompt.slice(0, 40);
    const description = cleanText(spec.description, 140);
    const tags = (Array.isArray(spec.tags) ? spec.tags : [])
        .map((t) => cleanText(t, 24).toLowerCase())
        .filter(Boolean)
        .slice(0, 8);
    const effectId = (0, firestore_2.getFirestore)().collection('ar_effects').doc().id;
    const doc = {
        name,
        description,
        prompt,
        kind,
        category,
        audience,
        anchor,
        tags,
        scale: num(spec.scale, 0.2, 4, 1),
        offsetX: num(spec.offsetX, -2, 2, 0),
        offsetY: num(spec.offsetY, -3, 3, 0),
        source: 'ai',
    };
    if (kind === 'makeup') {
        doc.makeup = makeupFrom(spec.makeup);
    }
    else if (kind === 'background') {
        const scenePrompt = `${cleanText(spec.imagePrompt, 400) || prompt}. Vertical photographic backdrop, ` +
            'natural perspective at eye level, no people, no text, no watermark.';
        const raw = decode(await generateImage(scenePrompt, '9:16'));
        const scene = resize(raw, MAX_SCENE);
        const asset = await saveAsset(effectId, 'scene.png', encodePng(scene));
        const thumb = await saveAsset(effectId, 'thumb.png', encodePng(resize(scene, 240)));
        doc.assetUrl = asset.url;
        doc.thumbUrl = thumb.url;
        doc.storagePath = asset.path;
    }
    else {
        const keyHex = spec.keyColor === 'magenta' ? '#FF00FF' : '#00FF00';
        const keyName = spec.keyColor === 'magenta' ? 'magenta' : 'green';
        const spritePrompt = `${cleanText(spec.imagePrompt, 400) || prompt}. One single object only, centered, ` +
            'straight-on front view as if worn by a person facing the camera, crisp edges, even studio lighting. ' +
            'No person, no face, no skin, no mannequin, no text, no drop shadow, no reflections of the background. ' +
            `Perfectly flat solid pure ${keyName} (${keyHex}) background filling the entire canvas.`;
        const aspect = anchor === 'torso' ? '3:4' : '1:1';
        const keyed = chromaKey(decode(await generateImage(spritePrompt, aspect)));
        if (keyed.coverage < 0.01 || keyed.coverage > 0.92) {
            throw new https_1.HttpsError('internal', 'Could not cut the effect out cleanly. Try describing it differently.');
        }
        const sprite = resize(cropToAlpha(keyed.img), MAX_SPRITE);
        const asset = await saveAsset(effectId, 'asset.png', encodePng(sprite));
        const thumb = await saveAsset(effectId, 'thumb.png', encodePng(resize(sprite, 192)));
        doc.assetUrl = asset.url;
        doc.thumbUrl = thumb.url;
        doc.storagePath = asset.path;
    }
    await (0, firestore_2.getFirestore)().doc(`ar_effects/${effectId}`).set(Object.assign(Object.assign({}, doc), { keywords: keywordsFor([name, category, audience, anchor, ...tags, prompt]), creatorUid: uid, creatorName: await creatorName(uid), listed: publish, usageCount: 0, favoriteCount: 0, score: 0, createdAt: firestore_2.FieldValue.serverTimestamp(), updatedAt: firestore_2.FieldValue.serverTimestamp() }));
    return { effectId };
});
exports.arEffectCreateFromUpload = (0, https_1.onCall)({ timeoutSeconds: 120, memory: '1GiB' }, async (request) => {
    var _a;
    var _b, _c;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to upload effects.');
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const storagePath = cleanText(data.storagePath, 200);
    if (!storagePath.startsWith(`ar_effect_uploads/${uid}/`) || storagePath.includes('..')) {
        throw new https_1.HttpsError('permission-denied', 'Upload not found.');
    }
    const name = cleanText(data.name, 40) || 'My effect';
    const anchor = pick(data.anchor, ANCHORS, 'face');
    const category = pick(data.category, CATEGORIES, 'stickers');
    const audience = pick(data.audience, AUDIENCES, 'unisex');
    const publish = data.publish !== false;
    if (!(await underDailyCap(uid))) {
        throw new https_1.HttpsError('resource-exhausted', `You can create ${DAILY_GENERATIONS} effects a day. Try again tomorrow.`);
    }
    const upload = (0, storage_1.getStorage)().bucket().file(storagePath);
    const [buf] = await upload.download();
    if (buf.length > 8 * 1024 * 1024)
        throw new https_1.HttpsError('invalid-argument', 'Image is too large (8 MB max).');
    const img = decode(buf);
    const isBackground = anchor === 'screen' || category === 'backgrounds';
    let transparent = 0;
    for (let i = 3; i < img.data.length; i += 4)
        if (img.data[i] < 128)
            transparent++;
    if (!isBackground && transparent / (img.width * img.height) < 0.05) {
        throw new https_1.HttpsError('invalid-argument', 'Use a PNG with a transparent background.');
    }
    // Same safety bar as generated effects.
    const check = await (0, vertexAi_1.vertexAi)().models.generateContent({
        model: TEXT_MODEL,
        contents: [{
                role: 'user',
                parts: [
                    { inlineData: { mimeType: buf[0] === 0x89 ? 'image/png' : 'image/jpeg', data: buf.toString('base64') } },
                    { text: `This image will be a public camera effect named "${name}". Reply ONLY JSON {"safe":true|false,"tags":["up to 6 lowercase words describing it"]}. ` +
                            'safe=false for nudity or sexual content, hate symbols, graphic violence, or a real person\'s face.' },
                ],
            }],
        config: { responseMimeType: 'application/json', temperature: 0, maxOutputTokens: 200, thinkingConfig: { thinkingBudget: 0 } },
    });
    let verdict = {};
    try {
        verdict = JSON.parse((_c = check.text) !== null && _c !== void 0 ? _c : '{}');
    }
    catch (_d) {
        verdict = {};
    }
    if (verdict.safe !== true) {
        await upload.delete().catch(() => undefined);
        throw new https_1.HttpsError('failed-precondition', 'That image cannot be used as an effect.');
    }
    const tags = (Array.isArray(verdict.tags) ? verdict.tags : [])
        .map((t) => cleanText(t, 24).toLowerCase())
        .filter(Boolean)
        .slice(0, 6);
    const effectId = (0, firestore_2.getFirestore)().collection('ar_effects').doc().id;
    const asset = isBackground ? resize(img, MAX_SCENE) : resize(cropToAlpha(img), MAX_SPRITE);
    const saved = await saveAsset(effectId, isBackground ? 'scene.png' : 'asset.png', encodePng(asset));
    const thumb = await saveAsset(effectId, 'thumb.png', encodePng(resize(asset, 192)));
    await upload.delete().catch(() => undefined);
    await (0, firestore_2.getFirestore)().doc(`ar_effects/${effectId}`).set({
        name,
        description: '',
        kind: isBackground ? 'background' : 'sprite',
        category: isBackground ? 'backgrounds' : category,
        audience,
        anchor: isBackground ? 'screen' : anchor,
        tags,
        scale: 1,
        offsetX: 0,
        offsetY: 0,
        source: 'upload',
        assetUrl: saved.url,
        thumbUrl: thumb.url,
        storagePath: saved.path,
        keywords: keywordsFor([name, category, audience, anchor, ...tags]),
        creatorUid: uid,
        creatorName: await creatorName(uid),
        listed: publish,
        usageCount: 0,
        favoriteCount: 0,
        score: 0,
        createdAt: firestore_2.FieldValue.serverTimestamp(),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    return { effectId };
});
/** One counted use per user, effect and day. */
exports.arEffectUse = (0, https_1.onCall)({ timeoutSeconds: 20, memory: '256MiB' }, async (request) => {
    var _a, _b;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const effectId = cleanText((_b = request.data) === null || _b === void 0 ? void 0 : _b.effectId, 64);
    if (!/^[A-Za-z0-9_-]{4,64}$/.test(effectId))
        throw new https_1.HttpsError('invalid-argument', 'Bad effect.');
    const db = (0, firestore_2.getFirestore)();
    const day = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    const mark = db.doc(`ar_effect_usage/${uid}_${effectId}_${day}`);
    const effect = db.doc(`ar_effects/${effectId}`);
    const counted = await db.runTransaction(async (tx) => {
        const [m, e] = await Promise.all([tx.get(mark), tx.get(effect)]);
        if (m.exists || !e.exists)
            return false;
        tx.set(mark, { effectId, at: firestore_2.FieldValue.serverTimestamp() });
        tx.update(effect, { usageCount: firestore_2.FieldValue.increment(1), score: firestore_2.FieldValue.increment(1) });
        return true;
    });
    return { counted };
});
const FAVORITE_WEIGHT = 5;
async function bumpFavorite(effectId, delta) {
    const ref = (0, firestore_2.getFirestore)().doc(`ar_effects/${effectId}`);
    await (0, firestore_2.getFirestore)().runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(ref);
        if (!snap.exists)
            return;
        const current = (_a = snap.get('favoriteCount')) !== null && _a !== void 0 ? _a : 0;
        if (delta < 0 && current <= 0)
            return;
        tx.update(ref, {
            favoriteCount: firestore_2.FieldValue.increment(delta),
            score: firestore_2.FieldValue.increment(delta * FAVORITE_WEIGHT),
        });
    });
}
exports.arEffectFavoriteAdded = (0, firestore_1.onDocumentCreated)('users/{uid}/ar_favorites/{effectId}', async (event) => {
    await bumpFavorite(event.params.effectId, 1);
});
exports.arEffectFavoriteRemoved = (0, firestore_1.onDocumentDeleted)('users/{uid}/ar_favorites/{effectId}', async (event) => {
    await bumpFavorite(event.params.effectId, -1);
});
//# sourceMappingURL=arEffects.js.map