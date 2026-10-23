import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Note: In a production app, the actual embedding call to OpenRouter would go through a secure backend or cloud function to avoid exposing the API key on the client.
// We simulate the structure here.

enum MemoryType {
  PROFILE,
  COMMUNICATION,
  PREFERENCE,
  PROJECT,
  RELATIONSHIP,
  TASK,
  CREATOR,
  MEDIA,
  LOCATION,
  WORKFLOW,
  TEMPORARY_CONTEXT,
}

class SemanticMemory {
  final String id;
  final String userId;
  final MemoryType type;
  final String content;
  final String source;
  final double confidence;
  final String permission;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final bool confirmedByUser;
  // Firestore VectorValue would be here:
  // final VectorValue embedding;

  const SemanticMemory({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    required this.source,
    required this.confidence,
    required this.permission,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    required this.confirmedByUser,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'type': type.name,
      'content': content,
      'source': source,
      'confidence': confidence,
      'permission': permission,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'expires_at': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'confirmed_by_user': confirmedByUser,
      // 'embedding': VectorValue(embeddingList) // Requires vector support enabled in Firebase project
    };
  }

  factory SemanticMemory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SemanticMemory(
      id: doc.id,
      userId: data['user_id'] as String? ?? '',
      type: MemoryType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MemoryType.TEMPORARY_CONTEXT,
      ),
      content: data['content'] as String? ?? '',
      source: data['source'] as String? ?? '',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
      permission: data['permission'] as String? ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expires_at'] as Timestamp?)?.toDate(),
      confirmedByUser: data['confirmed_by_user'] as bool? ?? false,
    );
  }
}

final personalMemoryEngineProvider = Provider<PersonalMemoryEngine>((ref) {
  return PersonalMemoryEngine(FirebaseFirestore.instance);
});

class PersonalMemoryEngine {
  final FirebaseFirestore _firestore;
  
  PersonalMemoryEngine(this._firestore);

  /// 1. Embedding -> 2. Retrieval -> 3. Reranking -> 4. Context Selection
  Future<List<SemanticMemory>> retrieveRelevantMemories(String userId, String query) async {
    // ARCHITECTURE JUSTIFICATION:
    // We use Firestore's native Vector Search capability rather than introducing Pinecone or Milvus.
    // This minimizes architectural sprawl, keeps data resident where user permissions (Firestore Security Rules)
    // naturally apply, and prevents sync issues between databases.
    
    // Step 1: Generate Embedding (via OpenRouter/OpenAI API)
    // final queryEmbedding = await _openRouterApi.generateEmbedding(query);
    
    // Step 2: Retrieval (using Firestore KNN Vector Search)
    /*
    final matches = await _firestore.collection('users').doc(userId).collection('memories')
        .where('expires_at', isGreaterThanOrEqualTo: Timestamp.now()) // Or null check
        .orderBy('embedding') // Requires Vector Index
        .findNearest('embedding', queryEmbedding, limit: 10, distanceMeasure: DistanceMeasure.cosine)
        .get();
    */
    
    // Simulated Retrieval until Vector Index is deployed:
    final snapshot = await _firestore.collection('users').doc(userId).collection('memories')
        .orderBy('updated_at', descending: true)
        .limit(10)
        .get();

    final memories = snapshot.docs.map((doc) => SemanticMemory.fromFirestore(doc)).toList();
    
    // Filter out expired temporary context
    final now = DateTime.now();
    memories.removeWhere((m) => m.expiresAt != null && m.expiresAt!.isBefore(now));

    // Step 3: Optional Reranking
    // Rerank memories based on exact keyword overlap or cross-encoder model.
    
    // Step 4: Context Selection
    // Ensure we don't exceed the token budget.
    return memories;
  }

  Future<void> storeMemory(SemanticMemory memory) async {
    // In production, an embedding would be generated for `memory.content` before saving.
    await _firestore
        .collection('users')
        .doc(memory.userId)
        .collection('memories')
        .doc(memory.id.isEmpty ? null : memory.id)
        .set(memory.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteMemory(String userId, String memoryId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('memories')
        .doc(memoryId)
        .delete();
  }

  Future<void> resetAllMemories(String userId) async {
    final batch = _firestore.batch();
    final memories = await _firestore.collection('users').doc(userId).collection('memories').get();
    for (var doc in memories.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
