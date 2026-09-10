import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatHistoryRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _messagesRef {
    if (_uid.isEmpty) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection('ai_history');
  }

  // Load chat history ordered by timestamp
  Future<List<Map<String, dynamic>>> loadHistory() async {
    if (_uid.isEmpty) return [];
    try {
      final snapshot = await _messagesRef.orderBy('timestamp', descending: false).limit(100).get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error loading chat history: $e');
      return [];
    }
  }

  // Save a message to history
  Future<void> saveMessage(Map<String, dynamic> message) async {
    if (_uid.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(message);
      data['timestamp'] = FieldValue.serverTimestamp();
      await _messagesRef.add(data);
    } catch (e) {
      print('Error saving chat message: $e');
    }
  }

  // Clear history
  Future<void> clearHistory() async {
    if (_uid.isEmpty) return;
    try {
      final snapshot = await _messagesRef.get();
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Error clearing chat history: $e');
    }
  }
}

final chatHistoryProvider = Provider<ChatHistoryRepository>((ref) {
  return ChatHistoryRepository();
});
