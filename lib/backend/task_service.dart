import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class UserTask {
  final String id;
  final String title;
  final String description;
  final String assignedUserId;
  final String status;
  final String priority;
  final DateTime dueDate;
  final DateTime createdAt;

  UserTask({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedUserId,
    required this.status,
    this.priority = 'medium',
    required this.dueDate,
    required this.createdAt,
  });

  factory UserTask.fromMap(Map<String, dynamic> map, String id) {
    return UserTask(
      id: id,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      assignedUserId: map['assignedUserId'] ?? '',
      status: map['status'] ?? 'pending',
      priority: map['priority'] ?? 'medium',
      dueDate: (map['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'assignedUserId': assignedUserId,
      'status': status,
      'priority': priority,
      'dueDate': Timestamp.fromDate(dueDate),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class TaskService extends AsyncNotifier<List<UserTask>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<UserTask>> build() async {
    return _fetchTasks();
  }

  Future<List<UserTask>> _fetchTasks() async {
    try {
      final snapshot = await _firestore.collection('tasks').get();
      return snapshot.docs.map((doc) => UserTask.fromMap(doc.data(), doc.id)).toList();
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      return [];
    }
  }

  Future<void> createTask(UserTask task) async {
    try {
      await _firestore.collection('tasks').add(task.toMap());
      await _firestore.collection('notifications').add({
        'userId': task.assignedUserId,
        'title': 'New Task Assigned',
        'message': 'You have been assigned a new ${task.priority} priority task: ${task.title}',
        'type': 'task',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchTasks());
    } catch (e) {
      debugPrint('Error creating task: $e');
    }
  }

  Future<void> updateTaskStatus(String taskId, String newStatus) async {
    try {
      await _firestore.collection('tasks').doc(taskId).update({'status': newStatus});
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchTasks());
    } catch (e) {
      debugPrint('Error updating task status: $e');
    }
  }
}

final taskProvider = AsyncNotifierProvider<TaskService, List<UserTask>>(() {
  return TaskService();
});

final userTaskProvider = FutureProvider.family<List<UserTask>, String>((ref, arg) async {
  final firestore = FirebaseFirestore.instance;
  try {
    final query = firestore.collection('tasks').where('assignedUserId', isEqualTo: arg);
    final snapshot = await query.get();
    return snapshot.docs.map((doc) => UserTask.fromMap(doc.data(), doc.id)).toList();
  } catch (e) {
    debugPrint('Error loading tasks: $e');
    return [];
  }
});
