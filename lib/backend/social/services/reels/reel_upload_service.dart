import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/content.dart';

final reelUploadServiceProvider = Provider<ReelUploadService>((ref) {
  return ReelUploadService(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    FirebaseAuth.instance,
  );
});

/// Progress of one reel upload, for the UI.
class ReelUploadProgress {
  final String contentId;
  final double fraction; // 0..1 of the file upload
  final ContentStatus status;
  const ReelUploadProgress(this.contentId, this.fraction, this.status);
}

/// Posts a reel:
///  1. creates content/{id} with status `uploading` (allowed by rules only
///     for the signed-in author, with an empty mediaUrl and zero counts);
///  2. uploads the raw file to reels/uploads/{uid}/{id}/original.<ext>.
///     Firebase Storage uploads are chunked and resume after short drops;
///  3. the server transcodes it and flips the status to `ready`.
///
/// The creator can leave the screen as soon as step 2 finishes; [watch]
/// reports when the reel is live.
class ReelUploadService {
  ReelUploadService(this._db, this._storage, this._auth);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  Stream<ReelUploadProgress> upload(
    File video, {
    required String description,
    List<String> hashtags = const [],
    String visibility = 'public',
  }) async* {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to post a reel.');

    final ref = _db.collection('content').doc();
    final content = Content(
      id: ref.id,
      authorId: uid,
      description: description,
      type: ContentType.short_video,
      mediaUrl: '',
      mediaMetadata: MediaMetadata(),
      hashtags: hashtags,
      visibility: visibility,
      createdAt: DateTime.now(),
      status: ContentStatus.uploading,
    );
    // algorithmicScore starts at 0 so the For You query (ordered by it)
    // can include new reels at all.
    await ref.set({...content.toMap(), 'algorithmicScore': 0});

    final ext = _extensionOf(video.path);
    final task = _storage
        .ref('reels/uploads/$uid/${ref.id}/original.$ext')
        .putFile(video, SettableMetadata(contentType: _mimeFor(ext)));

    await for (final snap in task.snapshotEvents) {
      final total = snap.totalBytes == 0 ? 1 : snap.totalBytes;
      yield ReelUploadProgress(ref.id, snap.bytesTransferred / total, ContentStatus.uploading);
      if (snap.state == TaskState.error || snap.state == TaskState.canceled) {
        throw StateError('Upload ${snap.state.name}');
      }
    }
    yield ReelUploadProgress(ref.id, 1, ContentStatus.processing);
  }

  /// Live status of a posted reel (processing -> ready / failed).
  Stream<ContentStatus> watch(String contentId) => _db
      .collection('content')
      .doc(contentId)
      .snapshots()
      .map((s) => Content.fromFirestore(s).status);

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'mp4';
  }

  String _mimeFor(String ext) => switch (ext) {
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        'mkv' => 'video/x-matroska',
        '3gp' => 'video/3gpp',
        _ => 'video/mp4',
      };
}
