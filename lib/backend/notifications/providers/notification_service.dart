import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import '../../../auth/auth_repository.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationFilter extends Notifier<String> {
  @override
  String build() => 'All';
  void setFilter(String value) => state = value;
}
final notificationFilterProvider = NotifierProvider<NotificationFilter, String>(NotificationFilter.new);

class NotificationLimit extends Notifier<int> {
  @override
  int build() => 20;
  void setLimit(int value) => state = value;
  void increment(int amount) => state = state + amount;
}
final notificationLimitProvider = NotifierProvider<NotificationLimit, int>(NotificationLimit.new);

final notificationsStreamProvider = StreamProvider<List<AppNotification>>((ref) {
  final filter = ref.watch(notificationFilterProvider);
  final limit = ref.watch(notificationLimitProvider);
  return ref.watch(notificationServiceProvider).streamNotifications(filter: filter, limit: limit);
});

final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  ref.watch(authStateProvider.select((a) => a.value?.uid));
  return ref.watch(notificationServiceProvider).streamUnreadCount();
});

final notificationPreferencesProvider = StreamProvider<NotificationPreferences>((ref) {
  ref.watch(authStateProvider.select((a) => a.value?.uid));
  return ref.watch(notificationServiceProvider).streamPreferences();
});

/// Full inbox for the notification panel (newest first). Filtering happens in
/// the panel so switching chips is instant and needs no extra indexes.
final notificationInboxProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  ref.watch(authStateProvider.select((a) => a.value?.uid));
  final limit = ref.watch(notificationLimitProvider);
  return ref.watch(notificationServiceProvider).streamInbox(limit: limit + 80);
});

/// Notifications that arrive after the app opened — drives the in-app banner
/// and ring. Only `added` changes are emitted, so nothing replays on launch.
final incomingNotificationProvider = StreamProvider<AppNotification>((ref) {
  ref.watch(authStateProvider.select((a) => a.value?.uid));
  return ref.watch(notificationServiceProvider).streamIncoming();
});

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns the current user ID, or null if not authenticated.
  /// All stream methods guard against null to prevent PERMISSION_DENIED errors.
  String? get _currentUserId => _auth.currentUser?.uid;

  Stream<List<AppNotification>> streamNotifications({String filter = 'All', int limit = 20}) {
    final uid = _currentUserId;
    // Guard: return empty stream if not authenticated
    if (uid == null) return const Stream.empty();

    Query query = _firestore.collection('notifications').where('userId', isEqualTo: uid);

    if (filter != 'All') {
      if (filter == 'Messages') {
        query = query.where('category', isEqualTo: AppNotificationCategory.newMessage.name);
      } else if (filter == 'Mentions') {
        query = query.where('category', isEqualTo: AppNotificationCategory.mention.name);
      } else if (filter == 'Priority') {
        query = query.where('priority', whereIn: [AppNotificationPriority.high.name, AppNotificationPriority.urgent.name]);
      } else if (filter == 'System') {
        query = query.where('category', isEqualTo: AppNotificationCategory.system.name);
      }
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs
              .map((doc) => AppNotification.fromFirestore(doc))
              .toList();
              
          // Deduplication logic: If multiple notifications share the same groupId 
          // within the last 24 hours, only show the most recent one.
          final Map<String, AppNotification> deduplicated = {};
          final List<AppNotification> result = [];
          
          for (final notif in notifications) {
            if (notif.groupId != null) {
              if (!deduplicated.containsKey(notif.groupId)) {
                deduplicated[notif.groupId!] = notif;
                result.add(notif);
              }
            } else {
              result.add(notif);
            }
          }
          
          return result;
        });
  }

  Stream<List<AppNotification>> streamInbox({int limit = 100}) {
    final uid = _currentUserId;
    if (uid == null) return Stream.value(const []);
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromFirestore).toList());
  }

  Stream<AppNotification> streamIncoming() {
    final uid = _currentUserId;
    if (uid == null) return const Stream.empty();
    // Small clock-skew allowance so a write landing as we subscribe still rings.
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(seconds: 5)));
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .expand((s) => s.docChanges
            .where((c) => c.type == DocumentChangeType.added)
            .map((c) => AppNotification.fromFirestore(c.doc))
            .where((n) => !n.isRead));
  }

  /// Toggle one category (AppNotificationCategory.name) on or off.
  Future<void> setCategoryEnabled(String category, bool enabled) async {
    final uid = _currentUserId;
    if (uid == null) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .set({
      'categoryOverrides': {category: enabled},
    }, SetOptions(merge: true));
  }

  /// Merge a few preference fields without rewriting the whole document.
  Future<void> updatePreferenceFields(Map<String, dynamic> fields) async {
    final uid = _currentUserId;
    if (uid == null) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .set(fields, SetOptions(merge: true));
  }

  Stream<NotificationPreferences> streamPreferences() {
    final uid = _currentUserId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .snapshots()
        .map((doc) => NotificationPreferences.fromFirestore(doc));
  }

  Future<void> updatePreferences(NotificationPreferences prefs) async {
    final uid = _currentUserId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .set(prefs.toMap(), SetOptions(merge: true));
  }

  Stream<int> streamUnreadCount() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value(0);

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markAsRead(String notificationId) async {
    if (_currentUserId == null) return;
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  Future<void> markAllAsRead() async {
    final uid = _currentUserId;
    if (uid == null) return;

    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();

    for (var i = 0; i < snapshot.docs.length; i += 450) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs.skip(i).take(450)) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  Future<void> markAsUnread(String notificationId) async {
    if (_currentUserId == null) return;
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': false,
    });
  }

  /// Clear everything the user has already read.
  Future<int> clearRead() async {
    final uid = _currentUserId;
    if (uid == null) return 0;
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: true)
        .limit(400)
        .get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return snapshot.docs.length;
  }

  Future<void> deleteNotification(String notificationId) async {
    if (_currentUserId == null) return;
    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  Future<NotificationPreferences> getPreferences() async {
    final uid = _currentUserId;
    if (uid == null) return NotificationPreferences();

    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .get();
    if (!doc.exists) {
      return NotificationPreferences();
    }
    return NotificationPreferences.fromFirestore(doc);
  }
}
