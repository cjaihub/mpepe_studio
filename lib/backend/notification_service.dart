import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String type; // 'task', 'system', 'social'
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map, String id) {
    return AppNotification(
      id: id,
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      type: map['type'] ?? 'system',
      isRead: map['isRead'] ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'message': message,
      'type': type,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class NotificationService extends AsyncNotifier<List<AppNotification>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final String _userId;

  @override
  Future<List<AppNotification>> build() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    _userId = currentUser?.uid ?? '';
    _initListener();
    _initFCM();
    return [];
  }

  /// Initialises FCM and saves the token to Firestore for this user.
  Future<void> _initFCM() async {
    if (_userId.isEmpty) return;
    final token = await FirebaseService.instance.initFCM(
      onForegroundMessage: (message) {
        // Create an in-app notification from the FCM message payload.
        final notification = message.notification;
        if (notification != null) {
          createNotification(AppNotification(
            id: '',
            userId: _userId,
            title: notification.title ?? '',
            message: notification.body ?? '',
            type: 'system',
            createdAt: DateTime.now(),
          ));
        }
      },
      onMessageOpenedApp: (message) {
        // Optionally navigate to a specific screen based on message data.
        // e.g. router.push(message.data['route'] ?? '/');
      },
    );
    if (token != null) {
      await FirebaseService.instance.saveFCMTokenToFirestore(
        uid: _userId,
        fcmToken: token,
      );
    }
  }

  void _initListener() {
    if (_userId.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    _firestore
        .collection('notifications')
        .where('userId', isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      final notifications = snapshot.docs.map((doc) => AppNotification.fromMap(doc.data(), doc.id)).toList();
      state = AsyncValue.data(notifications);
    }, onError: (e) {
      // ignore: avoid_print
      print('Error listening to notifications: $e');
      if (!state.hasValue) {
        state = const AsyncValue.data([]);
      }
    });
  }

  Future<void> createNotification(AppNotification notification) async {
    try {
      await _firestore.collection('notifications').add(notification.toMap());
    } catch (e) {
      // ignore: avoid_print
      print('Error creating notification: $e');
      // Optimistic update for demo mode
      if (state.hasValue) {
        state = AsyncValue.data([
          AppNotification(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: notification.userId,
            title: notification.title,
            message: notification.message,
            type: notification.type,
            isRead: false,
            createdAt: DateTime.now(),
          ),
          ...state.value!
        ]);
      }
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({'isRead': true});
    } catch (e) {
      // ignore: avoid_print
      print('Error marking notification as read: $e');
      // Optimistic fallback
      if (state.hasValue) {
        final updated = state.value!.map((n) {
          if (n.id == notificationId) {
            return AppNotification(
              id: n.id,
              userId: n.userId,
              title: n.title,
              message: n.message,
              type: n.type,
              isRead: true,
              createdAt: n.createdAt,
            );
          }
          return n;
        }).toList();
        state = AsyncValue.data(updated);
      }
    }
  }

  Future<void> markAllAsRead() async {
    try {
      if (!state.hasValue || state.value!.isEmpty) return;
      
      final batch = _firestore.batch();
      for (final n in state.value!) {
        if (!n.isRead && n.id.isNotEmpty) {
          batch.update(_firestore.collection('notifications').doc(n.id), {'isRead': true});
        }
      }
      await batch.commit();
    } catch (e) {
      // ignore: avoid_print
      print('Error marking all as read: $e');
      if (state.hasValue) {
        final updated = state.value!.map((n) => AppNotification(
              id: n.id,
              userId: n.userId,
              title: n.title,
              message: n.message,
              type: n.type,
              isRead: true,
              createdAt: n.createdAt,
            )).toList();
        state = AsyncValue.data(updated);
      }
    }
  }
}

final notificationProvider = AsyncNotifierProvider<NotificationService, List<AppNotification>>(() {
  return NotificationService(); 
});
