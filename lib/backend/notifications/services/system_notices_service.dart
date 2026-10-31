import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Friendly "system" notices for the signed-in person: a new app version,
/// a profile that is missing a few details. Each notice is a normal
/// `notifications/{id}` doc with `priority: 'low'`, so it lands in the
/// notification centre and the system tray without popping over the screen
/// (functions/src/notifications.ts writes the final copy and sends the push).
///
/// Doc ids are deterministic, so the same notice is never sent twice.
class SystemNoticesService {
  SystemNoticesService._();
  static final SystemNoticesService instance = SystemNoticesService._();

  static const Duration _profileNudgeEvery = Duration(days: 7);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// A newer version is published on Play for this person.
  Future<void> appUpdateAvailable(int versionCode) async {
    final uid = _uid;
    if (uid == null || versionCode <= 0) return;
    await _createOnce('app_update_${uid}_$versionCode', {
      'userId': uid,
      'recipientId': uid,
      'category': 'appUpdate',
      'priority': 'low',
      'title': 'A new version of Oneova is ready',
      'body': 'Update to get the latest features and fixes. It only takes a moment.',
      'groupId': 'app_update',
      'payload': {'versionCode': versionCode},
    });
  }

  /// Gently reminds the person (at most once a week) about profile details
  /// that are still missing, naming the first one or two.
  Future<void> profileIncomplete(List<String> missingTitles, int percentage) async {
    final uid = _uid;
    if (uid == null || missingTitles.isEmpty || percentage >= 100) return;
    final week = DateTime.now().millisecondsSinceEpoch ~/ _profileNudgeEvery.inMilliseconds;
    final first = missingTitles.take(2).map((t) => t.toLowerCase()).join(' and ');
    await _createOnce('profile_tip_${uid}_$week', {
      'userId': uid,
      'recipientId': uid,
      'category': 'profileTip',
      'priority': 'low',
      'title': 'Your profile is $percentage% done',
      'body': 'Add your $first so people can find and follow you. Ova can suggest ideas for you.',
      'groupId': 'profile_tip',
      'deepLink': '/profile/me',
    });
  }

  String? get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  Future<void> _createOnce(String id, Map<String, dynamic> data) async {
    try {
      final ref = _db.collection('notifications').doc(id);
      // The read rule checks resource.data, so reading a doc that does not
      // exist yet is denied: that is our "not sent yet".
      try {
        if ((await ref.get()).exists) return;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
      await ref.set({
        ...data,
        'type': 'system',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[SystemNotices] $id skipped: $e');
    }
  }
}
