import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/live/services/live_service.dart';
import '../models/shop_models.dart';

/// Reads and writes for Oneova 3D Shops. Everything here is the seller's own
/// presentation data; prices, stock and payment are re-checked by the server
/// at checkout (functions/src/commerce/orderEscrow.ts).
class Shop3DRepository {
  Shop3DRepository({FirebaseFirestore? db, FirebaseStorage? storage, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  static const feedPageSize = 8;
  static const maxProductsPerShop = 100;

  String? get uid => _auth.currentUser?.uid;

  String _requireUid() {
    final u = uid;
    if (u == null) throw StateError('Sign in to manage your shop.');
    return u;
  }

  CollectionReference<Map<String, dynamic>> get _shops => _db.collection('biz_shops');
  CollectionReference<Map<String, dynamic>> get _products => _db.collection('products');

  // ── Shops ──────────────────────────────────────────────────────────────

  Stream<Shop3D?> watchShop(String shopId) =>
      _shops.doc(shopId).snapshots().map((d) => d.exists ? Shop3D.fromDoc(d) : null);

  /// One page of open shops, newest activity first. Pass the last doc of the
  /// previous page as [after] to continue.
  Future<(List<Shop3D>, DocumentSnapshot<Map<String, dynamic>>?)> shopsPage({
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    Query<Map<String, dynamic>> q =
        _shops.where('status', isEqualTo: 'open').orderBy('updatedAt', descending: true).limit(feedPageSize);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    final shops = snap.docs.map(Shop3D.fromDoc).where((s) => s.name.isNotEmpty).toList();
    // A short page is the last one; no extra empty fetch.
    return (shops, snap.docs.length < feedPageSize ? null : snap.docs.last);
  }

  /// Fetches specific open shops (used to put live sellers first in the feed).
  Future<List<Shop3D>> shopsByIds(Iterable<String> ids) async {
    final list = ids.toSet().take(10).toList();
    if (list.isEmpty) return const [];
    // Most live hosts have no shop, and rules refuse reading a missing or
    // closed shop, so each read fails on its own instead of sinking the rest.
    final docs = await Future.wait(list.map((id) async {
      try {
        return await _shops.doc(id).get();
      } catch (_) {
        return null;
      }
    }));
    return [
      for (final d in docs)
        if (d != null && d.exists) Shop3D.fromDoc(d),
    ].where((s) => s.status == ShopStatus.open && s.name.isNotEmpty).toList();
  }

  /// Creates or updates the signed-in seller's storefront.
  Future<void> saveMyShop({
    required String name,
    required String tagline,
    required String bio,
    required List<String> categories,
    required StageConfig stage,
    String? avatarUrl,
    String? bannerUrl,
    double? lat,
    double? lng,
    String? featuredProductId,
    ShopStatus? status,
  }) async {
    final me = _requireUid();
    final ref = _shops.doc(me);
    final existing = await ref.get();
    final current = existing.exists ? ShopStatus.parse(existing.data()?['status']) : ShopStatus.draft;
    await ref.set({
      'ownerId': me,
      'name': name.trim(),
      'tagline': tagline.trim(),
      'bio': bio.trim(),
      'categories': categories,
      'stage': stage.toMap(),
      'status': (status ?? current).name,
      'avatarUrl': ?avatarUrl,
      'bannerUrl': ?bannerUrl,
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
      'featuredProductId': featuredProductId, // null clears the star
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setMyShopStatus(ShopStatus status) async {
    final me = _requireUid();
    final ref = _shops.doc(me);
    final d = (await ref.get()).data();
    if (d == null) throw StateError('Set up your shop first.');
    // Full doc is re-sent so the rules can validate the whole shape.
    await ref.set({
      ...d,
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      if (status == ShopStatus.open) 'openedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Products ───────────────────────────────────────────────────────────

  /// A seller's catalog, in the seller's chosen order. No composite index:
  /// older products without `sortOrder` still show (sorted last).
  Stream<List<ShopProduct>> watchProductsOf(String ownerId, {bool activeOnly = true}) {
    return _products.where('ownerId', isEqualTo: ownerId).limit(maxProductsPerShop).snapshots().map((s) {
      final list = s.docs.map(ShopProduct.fromDoc).where((p) => p.name.isNotEmpty);
      final filtered = activeOnly ? list.where((p) => p.active && p.price > 0) : list;
      return filtered.toList()
        ..sort((a, b) {
          final o = a.sortOrder.compareTo(b.sortOrder);
          return o != 0 ? o : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    });
  }

  Stream<ShopProduct?> watchProduct(String productId) =>
      _products.doc(productId).snapshots().map((d) => d.exists ? ShopProduct.fromDoc(d) : null);

  /// Reserves an id so files can be uploaded under the product before saving.
  String newProductId() => _products.doc().id;

  Future<void> saveProduct({
    required String productId,
    required bool isNew,
    required String name,
    required String description,
    required num price,
    required num? compareAtPrice,
    required String currency,
    required int? stock,
    required String category,
    required List<String> imageUrls,
    required String? model3dUrl,
    required List<ProductVariant> variants,
    required bool active,
    int? sortOrder,
    List<ProductOption>? customization,
    List<ProductTexture>? textures,
    String? model3dHdUrl,
    String? model3dArUrl,
    List<String> modelAnimations = const [],
  }) async {
    final me = _requireUid();
    final trackedStock = stock ?? _sumVariantStock(variants);
    await _products.doc(productId).set({
      'ownerId': me,
      'shopId': me,
      'name': name.trim(),
      'title': name.trim(), // older readers use `title`
      'description': description.trim(),
      'price': price,
      'compareAtPrice': compareAtPrice,
      'currency': currency.toLowerCase(),
      // Untracked stock removes the old count so it can't block checkout.
      'stock': trackedStock ?? (isNew ? null : FieldValue.delete()),
      'inStock': trackedStock == null || trackedStock > 0,
      'category': category.trim(),
      'imageUrl': imageUrls.isEmpty ? '' : imageUrls.first,
      'imageUrls': imageUrls,
      'model3dUrl': model3dUrl,
      // Belong to the model above; cleared when the seller removes or replaces it.
      'model3dHdUrl': model3dUrl == null ? null : model3dHdUrl,
      'model3dArUrl': model3dUrl == null ? null : model3dArUrl,
      'modelAnimations': model3dUrl == null ? const <String>[] : modelAnimations,
      'variants': [for (final v in variants) v.toMap()],
      if (customization != null) 'customization': [for (final o in customization) o.toMap()],
      if (textures != null) 'textures': [for (final t in textures) t.toMap()],
      'active': active,
      'sortOrder': ?sortOrder,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static int? _sumVariantStock(List<ProductVariant> variants) {
    if (variants.isEmpty || variants.any((v) => v.stock == null)) return null;
    return variants.fold<int>(0, (a, v) => a + v.stock!);
  }

  Future<void> deleteProduct(String productId) => _products.doc(productId).delete();

  /// Persists a new order for the seller's catalog.
  Future<void> reorderProducts(List<String> orderedIds) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_products.doc(orderedIds[i]), {'sortOrder': i, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  // ── Uploads ────────────────────────────────────────────────────────────

  Future<String> uploadBrandImage(File file, String kind) async {
    final me = _requireUid();
    final ext = _ext(file.path, fallback: 'jpg');
    final ref = _storage.ref('shops/$me/brand/${kind}_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putFile(file, SettableMetadata(contentType: _imageType(ext), cacheControl: 'public,max-age=604800'));
    return ref.getDownloadURL();
  }

  /// Uploads a product image or 3D model. [onProgress] reports 0..1.
  Future<String> uploadProductFile(String productId, File file, {void Function(double)? onProgress}) async {
    final me = _requireUid();
    final ext = _ext(file.path, fallback: 'bin');
    final contentType = switch (ext) {
      'glb' => 'model/gltf-binary',
      'gltf' => 'model/gltf+json',
      'usdz' => 'model/vnd.usdz+zip',
      _ => _imageType(ext),
    };
    final ref = _storage.ref('shops/$me/products/$productId/${DateTime.now().millisecondsSinceEpoch}.$ext');
    final task = ref.putFile(file, SettableMetadata(contentType: contentType, cacheControl: 'public,max-age=2592000'));
    if (onProgress != null) {
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
      });
    }
    await task;
    return ref.getDownloadURL();
  }

  static String _ext(String path, {required String fallback}) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return fallback;
    return path.substring(dot + 1).toLowerCase();
  }

  static String _imageType(String ext) => switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        _ => 'image/jpeg',
      };

  // ── Saved products ─────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _saved(String me, String productId) =>
      _db.collection('users').doc(me).collection('saved_products').doc(productId);

  Stream<bool> watchSaved(String productId) {
    final me = uid;
    if (me == null) return Stream.value(false);
    return _saved(me, productId).snapshots().map((d) => d.exists);
  }

  Future<bool> toggleSaved(ShopProduct p) async {
    final me = _requireUid();
    final ref = _saved(me, p.id);
    if ((await ref.get()).exists) {
      await ref.delete();
      return false;
    }
    await ref.set({'productId': p.id, 'shopId': p.ownerId, 'savedAt': FieldValue.serverTimestamp()});
    return true;
  }

  // ── Business portal (seller) ──

  /// Orders where the signed-in user is the seller, newest first.
  Stream<List<Map<String, dynamic>>> watchSellerOrders({int limit = 100}) {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _db
        .collection('orders')
        .where('participants', arrayContains: me)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (d.data()['sellerId'] == me) {...d.data(), 'id': d.id},
            ]);
  }

  Future<void> setFulfilment(String orderId, String step, {String note = ''}) async {
    await FirebaseFunctions.instance.httpsCallable('bizSetFulfilment').call({'orderId': orderId, 'step': step, 'note': note});
  }

  Future<void> saveStoreSettings(StoreSettings s) async {
    final me = _requireUid();
    await _shops.doc(me).update({...s.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Quick stock edit from the inventory screen.
  Future<void> setStock(ShopProduct p, {int? stock, Map<String, int?>? variantStock}) async {
    _requireUid();
    final variants = [
      for (final v in p.variants)
        variantStock != null && variantStock.containsKey(v.id)
            ? ProductVariant(id: v.id, name: v.name, colorHex: v.colorHex, stock: variantStock[v.id], modelVariant: v.modelVariant)
            : v,
    ];
    final total = p.variants.isEmpty ? stock : _sumVariantStock(variants);
    await _products.doc(p.id).update({
      if (p.variants.isNotEmpty) 'variants': [for (final v in variants) v.toMap()],
      'stock': total ?? FieldValue.delete(),
      'inStock': total == null || total > 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  CollectionReference<Map<String, dynamic>> _codes(String me) => _shops.doc(me).collection('codes');

  Stream<List<DiscountCode>> watchMyCodes() {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _codes(me).snapshots().map((s) => s.docs.map(DiscountCode.fromDoc).toList()..sort((a, b) => a.code.compareTo(b.code)));
  }

  Future<void> saveCode({required String code, int? percentOff, num? amountOff, String? currency, num? minSpend, int? maxUses, DateTime? endsAt, bool active = true}) async {
    final me = _requireUid();
    final id = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (id.isEmpty) throw StateError('Enter a code with letters or numbers.');
    final ref = _codes(me).doc(id);
    final existing = await ref.get();
    await ref.set({
      'code': id,
      'active': active,
      'percentOff': percentOff,
      'amountOff': amountOff,
      'currency': currency?.toUpperCase(),
      'minSpend': minSpend,
      'maxUses': maxUses,
      'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt),
      'uses': existing.data()?['uses'] ?? 0,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCode(String code) => _codes(_requireUid()).doc(code).delete();

  /// Last [days] of store counters (views, carts, saves).
  Stream<List<Map<String, dynamic>>> watchDailyStats({int days = 30}) {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _shops.doc(me).collection('daily').orderBy('day', descending: true).limit(days).snapshots().map((s) => [for (final d in s.docs) d.data()]);
  }

  // ── Buyer signals and reviews ──

  /// Counts a view / cart / save once per person per item per day. Never throws.
  Future<void> trackEvent(String shopId, String kind, {String? productId}) async {
    if (uid == null) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('bizTrackEvent')
          .call({'shopId': shopId, 'kind': kind, 'productId': ?productId});
    } catch (_) {}
  }

  Future<void> submitReview(String orderId, int rating, String text) async {
    await FirebaseFunctions.instance.httpsCallable('bizSubmitReview').call({'orderId': orderId, 'rating': rating, 'text': text});
  }

  Stream<List<Map<String, dynamic>>> watchReviews(String productId, {int limit = 20}) => _db
      .collection('product_reviews')
      .where('productId', isEqualTo: productId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) d.data()]);

  // ── Textures ──

  List<ShopTexture>? _library;

  /// The hosted built-in library (rendered on the server on first use).
  Future<List<ShopTexture>> textureLibrary() async {
    if (_library != null) return _library!;
    final r = await FirebaseFunctions.instance
        .httpsCallable('textureLibrary', options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
        .call();
    final list = ((r.data as Map)['textures'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ShopTexture.fromMap('${m['id']}', m))
        .where((t) => t.url.startsWith('https://'))
        .toList();
    return _library = list;
  }

  CollectionReference<Map<String, dynamic>> _textures(String me) => _shops.doc(me).collection('textures');

  Stream<List<ShopTexture>> watchMyTextures() {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _textures(me)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => [for (final d in s.docs) ShopTexture.fromMap(d.id, d.data())]);
  }

  /// Renders a new colorway of [kind] on the server.
  Future<ShopTexture> createTexture({required String kind, required List<String> colors, String? name}) async {
    final r = await FirebaseFunctions.instance
        .httpsCallable('textureCreate')
        .call({'kind': kind, 'colors': colors, 'name': ?name});
    final m = r.data as Map;
    return ShopTexture.fromMap('${m['id']}', m);
  }

  /// A seller's own photo as a texture (fabric swatch, wood sample…).
  Future<ShopTexture> uploadTexturePhoto(File file, String name) async {
    final me = _requireUid();
    final id = _textures(me).doc().id;
    final ref = FirebaseStorage.instance.ref('shops/$me/textures/$id.${_ext(file.path, fallback: 'jpg')}');
    await ref.putFile(file, SettableMetadata(contentType: 'image/${_ext(file.path, fallback: 'jpg') == 'png' ? 'png' : 'jpeg'}'));
    final url = await ref.getDownloadURL();
    final data = {
      'name': name.trim().isEmpty ? 'My texture' : name.trim(),
      'kind': 'photo',
      'category': 'Mine',
      'url': url,
      'roughness': 0.6,
      'metallic': 0.0,
      'scale': 1.0,
      'builtIn': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _textures(me).doc(id).set(data);
    return ShopTexture.fromMap(id, data);
  }

  Future<void> deleteMyTexture(String id) => _textures(_requireUid()).doc(id).delete();

  /// Live: show [texture] on [productId] for everyone watching the stage.
  Future<void> setStageTexture(String productId, ProductTexture? texture) async {
    final me = _requireUid();
    await _shops.doc(me).update({
      'stageTexture': texture == null ? null : {'productId': productId, ...texture.toMap()},
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Live deal (seller) ──

  Future<void> startLiveDeal({required int percentOff, required Duration length, String title = 'Live deal', List<String> productIds = const []}) async {
    final me = _requireUid();
    final deal = LiveDeal(
      title: title,
      percentOff: percentOff.clamp(1, 80),
      endsAt: DateTime.now().add(length),
      productIds: productIds,
    );
    await _db.collection('biz_shops').doc(me).update({'liveDeal': deal.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> endLiveDeal() async {
    final me = _requireUid();
    await _db.collection('biz_shops').doc(me).update({'liveDeal': null, 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ── Cart (private, `users/{uid}/cart`) ──

  CollectionReference<Map<String, dynamic>> _cart(String me) => _db.collection('users').doc(me).collection('cart');

  Future<void> addToCart(ShopProduct p, ProductVariant? v, {int quantity = 1, Map<String, String> customization = const {}}) async {
    final me = _requireUid();
    final base = v == null ? p.id : '${p.id}__${v.id}';
    // Different customizations are different lines.
    final id = customization.isEmpty ? base : '${base}__${customization.entries.map((e) => '${e.key}=${e.value}').join('&').hashCode.toUnsigned(32).toRadixString(36)}';
    await _cart(me).doc(id).set({
      'productId': p.id,
      'variantId': v?.id,
      'shopId': p.ownerId,
      if (customization.isNotEmpty) 'customization': customization,
      'quantity': FieldValue.increment(quantity),
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFromCart(String lineId) async => _cart(_requireUid()).doc(lineId).delete();

  Stream<List<CartLine>> watchCart() {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _cart(me).orderBy('addedAt', descending: true).limit(50).snapshots().map((s) => [
          for (final d in s.docs)
            CartLine(
              id: d.id,
              productId: (d.data()['productId'] as String?) ?? '',
              variantId: d.data()['variantId'] as String?,
              quantity: (d.data()['quantity'] as num?)?.toInt() ?? 1,
              customization: {
                for (final e in ((d.data()['customization'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
              },
            ),
        ]);
  }

  Stream<List<String>> watchSavedIds() {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(me)
        .collection('saved_products')
        .orderBy('savedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

final shop3dRepositoryProvider = Provider<Shop3DRepository>((ref) => Shop3DRepository());

final shopProvider = StreamProvider.autoDispose.family<Shop3D?, String>(
  (ref, shopId) => ref.watch(shop3dRepositoryProvider).watchShop(shopId),
);

final myShopProvider = StreamProvider.autoDispose<Shop3D?>((ref) {
  final repo = ref.watch(shop3dRepositoryProvider);
  final me = repo.uid;
  return me == null ? Stream.value(null) : repo.watchShop(me);
});

final shopProductsProvider = StreamProvider.autoDispose.family<List<ShopProduct>, String>(
  (ref, ownerId) => ref.watch(shop3dRepositoryProvider).watchProductsOf(ownerId),
);

/// The signed-in seller's whole catalog, drafts included.
final myCatalogProvider = StreamProvider.autoDispose<List<ShopProduct>>((ref) {
  final repo = ref.watch(shop3dRepositoryProvider);
  final me = repo.uid;
  return me == null ? Stream.value(const []) : repo.watchProductsOf(me, activeOnly: false);
});

final shopProductProvider = StreamProvider.autoDispose.family<ShopProduct?, String>(
  (ref, id) => ref.watch(shop3dRepositoryProvider).watchProduct(id),
);

final productSavedProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(shop3dRepositoryProvider).watchSaved(id),
);

/// One line in the private cart.
class CartLine {
  const CartLine({required this.id, required this.productId, this.variantId, this.quantity = 1, this.customization = const {}});
  final Map<String, String> customization;
  final String id;
  final String productId;
  final String? variantId;
  final int quantity;
}

final cartProvider = StreamProvider.autoDispose<List<CartLine>>(
  (ref) => ref.watch(shop3dRepositoryProvider).watchCart(),
);

final savedProductIdsProvider = StreamProvider.autoDispose<List<String>>(
  (ref) => ref.watch(shop3dRepositoryProvider).watchSavedIds(),
);

/// Sellers who are live right now, keyed by host uid (reuses the Live feed).
final liveShopsProvider = Provider.autoDispose<Map<String, ShopLive>>((ref) {
  final streams = ref.watch(activeLiveStreamsProvider).value ?? const [];
  return {
    for (final s in streams)
      if (s.hostId.isNotEmpty)
        s.hostId: ShopLive(streamId: s.id, title: s.title, viewerCount: s.viewerCount),
  };
});
