import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../backend/social/models/content.dart';
import '../../shared/theme/app_theme.dart';
import '../studio/models/studio_project.dart';
import '../studio/screens/studio_editor_screen.dart';
import '../studio/services/studio_media.dart';
import '../studio/services/studio_project_store.dart';
import '../studio/widgets/studio_progress_dialog.dart';

/// Opens someone's post in Studio as a remix: checks the creator allows it,
/// downloads the original, and starts a project that carries `remixOf` so
/// the published post credits them and shares its gift earnings
/// (functions/src/remix.ts).
class RemixLauncher {
  RemixLauncher._();

  static Future<void> start(BuildContext context, Content content) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m), backgroundColor: AppColors.brandPink));
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Read the live post: the creator may have turned remixes off since.
    Content post = content;
    String authorName = '';
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db.collection('content').doc(content.id).get();
      if (!doc.exists) {
        say('This post is no longer available.');
        return;
      }
      post = Content.fromFirestore(doc);
      final author = (await db.collection('users').doc(post.authorId).get()).data() ?? const {};
      authorName = (author['username'] ?? author['displayName'] ?? author['fullName'] ?? '').toString();
    } catch (e) {
      say('Could not open this post for remixing.');
      return;
    }
    final own = post.authorId == uid;
    if (!own && post.visibility != 'public') {
      say('Only public posts can be remixed.');
      return;
    }
    if (!own && !post.permissions.allowRemix) {
      say('The creator turned off remixes for this post.');
      return;
    }
    if (post.mediaUrl.isEmpty || !post.mediaUrl.startsWith('http')) {
      say('This post has no media to remix.');
      return;
    }
    if (!context.mounted) return;

    final isImage = post.type == ContentType.photo || studioIsImagePath(Uri.parse(post.mediaUrl).path);
    final path = await runStudioTask<String>(
      context,
      title: 'Getting the original',
      task: (onProgress) => _download(post.mediaUrl, post.id, isImage, onProgress),
    );
    if (path == null || !context.mounted) return;
    try {
      final clip = await StudioMedia.clipFromFile(path, isImage: isImage);
      final project = StudioProject.create(
        isPhoto: isImage,
        clips: [clip],
        remixOf: own ? null : RemixSource(contentId: post.id, authorId: post.authorId, authorName: authorName),
      );
      if (!context.mounted) return;
      await context.push('/create/studio/editor', extra: StudioEditorArgs(project: project, target: StudioTarget.post));
    } catch (e) {
      say('Could not open the original in Studio: $e');
    }
  }

  static Future<String> _download(String url, String id, bool isImage, void Function(double) onProgress) async {
    final dir = await StudioProjectStore.dir('remix');
    final file = File('${dir.path}/remix_${id}_${DateTime.now().millisecondsSinceEpoch}.${isImage ? 'jpg' : 'mp4'}');
    final client = HttpClient();
    try {
      final resp = await (await client.getUrl(Uri.parse(url))).close();
      if (resp.statusCode != 200) throw StateError('Download failed (${resp.statusCode}).');
      final total = resp.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file.path;
    } finally {
      client.close();
    }
  }
}
