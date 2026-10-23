import 'package:cloud_firestore/cloud_firestore.dart';

class SavedItem {
  final String id;
  final String collectionId;
  final String userId;
  final String targetId;
  final String targetType; // 'post', 'comment', 'article', 'product'
  final DateTime savedAt;
  final String? note; // Optional personal note on why it was saved

  SavedItem({
    required this.id,
    required this.collectionId,
    required this.userId,
    required this.targetId,
    required this.targetType,
    required this.savedAt,
    this.note,
  });

  factory SavedItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SavedItem(
      id: doc.id,
      collectionId: data['collectionId'] ?? '',
      userId: data['userId'] ?? '',
      targetId: data['targetId'] ?? '',
      targetType: data['targetType'] ?? 'post',
      savedAt: (data['savedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'collectionId': collectionId,
      'userId': userId,
      'targetId': targetId,
      'targetType': targetType,
      'savedAt': FieldValue.serverTimestamp(),
      'note': note,
    };
  }
}
