import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/oneova_draft_model.dart';

final oneovaDraftEngineProvider =
    NotifierProvider<OneovaDraftEngine, List<OneovaDraft>>(() {
  return OneovaDraftEngine();
});

class OneovaDraftEngine extends Notifier<List<OneovaDraft>> {
  static const String _manifestFileName = 'oneova_drafts_manifest.json';
  Directory? _draftsDir;
  Directory? _mediaDir;

  @override
  List<OneovaDraft> build() {
    _initializeAndLoad();
    return [];
  }

  Future<void> _initializeAndLoad() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _draftsDir = Directory('${docDir.path}/oneova_drafts');
      _mediaDir = Directory('${docDir.path}/oneova_media');

      if (!await _draftsDir!.exists()) {
        await _draftsDir!.create(recursive: true);
      }
      if (!await _mediaDir!.exists()) {
        await _mediaDir!.create(recursive: true);
      }

      final manifestFile = File('${_draftsDir!.path}/$_manifestFileName');
      if (await manifestFile.exists()) {
        final content = await manifestFile.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          final loaded = list
              .map((e) => OneovaDraft.fromMap(Map<String, dynamic>.from(e)))
              .toList();
          // Sort by newest updated
          loaded.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          state = loaded;
        }
      }

      // Also listen to or sync with Firestore studio_projects for cloud-persisted drafts
      _syncFromFirestore();
    } catch (e) {
      debugPrint('[OneovaDraftEngine] Failed to initialize drafts: $e');
    }
  }

  Future<void> _syncFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('studio_projects')
          .where('ownerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'Draft')
          .get();

      final existingIds = state.map((d) => d.id).toSet();
      final List<OneovaDraft> cloudDrafts = [];

      for (var doc in snapshot.docs) {
        if (!existingIds.contains(doc.id)) {
          final data = doc.data();
          if (data.containsKey('mediaPath') && data['mediaPath'] != null) {
            cloudDrafts.add(OneovaDraft.fromMap({...data, 'id': doc.id}));
          }
        }
      }

      if (cloudDrafts.isNotEmpty) {
        state = [...state, ...cloudDrafts]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _persistManifest();
      }
    } catch (e) {
      debugPrint('[OneovaDraftEngine] Cloud sync notice: $e');
    }
  }

  /// Safely copies any raw temporary media file into persistent app storage
  Future<String> persistMediaFile(String sourcePath, {bool isVideo = true}) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return sourcePath;
      }

      final docDir = await getApplicationDocumentsDirectory();
      _mediaDir ??= Directory('${docDir.path}/oneova_media');
      if (!await _mediaDir!.exists()) {
        await _mediaDir!.create(recursive: true);
      }

      final ext = isVideo ? '.mp4' : '.jpg';
      final newFileName = 'media_${const Uuid().v4()}$ext';
      final targetFile = File('${_mediaDir!.path}/$newFileName');

      await sourceFile.copy(targetFile.path);
      return targetFile.path;
    } catch (e) {
      debugPrint('[OneovaDraftEngine] Error persisting media: $e');
      return sourcePath;
    }
  }

  /// Creates a new persistent draft from freshly captured or imported media
  Future<OneovaDraft> createDraftFromMedia({
    required String sourcePath,
    required bool isVideo,
    String? title,
    double durationSeconds = 0.0,
    double trimStartSeconds = 0.0,
    double trimEndSeconds = 0.0,
    double speedMultiplier = 1.0,
    double aspectRatio = 9 / 16,
  }) async {
    final persistentPath = await persistMediaFile(sourcePath, isVideo: isVideo);
    final now = DateTime.now();
    final draftId = const Uuid().v4();

    final draftTitle = title ??
        (isVideo
            ? 'Video Project ${now.day}/${now.month}'
            : 'Photo Project ${now.day}/${now.month}');

    final newDraft = OneovaDraft(
      id: draftId,
      title: draftTitle,
      mediaPath: persistentPath,
      thumbnailPath: !isVideo ? persistentPath : null,
      isVideo: isVideo,
      durationSeconds: durationSeconds,
      trimStartSeconds: trimStartSeconds,
      trimEndSeconds: trimEndSeconds,
      speedMultiplier: speedMultiplier,
      aspectRatio: aspectRatio,
      createdAt: now,
      updatedAt: now,
    );

    await saveDraft(newDraft);
    return newDraft;
  }

  /// Updates or inserts a draft, saving locally and backing up to Firestore
  Future<void> saveDraft(OneovaDraft draft) async {
    final updatedDraft = draft.copyWith(updatedAt: DateTime.now());
    final index = state.indexWhere((d) => d.id == updatedDraft.id);

    if (index >= 0) {
      final list = [...state];
      list[index] = updatedDraft;
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = list;
    } else {
      state = [updatedDraft, ...state];
    }

    await _persistManifest();
    _backupToFirestore(updatedDraft);
  }

  Future<void> _persistManifest() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _draftsDir ??= Directory('${docDir.path}/oneova_drafts');
      if (!await _draftsDir!.exists()) {
        await _draftsDir!.create(recursive: true);
      }

      final manifestFile = File('${_draftsDir!.path}/$_manifestFileName');
      final jsonString = jsonEncode(state.map((d) => d.toMap()).toList());
      await manifestFile.writeAsString(jsonString);
    } catch (e) {
      debugPrint('[OneovaDraftEngine] Error writing manifest: $e');
    }
  }

  Future<void> _backupToFirestore(OneovaDraft draft) async {
    final user = FirebaseAuth.instance.currentUser;
    final ownerId = user?.uid ?? 'guest';

    try {
      await FirebaseFirestore.instance
          .collection('studio_projects')
          .doc(draft.id)
          .set({
        ...draft.toMap(),
        'ownerId': ownerId,
        'status': 'Draft',
        'category': draft.isVideo ? 'Video' : 'Photo',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[OneovaDraftEngine] Background Firestore backup notice: $e');
    }
  }

  Future<void> deleteDraft(String draftId) async {
    final draft = state.firstWhere(
      (d) => d.id == draftId,
      orElse: () => OneovaDraft(
        id: '',
        title: '',
        mediaPath: '',
        isVideo: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    state = state.where((d) => d.id != draftId).toList();
    await _persistManifest();

    // Clean up media file if local
    if (draft.mediaPath.isNotEmpty) {
      try {
        final file = File(draft.mediaPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    // Remove from Firestore
    try {
      await FirebaseFirestore.instance
          .collection('studio_projects')
          .doc(draftId)
          .delete();
    } catch (_) {}
  }

  Future<OneovaDraft> duplicateDraft(String draftId) async {
    final original = state.firstWhere((d) => d.id == draftId);
    final now = DateTime.now();
    final newDraft = original.copyWith(
      id: const Uuid().v4(),
      title: '${original.title} (Copy)',
      createdAt: now,
      updatedAt: now,
    );
    await saveDraft(newDraft);
    return newDraft;
  }
}
