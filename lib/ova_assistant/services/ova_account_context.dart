import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Who Ova is talking to: the signed-in person's own account, read from their
/// profile and cached for 10 minutes. Only what helps a conversation: name,
/// handle, verification, audience size, account type, ID-check status. Never
/// balances, ID numbers, documents or other people's data.
class OvaAccountContext {
  OvaAccountContext._();
  static final OvaAccountContext instance = OvaAccountContext._();

  String? _line;
  String? _uid;
  DateTime? _at;

  Future<void> warm() async {
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _line = null;
      return;
    }
    if (_uid == user.uid && _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 10)) return;
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('users').doc(user.uid).get(),
        db.collection('kyc').doc(user.uid).get().then<DocumentSnapshot<Map<String, dynamic>>?>((d) => d, onError: (_) => null),
      ]);
      final u = results[0]?.data() ?? const {};
      final k = results[1]?.data() ?? const {};
      String? str(String key) {
        final v = u[key];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      int? count(List<String> keys) {
        for (final key in keys) {
          final v = u[key];
          if (v is num) return v.toInt();
        }
        return null;
      }

      final name = str('displayName') ?? user.displayName;
      final handle = str('username') ?? str('handle');
      final followers = count(['followerCount', 'followersCount']);
      final following = count(['followingCount']);
      final posts = count(['postsCount']);
      final verified = u['isVerified'] == true || u['verified'] == true;
      final type = str('accountType');
      final bio = str('bio');
      final kyc = k['status'] is String ? k['status'] as String : null;
      _line = [
        if (name != null) 'name $name',
        if (handle != null) '@$handle',
        if (verified) 'verified',
        if (type != null) '$type account',
        if (followers != null) '$followers followers',
        if (following != null) 'following $following',
        if (posts != null) '$posts posts',
        if (kyc != null) 'ID check: $kyc',
        if (bio != null) 'bio "${bio.length > 80 ? '${bio.substring(0, 80)}…' : bio}"',
      ].join(', ');
      _uid = user.uid;
      _at = DateTime.now();
    } catch (e) {
      debugPrint('[OvaAccountContext] $e');
    }
  }

  String contextLine() {
    final l = _line;
    return l == null || l.isEmpty ? 'Account: signed-in Oneova user.' : 'Account (the person you are talking to): $l.';
  }

  void invalidate() => _at = null;
}
