import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore } from 'firebase-admin/firestore';
import { vertexAi } from '../vertexAi';
import { limit as rateLimit } from '../guard/protect';

const db = getFirestore();

/**
 * Smart search: Gemini (Vertex AI, the function's service account) turns a
 * natural-language query ("funny cooking videos in swahili") into a few short
 * search terms and hashtags. The app runs its normal Firestore search for
 * each term (people, hashtags, posts) and merges the results, so everything
 * shown is real content the person is allowed to see. Any entries in
 * `search_index` that match a term (and pass their ACL) are returned too.
 */
async function expandQuery(query: string): Promise<string[]> {
  try {
    const res = await vertexAi().models.generateContent({
      model: 'gemini-2.5-flash',
      contents: [{ role: 'user', parts: [{ text: query.slice(0, 300) }] }],
      config: {
        systemInstruction:
          'You turn a search on a social video app into search terms. Reply ONLY with JSON {"terms":["..."]}: ' +
          'up to 5 short terms (1-2 words, lowercase), most specific first, including likely hashtags without "#" ' +
          'and the key words of the query itself. Keep the language of the query. No explanations.',
        responseMimeType: 'application/json',
        temperature: 0.2,
        maxOutputTokens: 120,
        thinkingConfig: { thinkingBudget: 0 },
      },
    });
    const parsed = JSON.parse((res.text ?? '').match(/\{[\s\S]*\}/)?.[0] ?? '{}');
    const terms: string[] = Array.isArray(parsed.terms) ? parsed.terms : [];
    return [...new Set(terms.filter((t) => typeof t === 'string').map((t) => t.trim().toLowerCase().replace(/^#/, '')).filter(Boolean))]
      .slice(0, 5);
  } catch (e: any) {
    logger.warn('query expansion failed', e?.message ?? e);
    return [];
  }
}

export const globalSemanticSearch = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'You must be logged in to search.');
  }

  const userId = request.auth.uid;
  await rateLimit(userId, 'search', 60, 60000);
  const { query, limit = 20, type } = request.data ?? {};

  if (!query || typeof query !== 'string') {
    throw new HttpsError('invalid-argument', 'A valid query string is required.');
  }

  try {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    const expanded = await expandQuery(query);
    const terms = [...new Set([...expanded, ...words])].slice(0, 6);

    let baseQuery: FirebaseFirestore.Query = db.collection('search_index');
    if (type) baseQuery = baseQuery.where('type', '==', type);

    const searchResults: Record<string, unknown>[] = [];
    if (terms.length > 0) {
      const results = await baseQuery
        .where('keywords', 'array-contains-any', terms.slice(0, 10))
        .limit(Math.min(Number(limit) || 20, 50))
        .get();
      results.forEach((doc) => {
        const docData = doc.data();
        const canAccess = docData.acl_public === true || (docData.acl_users && docData.acl_users.includes(userId));
        if (canAccess) {
          // eslint-disable-next-line @typescript-eslint/no-unused-vars
          const { embedding, keywords, acl_public, acl_users, ...safeData } = docData;
          searchResults.push({ id: doc.id, ...safeData });
        }
      });
    }

    return { results: searchResults, count: searchResults.length, terms: expanded };
  } catch (error) {
    logger.error('Search failed', error);
    throw new HttpsError('internal', 'An error occurred while searching.');
  }
});
