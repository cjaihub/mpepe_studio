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
exports.textureCreate = exports.textureLibrary = void 0;
/**
 * Hosted texture library for 3D products and live stages.
 *
 *   textureLibrary  the built-in library (`texture_library`). Missing
 *                   textures are rendered and uploaded on first use, so the
 *                   library fills itself; later calls only read.
 *   textureCreate   a seller's own colorway of any kind, hosted under
 *                   `shops/{uid}/textures/` and listed in
 *                   `biz_shops/{uid}/textures`.
 *
 * Images are seamless PNGs from textureEngine.ts; the app's 3D viewer puts
 * them on the model's materials with the stored roughness / metallic / scale.
 */
const crypto = __importStar(require("crypto"));
const pngjs_1 = require("pngjs");
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const textureEngine_1 = require("./textureEngine");
const db = () => (0, firestore_1.getFirestore)();
const SIZE = 512;
const MAX_PER_SHOP = 60;
async function host(path, spec) {
    const png = new pngjs_1.PNG({ width: SIZE, height: SIZE });
    png.data = Buffer.from((0, textureEngine_1.renderTexture)(Object.assign(Object.assign({}, spec), { size: SIZE })));
    const file = (0, storage_1.getStorage)().bucket().file(path);
    await file.save(pngjs_1.PNG.sync.write(png), {
        contentType: 'image/png',
        metadata: { cacheControl: 'public, max-age=31536000, immutable' },
        resumable: false,
    });
    return (0, storage_1.getDownloadURL)(file);
}
function docFor(name, spec, url) {
    const m = textureEngine_1.MATERIAL[spec.kind];
    return {
        name, kind: spec.kind, category: m.category, colors: spec.colors, url,
        roughness: m.roughness, metallic: m.metallic, scale: m.scale,
    };
}
exports.textureLibrary = (0, https_1.onCall)({ memory: '1GiB', timeoutSeconds: 300 }, async (req) => {
    var _a;
    var _b;
    if (!((_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid))
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const col = db().collection('texture_library');
    const have = new Set((await col.select().get()).docs.map((d) => d.id));
    const missing = textureEngine_1.BUILT_IN.filter((t) => !have.has(t.id));
    for (const [i, t] of missing.entries()) {
        try {
            const url = await host(`textures/library/${t.id}.png`, t.spec);
            await col.doc(t.id).set(Object.assign(Object.assign({}, docFor(t.name, t.spec, url)), { builtIn: true, order: textureEngine_1.BUILT_IN.indexOf(t), createdAt: firestore_1.FieldValue.serverTimestamp() }));
        }
        catch (e) {
            logger.error('texture render failed', t.id, i, (_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : e);
        }
    }
    const all = await col.orderBy('order').get();
    return { textures: all.docs.map((d) => (Object.assign(Object.assign({ id: d.id }, d.data()), { createdAt: null }))) };
});
exports.textureCreate = (0, https_1.onCall)({ memory: '512MiB', timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c, _d;
    var _e, _f;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const kind = String((_e = (_b = req.data) === null || _b === void 0 ? void 0 : _b.kind) !== null && _e !== void 0 ? _e : '');
    if (!textureEngine_1.TEXTURE_KINDS.includes(kind))
        throw new https_1.HttpsError('invalid-argument', 'Pick a material.');
    const colors = (Array.isArray((_c = req.data) === null || _c === void 0 ? void 0 : _c.colors) ? req.data.colors : [])
        .map((c) => String(c))
        .filter((c) => /^#?[0-9a-fA-F]{6}$/.test(c))
        .slice(0, 4)
        .map((c) => (c.startsWith('#') ? c : `#${c}`));
    if (colors.length < 1)
        throw new https_1.HttpsError('invalid-argument', 'Pick at least one color.');
    const name = String((_f = (_d = req.data) === null || _d === void 0 ? void 0 : _d.name) !== null && _f !== void 0 ? _f : textureEngine_1.MATERIAL[kind].label).trim().slice(0, 40) || textureEngine_1.MATERIAL[kind].label;
    const shopRef = db().collection('biz_shops').doc(uid);
    if (!(await shopRef.get()).exists)
        throw new https_1.HttpsError('failed-precondition', 'Set up your shop first.');
    const mine = shopRef.collection('textures');
    if ((await mine.count().get()).data().count >= MAX_PER_SHOP) {
        throw new https_1.HttpsError('resource-exhausted', `You can keep up to ${MAX_PER_SHOP} textures. Delete one to add more.`);
    }
    const id = crypto.randomBytes(8).toString('hex');
    const spec = { kind, colors, seed: crypto.randomInt(1, 1000000) };
    const url = await host(`shops/${uid}/textures/${id}.png`, spec);
    const doc = Object.assign(Object.assign({}, docFor(name, spec, url)), { builtIn: false, createdAt: firestore_1.FieldValue.serverTimestamp() });
    await mine.doc(id).set(doc);
    return Object.assign(Object.assign({ id }, doc), { createdAt: null });
});
//# sourceMappingURL=textures.js.map