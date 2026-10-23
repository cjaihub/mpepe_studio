import * as logger from 'firebase-functions/logger';

// Basic tokenization for Firestore array-contains search
export function generateKeywords(text: string): string[] {
  if (!text) return [];
  
  // Convert to lowercase and split by non-word characters
  const words = text.toLowerCase().split(/[\s,.\-!?"'()[\]{}<>]+/).filter(w => w.length > 0);
  
  const keywords = new Set<string>();
  
  for (const word of words) {
    keywords.add(word);
    // Simple prefixes for partial matching (e.g., typing "hell" matches "hello")
    for (let i = 2; i <= word.length; i++) {
      keywords.add(word.substring(0, i));
    }
  }
  
  // Limit to prevent excessive index size
  const maxKeywords = 1000;
  return Array.from(keywords).slice(0, maxKeywords);
}

/**
 * Utility to generate vector embeddings using Google Gen AI via Vertex AI.
 * This is used for Semantic Search if enabled.
 */
export async function generateEmbedding(text: string): Promise<number[]> {
  try {
    // const auth = new GoogleAuth({
    //   scopes: 'https://www.googleapis.com/auth/cloud-platform',
    // });
    
    // const projectId = await auth.getProjectId();
    // const client = await auth.getClient();
    
    // Using Vertex AI textembedding-gecko or similar model
    // Note: If you have configured `@google/genai` or Vertex AI SDK, you can use that directly.
    // For now, this is a placeholder that returns a dummy embedding for compilation.
    // In production, implement a real call to Vertex AI `text-multilingual-embedding-002`.
    
    logger.info(`Generating embedding for text length: ${text.length}`);
    
    // Placeholder returning a 768-dimensional zero vector
    return new Array(768).fill(0);
  } catch (error) {
    logger.error("Failed to generate embedding", error);
    return [];
  }
}
