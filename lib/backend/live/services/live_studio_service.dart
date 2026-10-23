import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/live_models.dart';
import '../models/live_studio_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final liveStudioServiceProvider =
    Provider<LiveStudioService>((ref) => LiveStudioService());

/// Studio-only fields of the stream doc (featured product, stage focus).
final liveStudioDocProvider =
    StreamProvider.family<LiveStudioDocState, String>((ref, streamId) {
  return ref.watch(liveStudioServiceProvider).watchStudioDoc(streamId);
});

/// Presenter's goods for a stream, in display order.
final liveProductsProvider =
    StreamProvider.family<List<LiveProduct>, String>((ref, streamId) {
  return ref.watch(liveStudioServiceProvider).watchProducts(streamId);
});

/// The product currently featured on the presentation stand.
/// `AsyncData(null)` means nothing is featured.
final liveFeaturedProductProvider =
    Provider.family<AsyncValue<LiveProduct?>, String>((ref, streamId) {
  final doc = ref.watch(liveStudioDocProvider(streamId));
  final products = ref.watch(liveProductsProvider(streamId));
  if (doc.isLoading || products.isLoading) return const AsyncLoading();
  if (doc.hasError) return AsyncError(doc.error!, doc.stackTrace!);
  if (products.hasError) return AsyncError(products.error!, products.stackTrace!);
  final id = doc.value?.featuredProductId;
  if (id == null) return const AsyncData(null);
  for (final p in products.value ?? const <LiveProduct>[]) {
    if (p.id == id) return AsyncData(p);
  }
  return const AsyncData(null);
});

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class LiveStudioService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _col = 'live_streams';

  String get currentUserId => _auth.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> _stream(String id) =>
      _db.collection(_col).doc(id);

  Stream<LiveStudioDocState> watchStudioDoc(String streamId) {
    return _stream(streamId).snapshots().map((s) =>
        LiveStudioDocState.fromJson(s.data() ?? const <String, dynamic>{}));
  }

  Stream<List<LiveProduct>> watchProducts(String streamId) {
    return _stream(streamId)
        .collection('products')
        .orderBy('sortOrder')
        .limit(100)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => LiveProduct.fromJson(d.id, d.data())).toList());
  }

  /// Hearts sent by anyone after [since]; used for the floating-hearts layer.
  Stream<List<LiveReaction>> watchReactionsSince(String streamId, DateTime since) {
    return _stream(streamId)
        .collection('reactions')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((s) => s.docs.map((d) => LiveReaction.fromJson(d.data())).toList());
  }

  /// Host: put a participant on the center stage (null = host returns).
  Future<void> setStageFocus(String streamId, String? userId) {
    return _stream(streamId).update({'stageFocusUserId': userId});
  }

  /// Host: feature a product on the presentation stand (null = clear).
  Future<void> setFeaturedProduct(String streamId, String? productId) {
    return _stream(streamId).update({
      'featuredProductId': productId,
      'featuredAt': FieldValue.serverTimestamp(),
    });
  }

  /// Host: add a product to the presenter's goods.
  Future<void> addProduct(
    String streamId, {
    required String name,
    num? price,
    String currency = 'USD',
    String imageUrl = '',
    String productUrl = '',
  }) async {
    final col = _stream(streamId).collection('products');
    final ref = col.doc();
    await ref.set(LiveProduct(
      id: ref.id,
      name: name.trim(),
      price: price,
      currency: currency.trim().isEmpty ? 'USD' : currency.trim().toUpperCase(),
      imageUrl: imageUrl.trim(),
      productUrl: productUrl.trim(),
      sortOrder: DateTime.now().millisecondsSinceEpoch,
      createdAt: DateTime.now(),
    ).toJson());
  }

  /// Host: remove a product (and un-feature it if needed).
  Future<void> removeProduct(String streamId, String productId,
      {required bool wasFeatured}) async {
    final batch = _db.batch();
    batch.delete(_stream(streamId).collection('products').doc(productId));
    if (wasFeatured) {
      batch.update(_stream(streamId), {'featuredProductId': null});
    }
    await batch.commit();
  }

  /// Registers the current user in the participants list on entry so the
  /// room has a real audience roster and "joined the live" events.
  /// Never overwrites an existing role / stage state (merge without role).
  Future<void> joinAsAudience(String streamId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _stream(streamId).collection('participants').doc(user.uid).set({
      'userId': user.uid,
      'displayName': user.displayName ?? 'Unknown',
      'avatarUrl': user.photoURL ?? '',
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Removes the current user's audience entry when they leave the room.
  Future<void> leaveAsAudience(String streamId) async {
    final uid = currentUserId;
    if (uid.isEmpty) return;
    await _stream(streamId).collection('participants').doc(uid).delete();
  }

  /// Guest self-service: cancel a pending join request or step down from the
  /// stage. Only writes docs a guest is allowed to write (own participant doc
  /// and own guest request); the user stays in the audience.
  Future<void> leaveStage(String streamId) async {
    final uid = currentUserId;
    if (uid.isEmpty) return;
    final batch = _db.batch();
    batch.set(_stream(streamId).collection('participants').doc(uid), {
      'hasRequestedToJoin': false,
      'isCoHost': false,
      'role': LiveGuestRole.viewer.name,
      'isCameraOn': false,
    }, SetOptions(merge: true));
    batch.set(_stream(streamId).collection('guest_requests').doc(uid), {
      'userId': uid, // required by the create rule if no request exists yet
      'streamId': streamId,
      'status': LiveGuestRequestStatus.cancelled.name,
      'respondedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Publishes the current user's mic/camera state so every client can render
  /// the correct badge. Works for the host and for approved stage guests.
  Future<void> publishMediaState(
    String streamId, {
    required bool isMuted,
    required bool isCameraOn,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _stream(streamId).collection('participants').doc(user.uid).set({
      'userId': user.uid,
      'displayName': user.displayName ?? 'Unknown',
      'avatarUrl': user.photoURL ?? '',
      'isMuted': isMuted,
      'isCameraOn': isCameraOn,
    }, SetOptions(merge: true));
  }
}
