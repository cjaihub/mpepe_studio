import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live total of unread chat messages for the signed-in user (from Firestore `chats.unreadCounts`).
final unreadChatCountProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('chats')
      .where('participants', arrayContains: uid)
      .snapshots()
      .map((snap) {
    var total = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final archived = data['archivedUsers'];
      if (archived is List && archived.contains(uid)) continue;
      final muted = data['mutedUsers'];
      if (muted is List && muted.contains(uid)) continue;
      final counts = data['unreadCounts'];
      if (counts is Map) {
        final v = counts[uid];
        if (v is num) total += v.toInt();
      }
    }
    return total;
  });
});
