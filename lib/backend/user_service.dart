import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'security/models/privacy_enums.dart';

/// Consent + storage metadata for the user's AI voice personalization sample.
class AiVoicePersonalizationMetadata {
  final bool enabled;
  final DateTime? consentGrantedAt;
  final String? sampleStoragePath;

  const AiVoicePersonalizationMetadata({
    this.enabled = false,
    this.consentGrantedAt,
    this.sampleStoragePath,
  });

  factory AiVoicePersonalizationMetadata.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AiVoicePersonalizationMetadata();
    return AiVoicePersonalizationMetadata(
      enabled: map['enabled'] as bool? ?? false,
      consentGrantedAt: (map['consentGrantedAt'] as Timestamp?)?.toDate(),
      sampleStoragePath: map['sampleStoragePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'consentGrantedAt':
          consentGrantedAt != null ? Timestamp.fromDate(consentGrantedAt!) : null,
      'sampleStoragePath': sampleStoragePath,
    };
  }
}

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
  final String? profilePhotoUrl;
  final String? username;
  final String? bio;
  final String? coverPhotoUrl;
  final bool isVerified;
  final bool isBusiness;
  final String? location;
  final DateTime createdAt;
  final String? fcmToken;
  final PrivacyMode defaultPrivacyMode;
  final AiVoicePersonalizationMetadata aiVoicePersonalization;

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
    this.profilePhotoUrl,
    this.username,
    this.bio,
    this.coverPhotoUrl,
    this.isVerified = false,
    this.isBusiness = false,
    this.location,
    required this.createdAt,
    this.fcmToken,
    this.defaultPrivacyMode = PrivacyMode.public,
    this.aiVoicePersonalization = const AiVoicePersonalizationMetadata(),
  });

  String? get photoUrl => profilePhotoUrl;

  factory AppUser.fromMap(Map<String, dynamic> map, String id) {
    return AppUser(
      id: id,
      fullName: (map['fullName'] as String?)?.isNotEmpty == true
          ? map['fullName']
          : (map['displayName'] as String?)?.isNotEmpty == true
              ? map['displayName']
              : (map['username'] as String?)?.isNotEmpty == true
                  ? map['username']
                  : (map['name'] as String?) ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? '',
      department: map['department'] ?? '',
      status: map['status'] ?? 'pending',
      jobTitle: map['jobTitle'],
      position: map['position'],
      preferredLanguage: map['preferredLanguage'] ?? 'en',
      themeMode: map['themeMode'] ?? 'system',
      lastActiveRoute: map['lastActiveRoute'] ?? '/',
      profilePhotoUrl: map['profilePhotoUrl'] ?? map['photoUrl'] ?? map['avatarUrl'],
      username: map['username'],
      bio: map['bio'],
      coverPhotoUrl: map['coverPhotoUrl'],
      isVerified: map['isVerified'] ?? false,
      isBusiness: map['isBusiness'] ?? false,
      location: map['location'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fcmToken: map['fcmToken'] as String?,
      defaultPrivacyMode: PrivacyMode.values.firstWhere(
        (e) => e.name == map['defaultPrivacyMode'],
        orElse: () => PrivacyMode.public,
      ),
      aiVoicePersonalization: AiVoicePersonalizationMetadata.fromMap(
        map['aiVoicePersonalization'] as Map<String, dynamic>?,
      ),
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
      if (bio != null) 'bio': bio,
      if (coverPhotoUrl != null) 'coverPhotoUrl': coverPhotoUrl,
      'isVerified': isVerified,
      'isBusiness': isBusiness,
      if (location != null) 'location': location,
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

final currentUserProfileProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) {
    if (!doc.exists || doc.data() == null) return null;
    return AppUser.fromMap(doc.data()!, doc.id);
  });
});
