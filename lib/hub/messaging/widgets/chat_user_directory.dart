import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../backend/user_service.dart';

/// Shared people-discovery & search queries for Oneova chat modals
/// (`UserSearchScreen`, `CreateGroupScreen`, and Group Member Picker).
class ChatUserDirectory {
  ChatUserDirectory._();

  static Future<List<AppUser>> loadSuggested({int limit = 30}) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final snap = await FirebaseFirestore.instance.collection('users').limit(limit).get();
    return snap.docs
        .map((doc) => AppUser.fromMap(doc.data(), doc.id))
        .where((u) => u.id != me && (u.fullName.trim().isNotEmpty || (u.username?.trim().isNotEmpty ?? false)))
        .toList();
  }

  static Future<List<AppUser>> search(
    String rawQuery, {
    List<AppUser> seed = const [],
    Set<String> excludeIds = const {},
  }) async {
    final q = rawQuery.trim();
    final me = FirebaseAuth.instance.currentUser?.uid;
    final exclude = <String>{...excludeIds, ?me};

    if (q.isEmpty) {
      return seed.where((u) => !exclude.contains(u.id)).toList();
    }

    final lower = q.toLowerCase();
    final cleanHandle = lower.startsWith('@') ? lower.substring(1) : lower;
    final titleCase = q.isEmpty ? q : '${q[0].toUpperCase()}${q.substring(1)}';

    final byId = <String, AppUser>{};
    for (final u in seed) {
      if (exclude.contains(u.id)) continue;
      if (_matches(u, lower, cleanHandle)) byId[u.id] = u;
    }

    final db = FirebaseFirestore.instance.collection('users');
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      if (cleanHandle.isNotEmpty)
        db
            .where('username', isGreaterThanOrEqualTo: cleanHandle)
            .where('username', isLessThanOrEqualTo: '$cleanHandle\uf8ff')
            .limit(20)
            .get(),
      db
          .where('fullName', isGreaterThanOrEqualTo: q)
          .where('fullName', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(20)
          .get(),
      if (titleCase != q)
        db
            .where('fullName', isGreaterThanOrEqualTo: titleCase)
            .where('fullName', isLessThanOrEqualTo: '$titleCase\uf8ff')
            .limit(20)
            .get(),
      if (titleCase != q)
        db
            .where('displayName', isGreaterThanOrEqualTo: titleCase)
            .where('displayName', isLessThanOrEqualTo: '$titleCase\uf8ff')
            .limit(20)
            .get(),
    ];

    final snaps = await Future.wait(queries.map((f) => f.catchError((_) async {
          return db.limit(0).get();
        })));
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        if (exclude.contains(doc.id) || byId.containsKey(doc.id)) continue;
        final user = AppUser.fromMap(doc.data(), doc.id);
        byId[doc.id] = user;
      }
    }

    // Fallback substring scan across a broader slice when prefix queries return few results.
    if (byId.length < 5) {
      try {
        final broad = await db.limit(80).get();
        for (final doc in broad.docs) {
          if (exclude.contains(doc.id) || byId.containsKey(doc.id)) continue;
          final user = AppUser.fromMap(doc.data(), doc.id);
          if (_matches(user, lower, cleanHandle)) {
            byId[doc.id] = user;
          }
        }
      } catch (_) {}
    }

    return byId.values.toList();
  }

  static bool _matches(AppUser u, String lower, String cleanHandle) {
    final name = u.fullName.toLowerCase();
    final handle = (u.username ?? '').toLowerCase();
    return name.contains(lower) ||
        (cleanHandle.isNotEmpty && handle.contains(cleanHandle));
  }
}
