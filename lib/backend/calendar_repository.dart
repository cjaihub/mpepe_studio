import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(FirebaseFirestore.instance);
});

final monthlyEventsProvider = StreamProvider.family<List<EventModel>, DateTime>((ref, month) {
  final repository = ref.watch(calendarRepositoryProvider);
  return repository.getEventsForMonth(month);
});

class CalendarRepository {
  final FirebaseFirestore _firestore;
  CalendarRepository(this._firestore);

  Stream<List<EventModel>> getEventsForMonth(DateTime month) {
    // A simple query getting events from the start of the month to the end of the month
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    return _firestore
        .collection('events')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList());
  }

  Future<void> addEvent(EventModel event) async {
    await _firestore.collection('events').doc(event.id).set(event.toMap());
  }

  Future<void> updateEvent(EventModel event) async {
    await _firestore.collection('events').doc(event.id).update(event.toMap());
  }

  Future<void> deleteEvent(String eventId) async {
    await _firestore.collection('events').doc(eventId).delete();
  }
}

class EventModel {
  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final List<String> assignedUsers;
  final List<String> equipmentIds;
  final String colorHex;
  final String type; // shoot, recording, meeting

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.assignedUsers,
    required this.equipmentIds,
    required this.colorHex,
    required this.type,
  });

  factory EventModel.create({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required List<String> assignedUsers,
    required List<String> equipmentIds,
    required String colorHex,
    required String type,
  }) {
    return EventModel(
      id: const Uuid().v4(),
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      assignedUsers: assignedUsers,
      equipmentIds: equipmentIds,
      colorHex: colorHex,
      type: type,
    );
  }

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      assignedUsers: List<String>.from(data['assignedUsers'] ?? []),
      equipmentIds: List<String>.from(data['equipmentIds'] ?? []),
      colorHex: data['colorHex'] ?? '#8E2DE2',
      type: data['type'] ?? 'meeting',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'assignedUsers': assignedUsers,
      'equipmentIds': equipmentIds,
      'colorHex': colorHex,
      'type': type,
    };
  }

  Color get color {
    final hexCode = colorHex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }
}
