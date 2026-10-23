import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_draft.dart';

final postDraftRepositoryProvider = Provider<PostDraftRepository>((ref) {
  return PostDraftRepository();
});

/// Handles persistence of creator post drafts to both Firestore and local SharedPreferences.
class PostDraftRepository {
  final FirebaseFirestore _firestore;
  static const String _localDraftsKey = 'oneova_local_post_drafts_v1';

  PostDraftRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// Saves or updates a post draft in Firestore and local storage.
  Future<void> saveDraft(PostDraft draft) async {
    final uid = _currentUserId ?? draft.userId;
    final now = DateTime.now();
    final updatedDraft = draft.copyWith(
      userId: uid,
      updatedAt: now,
    );

    // 1. Cache to local storage immediately
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_localDraftsKey);
      Map<String, dynamic> draftsMap = {};
      if (localJson != null && localJson.isNotEmpty) {
        draftsMap = jsonDecode(localJson) as Map<String, dynamic>;
      }
      draftsMap[updatedDraft.id] = {
        ...updatedDraft.toMap(),
        'updatedAt': updatedDraft.updatedAt.toIso8601String(),
        'createdAt': updatedDraft.createdAt.toIso8601String(),
      };
      await prefs.setString(_localDraftsKey, jsonEncode(draftsMap));
    } catch (e) {
      debugPrint('[PostDraftRepository] Local draft save error: $e');
    }

    // 2. Persist to Firestore if user is authenticated
    if (uid.isNotEmpty) {
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('post_drafts')
            .doc(updatedDraft.id)
            .set(updatedDraft.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('[PostDraftRepository] Firestore draft save error: $e');
      }
    }
  }

  /// Finds an existing draft matching the given mediaPath.
  Future<PostDraft?> findDraftForMedia(String mediaPath) async {
    final uid = _currentUserId;

    // 1. Check local storage first (instant)
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_localDraftsKey);
      if (localJson != null && localJson.isNotEmpty) {
        final draftsMap = jsonDecode(localJson) as Map<String, dynamic>;
        for (final entry in draftsMap.entries) {
          final data = entry.value as Map<String, dynamic>;
          if (data['mediaPath'] == mediaPath) {
            return PostDraft(
              id: entry.key,
              userId: data['userId'] as String? ?? uid ?? '',
              mediaPath: data['mediaPath'] as String? ?? mediaPath,
              isVideo: data['isVideo'] as bool? ?? true,
              title: data['title'] as String? ?? '',
              caption: data['caption'] as String? ?? '',
              coverImagePath: data['coverImagePath'] as String?,
              coverTimeMs: (data['coverTimeMs'] as num?)?.toInt() ?? 0,
              hashtags: (data['hashtags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
              collaborators: (data['collaborators'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
              taggedUsers: (data['taggedUsers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
              privacy: data['privacy'] as String? ?? 'public',
              ageRestriction: data['ageRestriction'] as String? ?? 'all',
              allowComments: data['allowComments'] as bool? ?? true,
              allowDuet: data['allowDuet'] as bool? ?? true,
              allowStitch: data['allowStitch'] as bool? ?? true,
              allowDownload: data['allowDownload'] as bool? ?? true,
              isAiGenerated: data['isAiGenerated'] as bool? ?? false,
              isBrandedContent: data['isBrandedContent'] as bool? ?? false,
              location: data['location'] as String?,
              latitude: (data['latitude'] as num?)?.toDouble(),
              longitude: (data['longitude'] as num?)?.toDouble(),
              geoRadiusTier: data['geoRadiusTier'] as String? ?? 'global',
              link: data['link'] as String?,
              destinations: (data['destinations'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const ['internal'],
              isFastTrendBoosted: data['isFastTrendBoosted'] as bool? ?? true,
              updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now(),
              createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
            );
          }
        }
      }
    } catch (_) {}

    // 2. Query Firestore
    if (uid != null && uid.isNotEmpty) {
      try {
        final snap = await _firestore
            .collection('users')
            .doc(uid)
            .collection('post_drafts')
            .where('mediaPath', isEqualTo: mediaPath)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          return PostDraft.fromFirestore(snap.docs.first);
        }
      } catch (_) {}
    }

    return null;
  }

  /// Deletes a draft from Firestore and local cache.
  Future<void> deleteDraft(String draftId) async {
    final uid = _currentUserId;

    // 1. Remove from local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_localDraftsKey);
      if (localJson != null && localJson.isNotEmpty) {
        final draftsMap = jsonDecode(localJson) as Map<String, dynamic>;
        draftsMap.remove(draftId);
        await prefs.setString(_localDraftsKey, jsonEncode(draftsMap));
      }
    } catch (_) {}

    // 2. Remove from Firestore
    if (uid != null && uid.isNotEmpty) {
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('post_drafts')
            .doc(draftId)
            .delete();
      } catch (_) {}
    }
  }

  /// Lists all drafts for the authenticated user ordered by most recently updated.
  Stream<List<PostDraft>> streamUserDrafts() {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return Stream.value([]);
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('post_drafts')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PostDraft.fromFirestore).toList());
  }
}
