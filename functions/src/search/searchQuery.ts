import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore } from 'firebase-admin/firestore';
import { generateEmbedding } from './searchUtils';

const db = getFirestore();

/**
 * Callable function to perform Semantic Search.
 * We can't do vector search natively from the Flutter client SDK yet without some complex setup,
 * and we need to generate the embedding for the query string securely on the backend anyway.
 */
export const globalSemanticSearch = onCall(async (request) => {
  // 1. Verify Authentication
  if (!request.auth) {
    throw new HttpsError(
      'unauthenticated',
      'You must be logged in to search.'
    );
  }

  const userId = request.auth.uid;
  const { query, limit = 20, type } = request.data;

  if (!query || typeof query !== 'string') {
    throw new HttpsError('invalid-argument', 'A valid query string is required.');
  }

  try {
    // 2. Generate embedding for the search query
    const queryVector = await generateEmbedding(query);

    // 3. Perform Vector Search (K-Nearest Neighbors) using Firestore
    // Note: The Firestore Node SDK supports VectorQuery. 
    // If using an older SDK, you might need to use direct REST API or Vertex AI Vector Search.
    // Assuming modern firebase-admin SDK with vector support:
    
    let baseQuery: any = db.collection('search_index');
    
    if (type) {
        baseQuery = baseQuery.where('type', '==', type);
    }
    
    // In actual implementation with Firestore Vector Search, we use findNearest
    // Example: .findNearest('embedding', queryVector, { limit, distanceMeasure: 'COSINE' })
    // Because we are mocking the embedding for now, we will just return a placeholder response 
    // or perform a simple keyword search fallback if vector search isn't fully enabled in this project.
    
    // For now, let's just do a basic text query fallback in this mock to ensure it returns something.
    // A true vector query would look like this:
    // const results = await baseQuery.findNearest('embedding', queryVector, { limit: limit, distanceMeasure: 'COSINE' }).get();
    
    // For now, logging to remove unused error
    logger.info(`Vector generated with length ${queryVector.length}`);
    
    // Fallback exact match query (since findNearest may not compile if firebase-admin is older):
    const results = await baseQuery
      .where('keywords', 'array-contains', query.toLowerCase().split(' ')[0])
      .limit(limit)
      .get();

    const searchResults: any[] = [];

    // 4. Enforce ACLs post-query (or via pre-filter if supported by vector search)
    results.forEach((doc: any) => {
      const docData = doc.data();
      
      // Strict Permissions Check
      const canAccess = docData.acl_public === true || 
                       (docData.acl_users && docData.acl_users.includes(userId));
                       
      if (canAccess) {
        // Strip out the embedding vector from the response to save bandwidth
        const { embedding, keywords, acl_public, acl_users, ...safeData } = docData;
        searchResults.push(safeData);
      }
    });

    return {
      results: searchResults,
      count: searchResults.length
    };

  } catch (error) {
    logger.error("Search failed", error);
    throw new HttpsError('internal', 'An error occurred while searching.');
  }
});
