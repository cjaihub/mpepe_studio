import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EquipmentStatus { available, checkedOut, maintenance }

class EquipmentItem {
  final String id;
  final String name;
  final String category; // e.g., 'Camera', 'Lens', 'Lighting', 'Audio'
  final String imageUrl;
  final EquipmentStatus status;
  final String? checkedOutBy;
  final DateTime? returnDate;

  EquipmentItem({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    this.status = EquipmentStatus.available,
    this.checkedOutBy,
    this.returnDate,
  });

  factory EquipmentItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EquipmentItem(
      id: doc.id,
      name: data['name'] ?? '',
      category: data['category'] ?? 'Other',
      imageUrl: data['imageUrl'] ?? '',
      status: EquipmentStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => EquipmentStatus.available,
      ),
      checkedOutBy: data['checkedOutBy'],
      returnDate: data['returnDate'] != null ? (data['returnDate'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'imageUrl': imageUrl,
      'status': status.toString().split('.').last,
      'checkedOutBy': checkedOutBy,
      'returnDate': returnDate != null ? Timestamp.fromDate(returnDate!) : null,
    };
  }
}

class EquipmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<EquipmentItem>> getEquipmentStream() {
    return _firestore.collection('equipment').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => EquipmentItem.fromFirestore(doc)).toList();
    });
  }

  Future<void> addEquipment(EquipmentItem item) async {
    await _firestore.collection('equipment').doc(item.id).set(item.toMap());
  }

  Future<void> updateEquipmentStatus(String id, EquipmentStatus status, {String? userId, DateTime? returnDate}) async {
    await _firestore.collection('equipment').doc(id).update({
      'status': status.toString().split('.').last,
      'checkedOutBy': userId,
      'returnDate': returnDate != null ? Timestamp.fromDate(returnDate) : null,
    });
  }
}

final equipmentRepositoryProvider = Provider((ref) => EquipmentRepository());

final equipmentStreamProvider = StreamProvider<List<EquipmentItem>>((ref) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.getEquipmentStream();
});
