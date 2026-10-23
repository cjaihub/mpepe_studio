import 'package:cloud_firestore/cloud_firestore.dart';

class SavedCollection {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final String? coverImageUrl;
  final bool isPrivate;
  final int itemCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavedCollection({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.coverImageUrl,
    this.isPrivate = true,
    this.itemCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SavedCollection.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SavedCollection(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      description: data['description'],
      coverImageUrl: data['coverImageUrl'],
      isPrivate: data['isPrivate'] ?? true,
      itemCount: data['itemCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'isPrivate': isPrivate,
      'itemCount': itemCount,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
