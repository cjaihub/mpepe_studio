import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_memory_models.dart';
import '../../settings_service.dart';

final aiMemoryServiceProvider = Provider<AiMemoryService>((ref) {
  return AiMemoryService();
});

class AiMemoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Unauthenticated access to AI Memory');
    return uid;
  }

  CollectionReference get _memoryCollection => 
      _firestore.collection('users').doc(_uid).collection('ai_memory');

  // The learning switch is the `aiPersonalization` category of the one
  // settings store, user_settings/{uid}.
  SettingsService get _settings => SettingsService(firestore: _firestore);

  /// Fetches the user's explicit learning authorization.
  Future<bool> isLearningEnabled() async {
    final settings = await _settings.getSettings(_uid);
    return (settings['aiPersonalization'] as Map?)?['learningEnabled'] == true;
  }

  /// Sets whether the AI is allowed to write to the memory graph.
  Future<void> setLearningEnabled(bool enabled) async {
    await _settings.updateSettingsCategory(_uid, 'aiPersonalization', {'learningEnabled': enabled});
  }

  /// The only permitted way for AI to write to memory.
  /// Enforces authorization and restricts to authorized categories.
  /// EXPLICIT REQUIREMENT: Must NOT silently create sensitive personality profiles.
  Future<void> authorizeMemoryWrite(AiMemoryCategory category, String value) async {
    final enabled = await isLearningEnabled();
    if (!enabled) {
      throw Exception('SECURITY_VIOLATION: AI Learning is disabled by the user.');
    }

    // AI is restricted strictly to stylistic properties. 
    // It cannot map political, religious, or sensitive personal attributes.
    final allowedCategories = AiMemoryCategory.values;
    if (!allowedCategories.contains(category)) {
      throw Exception('SECURITY_VIOLATION: Attempted to profile a restricted attribute.');
    }

    await _memoryCollection.add({
      'category': category.name,
      'value': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AiMemoryNode>> streamMemories() {
    return _memoryCollection.orderBy('updatedAt', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => AiMemoryNode.fromFirestore(d)).toList();
    });
  }

  Future<void> updateMemory(String id, String newValue) async {
    await _memoryCollection.doc(id).update({
      'value': newValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMemory(String id) async {
    await _memoryCollection.doc(id).delete();
  }

  /// Irreversibly wipes all AI memory data for the user.
  Future<void> resetAllMemories() async {
    final snap = await _memoryCollection.get();
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
