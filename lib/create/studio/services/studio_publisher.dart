import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../backend/social/models/story.dart';
import '../../../backend/social/services/story_service.dart';

/// Posts an exported Studio file as a 24h story.
class StudioPublisher {
  StudioPublisher._();

  static Future<String> publishStory({
    required StoryService stories,
    required String path,
    required bool isVideo,
    required void Function(double) onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to post a story.');
    final file = File(path);
    if (!await file.exists()) throw StateError('The exported file is no longer on this device.');

    final ext = isVideo ? 'mp4' : 'jpg';
    final now = DateTime.now();
    final ref = FirebaseStorage.instance.ref('stories/${user.uid}_${now.millisecondsSinceEpoch}.$ext');
    final task = ref.putFile(file, SettableMetadata(contentType: isVideo ? 'video/mp4' : 'image/jpeg'));
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress(0.9 * s.bytesTransferred / s.totalBytes);
    }, onError: (_) {});
    final TaskSnapshot snap;
    try {
      snap = await task;
    } finally {
      await sub.cancel();
    }
    final url = await snap.ref.getDownloadURL();

    final profile = (await FirebaseFirestore.instance.collection('users').doc(user.uid).get()).data() ?? const {};
    final name = (profile['displayName'] ?? profile['username'] ?? user.displayName ?? '').toString();
    final avatar = (profile['avatarUrl'] ?? profile['profilePhotoUrl'] ?? user.photoURL ?? '').toString();

    final story = Story(
      id: '${user.uid}_${now.millisecondsSinceEpoch}',
      authorId: user.uid,
      authorName: name,
      authorAvatarUrl: avatar,
      mediaType: isVideo ? StoryMediaType.video : StoryMediaType.photo,
      mediaUrl: url,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      privacy: StoryPrivacy.public,
      lifecycle: StoryLifecycle.active,
    );
    await stories.createStory(story);
    onProgress(1);
    return story.id;
  }
}
