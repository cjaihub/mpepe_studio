import 'package:cloud_firestore/cloud_firestore.dart';

enum AiMemoryCategory {
  tone,
  language,
  greetingStyle,
  formatting,
  emojiPreferences,
  responseLength,
  creatorStyle;
}

class AiMemoryNode {
  final String id;
  final AiMemoryCategory category;
  final String value;
  final DateTime updatedAt;

  const AiMemoryNode({
    required this.id,
    required this.category,
    required this.value,
    required this.updatedAt,
  });

  factory AiMemoryNode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AiMemoryNode(
      id: doc.id,
      category: AiMemoryCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => AiMemoryCategory.tone,
      ),
      value: data['value'] ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category.name,
      'value': value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
