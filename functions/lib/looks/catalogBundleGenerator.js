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
exports.generateCatalogBundles = void 0;
exports.computeBufferHash = computeBufferHash;
exports.buildCatalogBundles = buildCatalogBundles;
const crypto = __importStar(require("crypto"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const https_1 = require("firebase-functions/v2/https");
/**
 * Computes sha256 hash and ETag for a buffer.
 */
function computeBufferHash(buffer) {
    const hash = crypto.createHash('sha256').update(buffer).digest('hex');
    const etag = `"${hash.substring(0, 24)}"`;
    return { hash: `sha256:${hash}`, etag };
}
/**
 * Builds the Firestore Data Bundle and static JSON manifests for the Looks catalog.
 */
async function buildCatalogBundles() {
    const db = (0, firestore_1.getFirestore)();
    // 1. Fetch published looks
    const looksQuery = db.collection('lookCatalog').where('isPublished', '==', true);
    const looksSnap = await looksQuery.get();
    const looksList = [];
    const lookItems = [];
    looksSnap.forEach((doc) => {
        var _a, _b, _c;
        const data = doc.data();
        looksList.push(Object.assign({ id: doc.id }, data));
        lookItems.push({
            id: doc.id,
            category: (data.categories && data.categories[0]) || 'cinematic',
            version: data.schemaVersion ? `2.${data.schemaVersion}.0` : '2.0.0',
            etag: `"${doc.id}_${((_a = data.updatedAt) === null || _a === void 0 ? void 0 : _a.toMillis) ? data.updatedAt.toMillis() : Date.now()}"`,
            url: `/looks/${doc.id}.json`,
            updatedAt: ((_c = (_b = data.updatedAt) === null || _b === void 0 ? void 0 : _b.toDate) === null || _c === void 0 ? void 0 : _c.call(_b)) ? data.updatedAt.toDate().toISOString() : new Date().toISOString(),
        });
    });
    // 2. Fetch categories
    const catQuery = db.collection('lookCategories').orderBy('order');
    const catSnap = await catQuery.get();
    // 3. Build Firestore Bundle
    const bundle = db.bundle('looks-catalog-bundle');
    bundle.add('latest-published-looks', looksSnap);
    bundle.add('look-categories', catSnap);
    const bundleBuffer = bundle.build();
    const { hash: looksHash, etag: looksEtag } = computeBufferHash(bundleBuffer);
    const now = new Date().toISOString();
    const manifestVersion = `2.${Date.now()}`;
    const manifest = {
        schemaVersion: 2,
        manifestVersion,
        generatedAt: now,
        bundles: {
            looks: {
                id: 'looks_catalog_v2',
                version: manifestVersion,
                bundleUrl: '/bundles/looks_catalog.bundle',
                etag: looksEtag,
                sizeBytes: bundleBuffer.length,
                itemCount: looksList.length,
                contentHash: looksHash,
                updatedAt: now,
            },
            effects: {
                id: 'effects_manifest_v1',
                version: '1.0.0',
                bundleUrl: '/bundles/effects_manifest.json',
                etag: '"effects_v1_static"',
                sizeBytes: 1024,
                itemCount: 0,
                contentHash: 'sha256:effects00000000',
                updatedAt: now,
            },
            models: {
                id: 'vision_models_v1',
                version: '1.0.0',
                bundleUrl: '/bundles/models_manifest.json',
                etag: '"models_v1_static"',
                sizeBytes: 2048,
                itemCount: 0,
                contentHash: 'sha256:models00000000',
                updatedAt: now,
            },
            skills: {
                id: 'ai_skills_v1',
                version: '1.0.0',
                bundleUrl: '/bundles/skills_manifest.json',
                etag: '"skills_v1_static"',
                sizeBytes: 4096,
                itemCount: 12,
                contentHash: 'sha256:skills00000000',
                updatedAt: now,
            },
        },
        items: {
            looks: lookItems,
        },
    };
    const manifestBuffer = Buffer.from(JSON.stringify(manifest, null, 2), 'utf8');
    return {
        manifest,
        looksBundleBytes: bundleBuffer,
        manifestBytes: manifestBuffer,
    };
}
/**
 * Admin callable to trigger catalog bundle regeneration and Cloud Storage / CDN deployment.
 */
exports.generateCatalogBundles = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const { manifest, looksBundleBytes, manifestBytes } = await buildCatalogBundles();
    // Try writing to public/bundles directory if running locally or in development
    try {
        const publicBundlesDir = path.resolve(__dirname, '../../../public/bundles');
        if (fs.existsSync(path.dirname(publicBundlesDir))) {
            if (!fs.existsSync(publicBundlesDir)) {
                fs.mkdirSync(publicBundlesDir, { recursive: true });
            }
            fs.writeFileSync(path.join(publicBundlesDir, 'looks_catalog.bundle'), looksBundleBytes);
            fs.writeFileSync(path.join(publicBundlesDir, 'manifest.json'), manifestBytes);
        }
    }
    catch (err) {
        console.warn('[CatalogBundleGenerator] Local write failed or not supported in this runtime:', err);
    }
    // Upload to Cloud Storage bucket for CDN egress
    try {
        const bucket = (0, storage_1.getStorage)().bucket();
        await bucket.file('bundles/looks_catalog.bundle').save(looksBundleBytes, {
            contentType: 'application/octet-stream',
            metadata: {
                cacheControl: 'public, max-age=3600, stale-while-revalidate=86400',
                etag: manifest.bundles.looks.etag,
            },
        });
        await bucket.file('bundles/manifest.json').save(manifestBytes, {
            contentType: 'application/json',
            metadata: {
                cacheControl: 'public, max-age=300, stale-while-revalidate=3600',
            },
        });
    }
    catch (err) {
        console.warn('[CatalogBundleGenerator] Cloud storage upload skipped/failed:', err);
    }
    return {
        success: true,
        manifestVersion: manifest.manifestVersion,
        itemCount: manifest.bundles.looks.itemCount,
        bundleSizeBytes: looksBundleBytes.length,
        etag: manifest.bundles.looks.etag,
    };
});
//# sourceMappingURL=catalogBundleGenerator.js.map