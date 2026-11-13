import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../builtin/builtin_effects.dart';
import '../models/ar_effect.dart';

enum ArEffectSort {
  top('Top', 'score'),
  newest('New', 'createdAt'),
  mostUsed('Most used', 'usageCount');

  final String label;
  final String field;
  const ArEffectSort(this.label, this.field);
}

/// What the picker is showing.
class ArEffectQuery {
  final String search;
  final ArEffectCategory? category;
  final ArAudience? audience;
  final ArEffectSort sort;

  const ArEffectQuery({
    this.search = '',
    this.category,
    this.audience,
    this.sort = ArEffectSort.top,
  });

  ArEffectQuery copyWith({
    String? search,
    ArEffectCategory? Function()? category,
    ArAudience? Function()? audience,
    ArEffectSort? sort,
  }) =>
      ArEffectQuery(
        search: search ?? this.search,
        category: category != null ? category() : this.category,
        audience: audience != null ? audience() : this.audience,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is ArEffectQuery &&
      other.search == search &&
      other.category == category &&
      other.audience == audience &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(search, category, audience, sort);
}

/// The Firestore `ar_effects` catalog, per-user favorites and the server
/// callables that create effects. Catalog docs are only written server-side.
class ArEffectRepository {
  ArEffectRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  static const pageSize = 60;

  CollectionReference<Map<String, dynamic>> get _effects => _db.collection('ar_effects');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Search tokens match what the server writes into `keywords`.
  static String _token(String search) {
    final words = search
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 2)
        .toList();
    if (words.isEmpty) return '';
    // The longest word is the most selective.
    words.sort((a, b) => b.length.compareTo(a.length));
    final w = words.first;
    return w.length > 20 ? w.substring(0, 20) : w;
  }

  /// Live list of public effects for [q], ranked by [ArEffectSort].
  Stream<List<ArEffect>> watchCatalog(ArEffectQuery q) {
    Query<Map<String, dynamic>> query = _effects.where('listed', isEqualTo: true);
    final token = _token(q.search);
    if (token.isNotEmpty) {
      // Firestore allows one array-contains; category/audience are applied
      // on the matched page below.
      query = query.where('keywords', arrayContains: token);
    } else {
      if (q.category != null) query = query.where('category', isEqualTo: q.category!.name);
      if (q.audience != null && q.audience != ArAudience.unisex) {
        query = query.where('audience', whereIn: [q.audience!.name, ArAudience.unisex.name]);
      }
    }
    query = query.orderBy(q.sort.field, descending: true).limit(pageSize);
    return query.snapshots().map((s) {
      var list = s.docs.map(ArEffect.fromDoc).toList();
      if (token.isNotEmpty) {
        if (q.category != null) list = list.where((e) => e.category == q.category).toList();
        if (q.audience != null && q.audience != ArAudience.unisex) {
          list = list
              .where((e) => e.audience == q.audience || e.audience == ArAudience.unisex)
              .toList();
        }
      }
      return list;
    });
  }

  /// Effects the signed-in user created (public and private).
  Stream<List<ArEffect>> watchMine() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _effects
        .where('creatorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((s) => s.docs.map(ArEffect.fromDoc).toList());
  }

  CollectionReference<Map<String, dynamic>> _favorites(String uid) =>
      _db.collection('users').doc(uid).collection('ar_favorites');

  /// Ids of the user's favorites, newest first.
  Stream<List<String>> watchFavoriteIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _favorites(uid)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  /// Loads effects by id, keeping [ids] order and skipping ones that are gone.
  Future<List<ArEffect>> fetchByIds(List<String> ids) async {
    // Single gets, so one effect its creator made private can't fail the rest.
    final docs = await Future.wait(ids.map((id) async {
      final builtIn = BuiltInEffects.byId(id);
      if (builtIn != null) return builtIn.effect;
      try {
        final d = await _effects.doc(id).get();
        return d.exists ? ArEffect.fromDoc(d) : null;
      } on FirebaseException {
        return null;
      }
    }));
    return docs.whereType<ArEffect>().toList();
  }

  /// One favorite per user per effect: the doc id *is* the effect id, and
  /// the server keeps `favoriteCount` in step with these docs.
  Future<void> setFavorite(String effectId, bool favorite) async {
    final uid = _uid;
    if (uid == null) throw StateError('Sign in to save favorites.');
    final ref = _favorites(uid).doc(effectId);
    if (favorite) {
      await ref.set({'effectId': effectId, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  /// Counts a use for ranking (the server counts each user once a day).
  Future<void> recordUse(String effectId) async {
    try {
      await _functions.httpsCallable('arEffectUse').call<void>({'effectId': effectId});
    } catch (_) {
      // Ranking is best-effort; never block the camera on it.
    }
  }

  /// Type-to-create: the server picks the anchor, generates the asset on
  /// Vertex AI, stores it and returns the new effect's id.
  Future<String> generate({
    required String prompt,
    ArAudience? audience,
    ArEffectCategory? category,
    bool publish = true,
  }) async {
    final res = await _functions
        .httpsCallable(
          'arEffectGenerate',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 180)),
        )
        .call<Map<String, dynamic>>({
      'prompt': prompt,
      if (audience != null) 'audience': audience.name,
      if (category != null) 'category': category.name,
      'publish': publish,
    });
    return res.data['effectId'] as String;
  }

  /// Creates an effect from the user's own transparent PNG.
  Future<String> createFromUpload({
    required File file,
    required String name,
    required ArEffectCategory category,
    required ArAnchor anchor,
    required ArAudience audience,
    bool publish = true,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Sign in to upload effects.');
    final path = 'ar_effect_uploads/$uid/${DateTime.now().millisecondsSinceEpoch}.png';
    await FirebaseStorage.instance
        .ref(path)
        .putFile(file, SettableMetadata(contentType: 'image/png'));
    final res = await _functions.httpsCallable('arEffectCreateFromUpload').call<Map<String, dynamic>>({
      'storagePath': path,
      'name': name,
      'category': category.name,
      'anchor': anchor.name,
      'audience': audience.name,
      'publish': publish,
    });
    return res.data['effectId'] as String;
  }

  Future<ArEffect?> fetch(String id) async {
    final d = await _effects.doc(id).get();
    return d.exists ? ArEffect.fromDoc(d) : null;
  }
}

final arEffectRepositoryProvider = Provider<ArEffectRepository>((ref) => ArEffectRepository());

final arEffectCatalogProvider =
    StreamProvider.autoDispose.family<List<ArEffect>, ArEffectQuery>((ref, q) {
  return ref.watch(arEffectRepositoryProvider).watchCatalog(q);
});

final arMyEffectsProvider = StreamProvider.autoDispose<List<ArEffect>>((ref) {
  return ref.watch(arEffectRepositoryProvider).watchMine();
});

final arFavoriteIdsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  return ref.watch(arEffectRepositoryProvider).watchFavoriteIds();
});

final arFavoriteEffectsProvider = FutureProvider.autoDispose<List<ArEffect>>((ref) async {
  final ids = await ref.watch(arFavoriteIdsProvider.future);
  return ref.watch(arEffectRepositoryProvider).fetchByIds(ids);
});
