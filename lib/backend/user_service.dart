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
  /// Oneova ID levels, written only by the server: 2 = ID verified.
  final int identityLevel;
  /// 1 = registered business, 2 = Verified Business.
  final int businessLevel;

  /// Ova Guard notes on this profile (server-written): `impersonationOf`
  /// (uid of the verified account whose name it copies) and `bio`
  /// (link/scam verdict for the bio and website).
  final Map<String, dynamic>? safety;
  final bool isBusiness;
  final String? location;
  final DateTime createdAt;
  final String? fcmToken;
  final PrivacyMode defaultPrivacyMode;
  final AiVoicePersonalizationMetadata aiVoicePersonalization;
  final String? pronouns;
  final List<Map<String, String>> links;
  final String? category;
  final String accountType;
  final Map<String, dynamic>? businessDetails;
  final List<String> pinnedPostIds;
  final bool isPrivate;
  final DateTime? usernameLastChangedAt;
  final String? badgeTier;

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
    this.identityLevel = 0,
    this.businessLevel = 0,
    this.safety,
    this.isBusiness = false,
    this.location,
    required this.createdAt,
    this.fcmToken,
    this.defaultPrivacyMode = PrivacyMode.public,
    this.aiVoicePersonalization = const AiVoicePersonalizationMetadata(),
    this.pronouns,
    this.links = const [],
    this.category,
    this.accountType = 'personal',
    this.businessDetails,
    this.pinnedPostIds = const [],
    this.isPrivate = false,
    this.usernameLastChangedAt,
    this.badgeTier,
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
      // Contact details may live in users/{uid}/private/contact; your own
      // e-mail is always on your Firebase account.
      email: (map['email'] as String?) ??
          (FirebaseAuth.instance.currentUser?.uid == id ? FirebaseAuth.instance.currentUser?.email : null) ??
          '',
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
      identityLevel: (map['identityLevel'] as num?)?.toInt() ?? 0,
      businessLevel: (map['businessLevel'] as num?)?.toInt() ?? 0,
      safety: map['safety'] is Map ? Map<String, dynamic>.from(map['safety'] as Map) : null,
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
      pronouns: map['pronouns'] as String?,
      links: (map['links'] as List?)
              ?.map((e) => e is Map ? Map<String, String>.from(e.map((k, v) => MapEntry(k.toString(), v.toString()))) : <String, String>{})
              .toList() ??
          const [],
      category: map['category'] as String?,
      accountType: map['accountType'] as String? ?? (map['isBusiness'] == true ? 'business' : 'personal'),
      businessDetails: map['businessDetails'] is Map ? Map<String, dynamic>.from(map['businessDetails']) : null,
      pinnedPostIds: (map['pinnedPostIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      isPrivate: map['isPrivate'] as bool? ?? false,
      usernameLastChangedAt: (map['usernameLastChangedAt'] as Timestamp?)?.toDate(),
      badgeTier: map['badgeTier'] as String?,
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
      if (identityLevel > 0) 'identityLevel': identityLevel,
      if (businessLevel > 0) 'businessLevel': businessLevel,
      'isBusiness': isBusiness,
      if (location != null) 'location': location,
      'createdAt': FieldValue.serverTimestamp(),
      if (pronouns != null) 'pronouns': pronouns,
      'links': links,
      if (category != null) 'category': category,
      'accountType': accountType,
      if (businessDetails != null) 'businessDetails': businessDetails,
      'pinnedPostIds': pinnedPostIds,
      'isPrivate': isPrivate,
      if (usernameLastChangedAt != null)
        'usernameLastChangedAt': Timestamp.fromDate(usernameLastChangedAt!),
      if (badgeTier != null) 'badgeTier': badgeTier,
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

  Future<bool> isUsernameAvailable(String username, String currentUid) async {
    final clean = username.trim().toLowerCase().replaceAll('@', '');
    if (clean.length < 3) return false;
    try {
      final snap = await _firestore
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return true;
      return snap.docs.first.id == currentUid;
    } catch (e) {
      debugPrint('Error checking username: $e');
      return false;
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
