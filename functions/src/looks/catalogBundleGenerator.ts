import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

export interface BundleManifestEntry {
  id: string;
  version: string;
  bundleUrl: string;
  etag: string;
  sizeBytes: number;
  itemCount: number;
  contentHash: string;
  updatedAt: string;
}

export interface CatalogManifest {
  schemaVersion: number;
  manifestVersion: string;
  generatedAt: string;
  bundles: {
    looks: BundleManifestEntry;
    effects: BundleManifestEntry;
    models: BundleManifestEntry;
    skills: BundleManifestEntry;
  };
  items: {
    looks: Array<{
      id: string;
      category: string;
      version: string;
      etag: string;
      url: string;
      updatedAt: string;
    }>;
  };
}

/**
 * Computes sha256 hash and ETag for a buffer.
 */
export function computeBufferHash(buffer: Buffer): { hash: string; etag: string } {
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');
  const etag = `"${hash.substring(0, 24)}"`;
  return { hash: `sha256:${hash}`, etag };
}

/**
 * Builds the Firestore Data Bundle and static JSON manifests for the Looks catalog.
 */
export async function buildCatalogBundles(): Promise<{
  manifest: CatalogManifest;
  looksBundleBytes: Buffer;
  manifestBytes: Buffer;
}> {
  const db = getFirestore();

  // 1. Fetch published looks
  const looksQuery = db.collection('lookCatalog').where('isPublished', '==', true);
  const looksSnap = await looksQuery.get();

  const looksList: any[] = [];
  const lookItems: any[] = [];
  looksSnap.forEach((doc) => {
    const data = doc.data();
    looksList.push({ id: doc.id, ...data });
    lookItems.push({
      id: doc.id,
      category: (data.categories && data.categories[0]) || 'cinematic',
      version: data.schemaVersion ? `2.${data.schemaVersion}.0` : '2.0.0',
      etag: `"${doc.id}_${data.updatedAt?.toMillis ? data.updatedAt.toMillis() : Date.now()}"`,
      url: `/looks/${doc.id}.json`,
      updatedAt: data.updatedAt?.toDate?.() ? data.updatedAt.toDate().toISOString() : new Date().toISOString(),
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

  const manifest: CatalogManifest = {
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
export const generateCatalogBundles = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
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
  } catch (err) {
    console.warn('[CatalogBundleGenerator] Local write failed or not supported in this runtime:', err);
  }

  // Upload to Cloud Storage bucket for CDN egress
  try {
    const bucket = getStorage().bucket();
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
  } catch (err) {
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
