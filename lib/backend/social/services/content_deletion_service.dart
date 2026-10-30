import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Deletes one of the signed-in user's own posts: its comments, the
/// `content` doc, then the Storage files under `content/{uid}/`.
class ContentDeletionService {
  ContentDeletionService({FirebaseFirestore? firestore, FirebaseStorage? storage, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  /// Throws if the post is not the caller's or Firestore refuses the delete.
  /// Storage files that are already gone are ignored.
  Future<void> deleteOwnPost(String contentId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to delete posts.');
    final ref = _db.collection('content').doc(contentId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    if (data['authorId'] != uid) throw StateError('You can only delete your own posts.');

    final paths = <String>{
      for (final p in (data['storagePaths'] as List? ?? const [])) p.toString(),
      for (final url in [data['mediaUrl'], data['coverUrl']])
        if (url is String && url.isNotEmpty) ?_pathFromUrl(url),
    }.where((p) => p.startsWith('content/$uid/')).toSet();

    // Comments live in a subcollection the post owner may delete.
    while (true) {
      final page = await ref.collection('comments').limit(200).get();
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (page.docs.length < 200) break;
    }

    await ref.delete();

    for (final path in paths) {
      try {
        await _storage.ref(path).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') debugPrint('[ContentDeletionService] $path: ${e.code}');
      }
    }
  }

  String? _pathFromUrl(String url) {
    try {
      return _storage.refFromURL(url).fullPath;
    } catch (_) {
      return null;
    }
  }
}
