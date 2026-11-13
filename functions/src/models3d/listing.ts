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
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { generateVertexContent } from '../vertexAi';
import { cleanListing, priceBand } from './listingLogic';

const db = () => getFirestore();
const DAILY_LIMIT = 80;

/** Storage path of one of the caller's own shop or model photos, or null. */
export function ownPhotoPath(url: unknown, uid: string): string | null {
  if (typeof url !== 'string' || !url.startsWith('https://firebasestorage.googleapis.com/')) return null;
  const m = /\/o\/([^?]+)/.exec(url);
  if (!m) return null;
  let path: string;
  try { path = decodeURIComponent(m[1]); } catch { return null; }
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

export const shopListingDraft = onCall({ memory: '1GiB', timeoutSeconds: 90 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const paths = (Array.isArray(req.data?.imageUrls) ? req.data.imageUrls : [])
    .map((u: unknown) => ownPhotoPath(u, uid)).filter((p: string | null): p is string => !!p).slice(0, 4);
  if (paths.length === 0) throw new HttpsError('invalid-argument', 'Add a photo first.');
  const currency = String(req.data?.currency ?? 'USD').toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new HttpsError('invalid-argument', 'Unknown currency.');
  const country = String(req.data?.country ?? '').toUpperCase().slice(0, 2);
  const hint = String(req.data?.hint ?? '').trim().slice(0, 200);

  const day = new Date().toISOString().slice(0, 10);
  const limitRef = db().doc(`rateLimits/listing_${uid}_${day}`);
  const used = Number((await limitRef.get()).get('count') ?? 0);
  if (used >= DAILY_LIMIT) throw new HttpsError('resource-exhausted', 'You’ve used today’s AI drafts. Fill this one in by hand or try tomorrow.');
  await limitRef.set({ count: FieldValue.increment(1), expireAt: new Date(Date.now() + 2 * 86400_000) }, { merge: true });

  const shop = (await db().collection('biz_shops').doc(uid).get()).data() ?? {};
  const images = await Promise.all(paths.map(async (p: string) => {
    const file = getStorage().bucket().file(p);
    const [[meta], [bytes]] = await Promise.all([file.getMetadata(), file.download()]);
    return { inlineData: { mimeType: String(meta.contentType || 'image/jpeg'), data: bytes.toString('base64') } };
  }));

  const prompt = [
    'You write product listings for a seller on Oneova, a shopping app.',
    'Look at the photos (all of the same product) and describe exactly what is shown. Do not invent a brand, model number, size or material you cannot see; leave a field empty instead.',
    `Shop: ${String(shop.name ?? '').slice(0, 60)}. ${String(shop.tagline ?? '').slice(0, 90)} Categories: ${(Array.isArray(shop.categories) ? shop.categories : []).join(', ')}.`,
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
    const res = await generateVertexContent({
      contents: [{ role: 'user', parts: [...images, { text: prompt }] }],
      config: { responseMimeType: 'application/json', responseSchema: SCHEMA as any, temperature: 0.3, maxOutputTokens: 1200 },
    });
    draft = cleanListing(JSON.parse(res.text ?? '{}'));
  } catch (e: any) {
    logger.error('listing draft failed', e?.message ?? e);
    throw new HttpsError('unavailable', 'Ova couldn’t read these photos right now. Fill it in by hand or try again.');
  }
  if (!draft.name) throw new HttpsError('unavailable', 'Ova couldn’t tell what this is. Try a clearer photo.');

  // What similar products sell for on Oneova, in the same currency.
  let comparables: number[] = [];
  if (draft.category) {
    const snap = await db().collection('products')
      .where('category', '==', draft.category).where('currency', '==', currency.toLowerCase()).limit(60).get()
      .catch(() => null);
    comparables = (snap?.docs ?? [])
      .filter((d) => d.get('ownerId') !== uid && d.get('active') !== false)
      .map((d) => Number(d.get('price'))).filter((n) => n > 0);
  }
  const { price, ...rest } = draft;
  return { ...rest, currency, price: priceBand(price, comparables, currency) };
});
