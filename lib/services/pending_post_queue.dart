import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../backend/publishing/models/publishing_destination.dart';
import 'upload_service.dart';

enum PendingPostStatus { queued, uploading, linking, failed }

/// One post waiting to land. Its media is copied into app storage (the
/// editor's export may sit in a temp folder the OS can clear) and every
/// setting is kept, so the post survives a crash, a lost connection or the
/// app being closed, and goes out with the same content id when retried.
class PendingPost {
  final String id; // the content doc id it will publish as
  final String uid;
  final bool isVideo;
  final String mediaPath;
  final String? coverPath;
  final Map<String, dynamic> params;
  final String? link;
  final DateTime createdAt;
  final PendingPostStatus status;
  final double progress;
  final int attempts;
  final String? error;
  final String? linkError;

  const PendingPost({
    required this.id,
    required this.uid,
    required this.isVideo,
    required this.mediaPath,
    this.coverPath,
    required this.params,
    this.link,
    required this.createdAt,
    this.status = PendingPostStatus.queued,
    this.progress = 0,
    this.attempts = 0,
    this.error,
    this.linkError,
  });

  PendingPost copyWith({PendingPostStatus? status, double? progress, int? attempts, String? error, String? linkError, bool clearError = false}) =>
      PendingPost(
        id: id,
        uid: uid,
        isVideo: isVideo,
        mediaPath: mediaPath,
        coverPath: coverPath,
        params: params,
        link: link,
        createdAt: createdAt,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        attempts: attempts ?? this.attempts,
        error: clearError ? null : (error ?? this.error),
        linkError: linkError ?? this.linkError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'isVideo': isVideo,
        'mediaPath': mediaPath,
        'coverPath': coverPath,
        'params': params,
        'link': link,
        'createdAt': createdAt.toIso8601String(),
        // An upload cut off by the app closing resumes as queued.
        'status': status == PendingPostStatus.linking ? 'linking' : (status == PendingPostStatus.failed ? 'failed' : 'queued'),
        'attempts': attempts,
        'error': error,
      };

  static PendingPost fromJson(Map<String, dynamic> j) => PendingPost(
        id: j['id'] as String,
        uid: j['uid'] as String? ?? '',
        isVideo: j['isVideo'] as bool? ?? true,
        mediaPath: j['mediaPath'] as String,
        coverPath: j['coverPath'] as String?,
        params: Map<String, dynamic>.from(j['params'] as Map? ?? const {}),
        link: j['link'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        status: PendingPostStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => PendingPostStatus.queued),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
      );
}

final pendingPostQueueProvider = NotifierProvider<PendingPostQueue, List<PendingPost>>(PendingPostQueue.new);

/// Durable outbox for posts (Studio / MediaPreview → feed). Posting returns
/// at once; uploads run here with progress, retry by themselves when the
/// connection comes back or the app starts again, and stay until they land
/// or the creator discards them.
class PendingPostQueue extends Notifier<List<PendingPost>> {
  static const int _autoRetries = 5;

  final Set<String> _running = {};
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  bool _loaded = false;

  @override
  List<PendingPost> build() {
    ref.onDispose(() => _netSub?.cancel());
    _netSub = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((c) => c != ConnectivityResult.none)) resumeAll(onlyAuto: true);
    }, onError: (_) {});
    return const [];
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/pending_posts');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> _persist() async {
    try {
      final f = File('${(await _dir()).path}/queue.json');
      await f.writeAsString(jsonEncode([for (final p in state) p.toJson()]));
    } catch (e) {
      debugPrint('[PendingPostQueue] persist: $e');
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = File('${(await _dir()).path}/queue.json');
      if (!await f.exists()) return;
      final list = (jsonDecode(await f.readAsString()) as List).cast<Map>();
      final loaded = [
        for (final j in list) PendingPost.fromJson(Map<String, dynamic>.from(j)),
      ].where((p) => File(p.mediaPath).existsSync()).toList();
      state = [...loaded, ...state.where((p) => !loaded.any((l) => l.id == p.id))];
    } catch (e) {
      debugPrint('[PendingPostQueue] load: $e');
    }
  }

  void _put(PendingPost p) {
    state = [for (final x in state) x.id == p.id ? p : x];
  }

  PendingPost? _find(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Saves the post and starts uploading it in the background. Returns the
  /// content id it will publish as, as soon as the post is safely stored.
  Future<String> enqueue({
    required String mediaPath,
    required bool isVideo,
    String? coverPath,
    String? link,
    required Map<String, dynamic> params,
  }) async {
    await _load();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to publish.');
    final id = FirebaseFirestore.instance.collection('content').doc().id;
    final dir = await _dir();
    final ext = mediaPath.contains('.') ? mediaPath.split('.').last : (isVideo ? 'mp4' : 'jpg');
    final media = await File(mediaPath).copy('${dir.path}/$id.$ext');
    String? cover;
    if (coverPath != null && coverPath.isNotEmpty && await File(coverPath).exists()) {
      cover = (await File(coverPath).copy('${dir.path}/${id}_cover.jpg')).path;
    }
    final post = PendingPost(
      id: id,
      uid: uid,
      isVideo: isVideo,
      mediaPath: media.path,
      coverPath: cover,
      params: params,
      link: (link == null || link.trim().isEmpty) ? null : link.trim(),
      createdAt: DateTime.now(),
    );
    state = [...state, post];
    await _persist();
    unawaited(_run(id));
    return id;
  }

  /// Retries everything still waiting (app start, connection back, or the
  /// creator tapping Retry). [onlyAuto] skips posts past their auto retries.
  Future<void> resumeAll({bool onlyAuto = false}) async {
    await _load();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    for (final p in List.of(state)) {
      if (p.uid != uid) continue;
      if (onlyAuto && p.status == PendingPostStatus.failed && p.attempts >= _autoRetries) continue;
      unawaited(_run(p.id));
    }
  }

  Future<void> retry(String id) => _run(id);

  /// Drops a post that has not landed (after the creator confirms).
  Future<void> discard(String id) async {
    final p = _find(id);
    if (p == null || _running.contains(id)) return;
    _discarded++;
    state = state.where((x) => x.id != id).toList();
    await _persist();
    await _deleteFiles(p);
  }

  Future<void> _deleteFiles(PendingPost p) async {
    for (final path in [p.mediaPath, p.coverPath]) {
      if (path == null) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _run(String id) async {
    if (_running.contains(id)) return;
    var p = _find(id);
    if (p == null) return;
    _running.add(id);
    try {
      if (p.status != PendingPostStatus.linking) {
        p = p.copyWith(status: PendingPostStatus.uploading, progress: 0, attempts: p.attempts + 1, clearError: true);
        _put(p);
        final a = p.params;
        await UploadService.uploadPostInBackground(
          contentId: p.id,
          mediaPath: p.mediaPath,
          isVideo: p.isVideo,
          customCoverPath: p.coverPath,
          title: a['title'] as String?,
          caption: a['caption'] as String? ?? '',
          privacy: a['privacy'] as String? ?? 'public',
          allowComments: a['allowComments'] as bool? ?? true,
          allowDuet: a['allowDuet'] as bool? ?? true,
          allowStitch: a['allowStitch'] as bool? ?? true,
          allowRemix: a['allowRemix'] as bool? ?? (a['allowDuet'] as bool? ?? true),
          remixOf: a['remixOf'] is Map ? Map<String, dynamic>.from(a['remixOf'] as Map) : null,
          allowDownload: a['allowDownload'] as bool? ?? true,
          highQualityUploads: a['highQualityUploads'] as bool? ?? false,
          location: a['location'] as String?,
          link: p.link,
          geoRadiusTier: a['geoRadiusTier'] as String?,
          coverTimeMs: (a['coverTimeMs'] as num?)?.toInt(),
          ageRestriction: a['ageRestriction'] as String?,
          isAiGenerated: a['isAiGenerated'] as bool? ?? false,
          isBrandedContent: a['isBrandedContent'] as bool? ?? false,
          destinations: [
            for (final n in (a['destinations'] as List? ?? const []))
              ...PlatformDestination.values.where((d) => d.name == n),
          ],
          collaborators: List<String>.from(a['collaborators'] as List? ?? const []),
          taggedUserIds: List<String>.from(a['taggedUserIds'] as List? ?? const []),
          isFastTrendBoosted: a['isFastTrendBoosted'] as bool? ?? false,
          durationMs: (a['durationMs'] as num?)?.toInt(),
          aspectRatio: (a['aspectRatio'] as num?)?.toDouble(),
          onProgress: (v) {
            final cur = _find(id);
            if (cur != null) _put(cur.copyWith(progress: v * (p!.link == null ? 1 : 0.97)));
          },
        );
        p = _find(id)!.copyWith(status: PendingPostStatus.linking);
        _put(p);
        await _persist();
      }

      // The post is live; attach the destination link (validated server side).
      String? linkError;
      if (p.link != null) {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('contentSetDestination')
              .call({'contentId': p.id, 'url': p.link});
        } on FirebaseFunctionsException catch (e) {
          // A rejected link never blocks the post; network trouble retries later.
          if (e.code == 'unavailable' || e.code == 'deadline-exceeded' || e.code == 'internal' || e.code == 'not-found') {
            rethrow;
          }
          linkError = e.message;
        }
      }

      state = state.where((x) => x.id != id).toList();
      await _persist();
      await _deleteFiles(p);
      if (linkError != null) _linkRejections.add((id: id, message: linkError));
    } catch (e) {
      debugPrint('[PendingPostQueue] $id failed: $e');
      final cur = _find(id);
      if (cur != null) {
        _put(cur.copyWith(status: cur.status == PendingPostStatus.linking ? PendingPostStatus.linking : PendingPostStatus.failed,
            error: _describe(e)));
        await _persist();
      }
    } finally {
      _running.remove(id);
    }
  }

  int _discarded = 0;

  /// True once per discard, so the feed doesn't announce it as posted.
  bool takeDiscarded() {
    if (_discarded == 0) return false;
    _discarded--;
    return true;
  }

  final List<({String id, String message})> _linkRejections = [];

  /// Links the server refused for posts that went live (shown once).
  List<({String id, String message})> takeLinkRejections() {
    final out = List.of(_linkRejections);
    _linkRejections.clear();
    return out;
  }

  static String _describe(Object e) {
    if (e is FirebaseException) return 'Upload failed (${e.code}).';
    if (e is StateError) return e.message;
    return 'Upload failed. Check your connection.';
  }
}
