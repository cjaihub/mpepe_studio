import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/auth_repository.dart';
import '../models/oneova_look.dart';
import '../services/cinema_presets_migration_service.dart';

/// Repository handling Firestore operations for looks, presets, and live profiles.
class LooksRepository {
  final FirebaseFirestore? _explicitFirestore;

  LooksRepository({FirebaseFirestore? firestore}) : _explicitFirestore = firestore;

  FirebaseFirestore? get firestore {
    if (_explicitFirestore != null) return _explicitFirestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Stream of user-owned looks.
  Stream<List<OneovaLook>> streamUserLooks(String uid) {
    final fs = firestore;
    if (uid.isEmpty || fs == null) return Stream.value(const []);
    return fs
        .collection('users')
        .doc(uid)
        .collection('looks')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => OneovaLook.fromMap(doc.data()))
            .toList());
  }

  /// Stream of public catalog looks by category.
  Stream<List<OneovaLook>> streamCatalogLooks({String? category}) {
    final fs = firestore;
    if (fs == null) return Stream.value(const []);
    Query query = fs.collection('lookCatalog');
    if (category != null && category.isNotEmpty && category != 'All') {
      query = query.where('categories', arrayContains: category.toLowerCase());
    }
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => OneovaLook.fromMap(doc.data() as Map<String, dynamic>))
        .toList());
  }

  /// Stream of live scenes for a host.
  Stream<List<Map<String, dynamic>>> streamLiveScenes(String uid) {
    final fs = firestore;
    if (uid.isEmpty || fs == null) return Stream.value(const []);
    return fs
        .collection('users')
        .doc(uid)
        .collection('liveScenes')
        .orderBy('order', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  /// Stream of saved live profiles for a host.
  Stream<List<Map<String, dynamic>>> streamLiveProfiles(String uid) {
    final fs = firestore;
    if (uid.isEmpty || fs == null) return Stream.value(const []);
    return fs
        .collection('users')
        .doc(uid)
        .collection('liveProfiles')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  CollectionReference<Map<String, dynamic>>? _user(String uid, String sub) =>
      firestore?.collection('users').doc(uid).collection(sub);

  List<Map<String, dynamic>> _withIds(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => {'id': d.id, ...d.data()}).toList();

  /// Folders the user groups looks into (`users/{uid}/lookFolders`).
  Stream<List<Map<String, dynamic>>> streamLookFolders(String uid) {
    final u = _user(uid, 'lookFolders');
    if (uid.isEmpty || u == null) return Stream.value(const []);
    return u.orderBy('order').snapshots().map(_withIds);
  }

  Future<void> saveLookFolder(String uid, String folderId, Map<String, dynamic> data) async {
    final u = _user(uid, 'lookFolders');
    if (u == null) return;
    return u.doc(folderId).set(
        {...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deleteLookFolder(String uid, String folderId) async {
    final u = _user(uid, 'lookFolders');
    if (u == null) return;
    return u.doc(folderId).delete();
  }

  /// Auto-saved live settings (`users/{uid}/liveSettings/current`).
  Stream<Map<String, dynamic>?> streamLiveSettings(String uid) {
    final u = _user(uid, 'liveSettings');
    if (uid.isEmpty || u == null) return Stream.value(null);
    return u.doc('current').snapshots().map((d) => d.data());
  }

  Future<void> saveLiveSettings(String uid, Map<String, dynamic> patch) async {
    final u = _user(uid, 'liveSettings');
    if (u == null) return;
    return u.doc('current').set(
        {...patch, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> saveLiveProfile(String uid, String id, Map<String, dynamic> data) async {
    final u = _user(uid, 'liveProfiles');
    if (u == null) return;
    return u.doc(id).set(
        {...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deleteLiveProfile(String uid, String id) async {
    final u = _user(uid, 'liveProfiles');
    if (u == null) return;
    return u.doc(id).delete();
  }

  Future<void> saveLiveScene(String uid, String id, Map<String, dynamic> data) async {
    final u = _user(uid, 'liveScenes');
    if (u == null) return;
    return u.doc(id).set(
        {...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deleteLiveScene(String uid, String id) async {
    final u = _user(uid, 'liveScenes');
    if (u == null) return;
    return u.doc(id).delete();
  }

  /// Catalog categories (`lookCategories`), written by functions/admin only.
  Stream<List<Map<String, dynamic>>> streamLookCategories() {
    final fs = firestore;
    if (fs == null) return Stream.value(const []);
    return fs.collection('lookCategories').orderBy('order').snapshots().map(_withIds);
  }

  /// Packs the user owns (`users/{uid}/entitlements`), written by functions only.
  Stream<Set<String>> streamEntitlements(String uid) {
    final u = _user(uid, 'entitlements');
    if (uid.isEmpty || u == null) return Stream.value(const {});
    return u.snapshots().map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// Save or update a look for the current user.
  Future<void> saveUserLook(String uid, OneovaLook look) async {
    final fs = firestore;
    if (uid.isEmpty || fs == null) return;
    final docRef = fs.collection('users').doc(uid).collection('looks').doc(look.id);
    final payload = look.copyWith(updatedAt: DateTime.now()).toMap();
    await docRef.set(payload, SetOptions(merge: true));
  }

  /// Delete a user look.
  Future<void> deleteUserLook(String uid, String lookId) async {
    final fs = firestore;
    if (uid.isEmpty || lookId.isEmpty || fs == null) return;
    await fs.collection('users').doc(uid).collection('looks').doc(lookId).delete();
  }

  /// Duplicate an existing look.
  Future<OneovaLook> duplicateUserLook(String uid, OneovaLook original) async {
    final newId = 'look_${DateTime.now().millisecondsSinceEpoch}';
    final duplicated = original.copyWith(
      id: newId,
      name: '${original.name} (Copy)',
      source: 'user',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await saveUserLook(uid, duplicated);
    return duplicated;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final looksRepositoryProvider = Provider<LooksRepository>((ref) {
  return LooksRepository();
});

/// Current authenticated UID; rebuilds dependants on sign-in/out.
final currentAuthUidProvider = Provider<String>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.value?.uid != null) return auth.value!.uid;
  try {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  } catch (_) {
    return '';
  }
});

/// Per-user Looks setup on sign-in: folds saved Cinema Presets into
/// `users/{uid}/looks` once. Watched by the app root.
final looksUserBootstrapProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
    final uid = next.value?.uid;
    if (uid == null || uid == prev?.value?.uid) return;
    CinemaPresetsMigrationService().migrateUserCinemaPresets(uid).then((n) {
      if (n > 0) debugPrint('[Looks] Imported $n cinema presets as looks.');
    });
  }, fireImmediately: true);
});

/// Selected catalog category filter.
class SelectedLookCategory extends Notifier<String> {
  @override
  String build() => 'All';
  void select(String category) => state = category;
}

final selectedLookCategoryProvider =
    NotifierProvider<SelectedLookCategory, String>(SelectedLookCategory.new);

/// Stream of user-saved looks.
final userLooksStreamProvider = StreamProvider<List<OneovaLook>>((ref) {
  final uid = ref.watch(currentAuthUidProvider);
  return ref.watch(looksRepositoryProvider).streamUserLooks(uid);
});

/// Stream of catalog looks.
final catalogLooksStreamProvider = StreamProvider<List<OneovaLook>>((ref) {
  final category = ref.watch(selectedLookCategoryProvider);
  return ref.watch(looksRepositoryProvider).streamCatalogLooks(category: category);
});

/// Active look selected in the current editing surface.
class ActiveLookNotifier extends Notifier<OneovaLook?> {
  @override
  OneovaLook? build() => null;

  void setLook(OneovaLook? look) => state = look;

  void updateIntensity(double intensity) {
    if (state != null) {
      state = state!.copyWith(intensity: intensity.clamp(0.0, 1.0));
    }
  }

  void updatePrimary(LookPrimary primary) {
    if (state != null) {
      state = state!.copyWith(primary: primary);
    }
  }

  void updateColor(LookColor color) {
    if (state != null) {
      state = state!.copyWith(color: color);
    }
  }

  void updateBeauty(BoostBeautyConfig beauty) {
    if (state != null) {
      state = state!.copyWith(boostBeauty: beauty);
    }
  }

  void updateBackground(BackgroundEffectConfig bg) {
    if (state != null) {
      state = state!.copyWith(background: bg);
    }
  }

  void clear() => state = null;
}

final activeLookProvider =
    NotifierProvider<ActiveLookNotifier, OneovaLook?>(ActiveLookNotifier.new);

/// Active look specifically bound to Live Stream broadcast.
class ActiveLiveLookNotifier extends Notifier<OneovaLook?> {
  @override
  OneovaLook? build() => null;

  void setLiveLook(OneovaLook? look) => state = look;

  void setMasterIntensity(double value) {
    if (state != null) {
      state = state!.copyWith(intensity: value.clamp(0.0, 1.0));
    }
  }
}

final activeLiveLookProvider =
    NotifierProvider<ActiveLiveLookNotifier, OneovaLook?>(ActiveLiveLookNotifier.new);

/// Stream of live scenes for the active broadcaster.
final liveScenesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = ref.watch(currentAuthUidProvider);
  return ref.watch(looksRepositoryProvider).streamLiveScenes(uid);
});

/// Stream of live profiles for the active broadcaster.
final liveProfilesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = ref.watch(currentAuthUidProvider);
  return ref.watch(looksRepositoryProvider).streamLiveProfiles(uid);
});

/// Look folders for the signed-in user.
final lookFoldersStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = ref.watch(currentAuthUidProvider);
  return ref.watch(looksRepositoryProvider).streamLookFolders(uid);
});

/// Auto-saved live settings document (null until first save).
final liveSettingsStreamProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final uid = ref.watch(currentAuthUidProvider);
  return ref.watch(looksRepositoryProvider).streamLiveSettings(uid);
});

/// Catalog categories in display order.
final lookCategoriesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(looksRepositoryProvider).streamLookCategories();
});

/// Pack ids the signed-in user is entitled to.
final lookEntitlementsStreamProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(currentAuthUidProvider);
  return ref.watch(looksRepositoryProvider).streamEntitlements(uid);
});
