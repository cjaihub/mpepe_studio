import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final String department;
  final String status;
  final String? jobTitle;
  final String? position;
  final String preferredLanguage;
  final String themeMode;
  final String lastActiveRoute;
  final DateTime createdAt;
  final String? fcmToken;

  AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    required this.status,
    this.jobTitle,
    this.position,
    this.preferredLanguage = 'en',
    this.themeMode = 'system',
    this.lastActiveRoute = '/',
    required this.createdAt,
    this.fcmToken,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String id) {
    return AppUser(
      id: id,
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? '',
      department: map['department'] ?? '',
      status: map['status'] ?? 'pending',
      jobTitle: map['jobTitle'],
      position: map['position'],
      preferredLanguage: map['preferredLanguage'] ?? 'en',
      themeMode: map['themeMode'] ?? 'system',
      lastActiveRoute: map['lastActiveRoute'] ?? '/',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fcmToken: map['fcmToken'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'email': email,
      'role': role,
      'department': department,
      'status': status,
      if (jobTitle != null) 'jobTitle': jobTitle,
      if (position != null) 'position': position,
      'preferredLanguage': preferredLanguage,
      'themeMode': themeMode,
      'lastActiveRoute': lastActiveRoute,
      'createdAt': FieldValue.serverTimestamp(),
      // fcmToken is managed separately via FirebaseService — not written here
    };
  }
}

class UserService extends AsyncNotifier<List<AppUser>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<AppUser>> build() async {
    return _fetchUsers();
  }

  Future<List<AppUser>> _fetchUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      return snapshot.docs.map((doc) => AppUser.fromMap(doc.data(), doc.id)).toList();
    } catch (e) {
      debugPrint('Error loading users: $e');
      return [];
    }
  }

  Future<void> createUser(AppUser user) async {
    try {
      await _firestore.collection('users').doc(user.id).set(user.toMap());
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchUsers());
    } catch (e) {
      debugPrint('Error creating user: $e');
    }
  }

  Future<void> approveUser(String uid, String jobTitle, String position) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'status': 'active',
        'jobTitle': jobTitle,
        'position': position,
      });
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchUsers());
    } catch (e) {
      debugPrint('Error approving user: $e');
    }
  }

  Future<AppUser?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return AppUser.fromMap(doc.data()!, doc.id);
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
    return null;
  }

  Future<void> updateLastActiveRoute(String uid, String route) async {
    try {
      await _firestore.collection('users').doc(uid).update({'lastActiveRoute': route});
    } catch (e) {
      debugPrint('Error updating last active route: $e');
    }
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('users').doc(uid).update(updates);
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchUsers());
    } catch (e) {
      debugPrint('Error updating user profile: $e');
    }
  }

  /// Updates only the FCM token for [uid] without a full list refresh.
  Future<void> updateFCMToken(String uid, String token) async {
    try {
      await _firestore.collection('users').doc(uid).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }
}

final userProvider = AsyncNotifierProvider<UserService, List<AppUser>>(() {
  return UserService();
});
