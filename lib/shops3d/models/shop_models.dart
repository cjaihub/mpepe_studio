import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../backend/pay/oneova_pay_service.dart' show currencyExponent;

/// Oneova 3D Shops data model.
///
/// * `biz_shops/{uid}`  — one storefront per seller (doc id = seller uid).
///   Trust fields (`verified`, `followersCount`, `rating`) are server-written.
/// * `products/{id}`    — the shared Biz catalog (also used by checkout and
///   Live). 3D Shops adds `model3dUrl`, `variants`, `compareAtPrice`,
///   `imageUrls`, `sortOrder`, `active`.
/// * `users/{uid}/saved_products/{productId}` — private wishlist.

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

/// How the seller dressed their stage. Values are tokens, not colours, so the
/// stage always renders with the app's own palette.
enum StageBackdrop {
  /// Follows the viewer's light/dark theme.
  studio,

  /// Always dark (night showroom).
  midnight,

  /// Always light (daylight gallery).
  daylight;

  static StageBackdrop parse(Object? v) =>
      StageBackdrop.values.firstWhere((e) => e.name == v, orElse: () => StageBackdrop.studio);

  String get label => switch (this) {
        StageBackdrop.studio => 'Studio',
        StageBackdrop.midnight => 'Midnight',
        StageBackdrop.daylight => 'Daylight',
      };

  bool isDark(BuildContext context) => switch (this) {
        StageBackdrop.studio => Theme.of(context).brightness == Brightness.dark,
        StageBackdrop.midnight => true,
        StageBackdrop.daylight => false,
      };
}

/// Accent used for the stage glow and highlights (brand palette only).
enum StageAccent {
  blue,
  pink;

  static StageAccent parse(Object? v) =>
      StageAccent.values.firstWhere((e) => e.name == v, orElse: () => StageAccent.blue);
}

/// Where the product card sits on the stage.
enum CardPlacement {
  right,
  left;

  static CardPlacement parse(Object? v) =>
      CardPlacement.values.firstWhere((e) => e.name == v, orElse: () => CardPlacement.right);
}

@immutable
class StageConfig {
  final StageBackdrop backdrop;
  final StageAccent accent;
  final CardPlacement card;
  final bool autoRotate;

  const StageConfig({
    this.backdrop = StageBackdrop.studio,
    this.accent = StageAccent.blue,
    this.card = CardPlacement.right,
    this.autoRotate = true,
  });

  factory StageConfig.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    return StageConfig(
      backdrop: StageBackdrop.parse(m['backdrop']),
      accent: StageAccent.parse(m['accent']),
      card: CardPlacement.parse(m['card']),
      autoRotate: m['autoRotate'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'backdrop': backdrop.name,
        'accent': accent.name,
        'card': card.name,
        'autoRotate': autoRotate,
      };

  StageConfig copyWith({StageBackdrop? backdrop, StageAccent? accent, CardPlacement? card, bool? autoRotate}) =>
      StageConfig(
        backdrop: backdrop ?? this.backdrop,
        accent: accent ?? this.accent,
        card: card ?? this.card,
        autoRotate: autoRotate ?? this.autoRotate,
      );
}

enum ShopStatus {
  draft,
  open,
  closed;

  static ShopStatus parse(Object? v) =>
      ShopStatus.values.firstWhere((e) => e.name == v, orElse: () => ShopStatus.draft);
}

@immutable
class Shop3D {
  final String id; // = owner uid
  final String ownerId;
  final String name;
  final String tagline;
  final String bio;
  final String avatarUrl;
  final String bannerUrl;
  final List<String> categories;
  final StageConfig stage;
  final ShopStatus status;
  final String? featuredProductId;
  final double? lat;
  final double? lng;
  final bool verified;
  final int followersCount;
  final double? rating;
  final DateTime? updatedAt;

  const Shop3D({
    required this.id,
    required this.ownerId,
    required this.name,
    this.tagline = '',
    this.bio = '',
    this.avatarUrl = '',
    this.bannerUrl = '',
    this.categories = const [],
    this.stage = const StageConfig(),
    this.status = ShopStatus.draft,
    this.featuredProductId,
    this.lat,
    this.lng,
    this.verified = false,
    this.followersCount = 0,
    this.rating,
    this.updatedAt,
    this.liveDeal,
    this.settings = const StoreSettings(),
    this.reviewCount = 0,
    this.stageTexture,
    this.verifiedLevel = 1,
  });

  final StoreSettings settings;
  final int reviewCount;

  /// Business verification level, mirrored by the identity service (server-only).
  final int verifiedLevel;

  /// Texture the seller is showing on air for one product.
  final ({String productId, ProductTexture texture})? stageTexture;

  /// Time-limited discount the seller runs on stage (priced on the server).
  final LiveDeal? liveDeal;

  bool get hasPickup => lat != null && lng != null;

  factory Shop3D.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final loc = d['location'];
    return Shop3D(
      id: doc.id,
      ownerId: (d['ownerId'] as String?) ?? doc.id,
      name: (d['name'] as String?) ?? '',
      tagline: (d['tagline'] as String?) ?? '',
      bio: (d['bio'] as String?) ?? '',
      avatarUrl: (d['avatarUrl'] as String?) ?? '',
      bannerUrl: (d['bannerUrl'] as String?) ?? '',
      categories: List<String>.from((d['categories'] as List?)?.whereType<String>() ?? const []),
      stage: StageConfig.fromMap(d['stage']),
      status: ShopStatus.parse(d['status']),
      featuredProductId: d['featuredProductId'] as String?,
      lat: loc is Map ? (loc['lat'] as num?)?.toDouble() : null,
      lng: loc is Map ? (loc['lng'] as num?)?.toDouble() : null,
      verified: d['verified'] == true,
      followersCount: (d['followersCount'] as num?)?.toInt() ?? 0,
      rating: (d['rating'] as num?)?.toDouble(),
      updatedAt: _date(d['updatedAt']),
      liveDeal: LiveDeal.parse(d['liveDeal']),
      settings: StoreSettings.parse(d),
      reviewCount: (d['reviewCount'] as num?)?.toInt() ?? 0,
      verifiedLevel: (d['verifiedLevel'] as num?)?.toInt() ?? 1,
      stageTexture: d['stageTexture'] is Map && (d['stageTexture']['productId'] ?? '') != ''
          ? (productId: '${d['stageTexture']['productId']}', texture: ProductTexture.fromMap(d['stageTexture'] as Map))
          : null,
    );
  }
}

/// `biz_shops/{uid}.liveDeal`: percent off for a limited time, optionally
/// only on some products. The checkout applies it from the same fields.
@immutable
class LiveDeal {
  const LiveDeal({required this.title, required this.percentOff, required this.endsAt, this.productIds = const []});

  final String title;
  final int percentOff;
  final DateTime endsAt;

  /// Empty = the whole shop.
  final List<String> productIds;

  bool get active => percentOff > 0 && endsAt.isAfter(DateTime.now());
  bool appliesTo(String productId) => active && (productIds.isEmpty || productIds.contains(productId));
  /// Same rounding as the server checkout: whole units for zero-decimal
  /// currencies (UGX, RWF, XAF, XOF…), cents otherwise.
  num priceFor(num price, String currency) {
    final scale = math.pow(10, currencyExponent(currency));
    return (price * (100 - percentOff) / 100 * scale).round() / scale;
  }

  static LiveDeal? parse(Object? raw) {
    if (raw is! Map) return null;
    final pct = (raw['percentOff'] as num?)?.toInt() ?? 0;
    final ends = _date(raw['endsAt']);
    if (pct <= 0 || ends == null) return null;
    return LiveDeal(
      title: (raw['title'] as String?)?.trim().isNotEmpty == true ? raw['title'] as String : 'Live deal',
      percentOff: pct.clamp(1, 80),
      endsAt: ends,
      productIds: List<String>.from((raw['productIds'] as List?)?.whereType<String>() ?? const []),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'percentOff': percentOff,
        'endsAt': Timestamp.fromDate(endsAt),
        'productIds': productIds,
      };
}

@immutable
class ProductVariant {
  final String id;
  final String name;

  /// `#RRGGBB` swatch colour, if the option is a colour.
  final String? colorHex;

  /// Stock for this option; null = not tracked per option.
  final int? stock;

  /// Name of the matching material variant inside the GLB (KHR_materials_variants).
  final String? modelVariant;

  const ProductVariant({required this.id, required this.name, this.colorHex, this.stock, this.modelVariant});

  bool get soldOut => stock != null && stock! <= 0;

  Color? get swatch {
    final h = colorHex?.replaceFirst('#', '');
    if (h == null || h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  factory ProductVariant.fromMap(Map m) => ProductVariant(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? m['id'] ?? '').toString(),
        colorHex: m['colorHex'] as String?,
        stock: (m['stock'] as num?)?.toInt(),
        modelVariant: m['modelVariant'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (colorHex != null) 'colorHex': colorHex,
        if (stock != null) 'stock': stock,
        if (modelVariant != null && modelVariant!.isNotEmpty) 'modelVariant': modelVariant,
      };
}

@immutable
class ShopProduct {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  final num price;
  final num? compareAtPrice;
  final String currency;
  final int? stock;
  final bool inStock;
  final String imageUrl;
  final List<String> imageUrls;
  final String? model3dUrl;
  final String? model3dIosUrl;

  /// Sharper file for tablets and close zoom (set by the model service).
  final String? model3dHdUrl;

  /// PNG/JPEG + Draco file the system AR viewer can open.
  final String? model3dArUrl;

  /// Names of the animations inside the model.
  final List<String> modelAnimations;
  final List<ProductVariant> variants;
  final String category;
  final bool active;
  final int sortOrder;

  /// Buyer customization the seller offers (priced on the server).
  final List<ProductOption> customization;
  final double? rating;
  final int reviewCount;

  /// Default material textures shown on the 3D model.
  final List<ProductTexture> textures;

  const ShopProduct({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description = '',
    this.price = 0,
    this.compareAtPrice,
    this.currency = 'usd',
    this.stock,
    this.inStock = true,
    this.imageUrl = '',
    this.imageUrls = const [],
    this.model3dUrl,
    this.model3dIosUrl,
    this.model3dHdUrl,
    this.model3dArUrl,
    this.modelAnimations = const [],
    this.variants = const [],
    this.category = '',
    this.active = true,
    this.sortOrder = 0,
    this.customization = const [],
    this.rating,
    this.reviewCount = 0,
    this.textures = const [],
  });

  bool get has3d => (model3dUrl ?? '').startsWith('https://');

  /// The file to show: the sharper one on tablets when the product has it.
  String? viewUrl({required bool large}) =>
      large && (model3dHdUrl ?? '').startsWith('https://') ? model3dHdUrl : model3dUrl;

  bool get soldOut => !inStock || (stock != null && stock! <= 0);

  /// Whole-number discount vs. the compare-at price, or null.
  int? get discountPercent {
    final c = compareAtPrice;
    if (c == null || c <= price || c <= 0) return null;
    final pct = ((c - price) / c * 100).round();
    return pct > 0 ? pct : null;
  }

  /// All images, cover first, http(s) only.
  List<String> get gallery {
    final all = <String>[if (imageUrl.isNotEmpty) imageUrl, ...imageUrls];
    final seen = <String>{};
    return [for (final u in all) if (u.startsWith('http') && seen.add(u)) u];
  }

  bool get sellable => active && price > 0 && !soldOut;

  factory ShopProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawVariants = d['variants'] as List? ?? const [];
    return ShopProduct(
      id: doc.id,
      ownerId: (d['ownerId'] ?? d['userId'] ?? d['uid'] ?? '').toString(),
      name: (d['name'] ?? d['title'] ?? '').toString(),
      description: (d['description'] as String?) ?? '',
      price: (d['price'] as num?) ?? 0,
      compareAtPrice: d['compareAtPrice'] as num?,
      currency: ((d['currency'] as String?) ?? 'usd').toLowerCase(),
      stock: (d['stock'] as num?)?.toInt(),
      inStock: d['inStock'] != false,
      imageUrl: (d['imageUrl'] as String?) ?? '',
      imageUrls: List<String>.from((d['imageUrls'] as List?)?.whereType<String>() ?? const []),
      model3dUrl: d['model3dUrl'] as String?,
      model3dIosUrl: d['model3dIosUrl'] as String?,
      model3dHdUrl: d['model3dHdUrl'] as String?,
      model3dArUrl: d['model3dArUrl'] as String?,
      modelAnimations: List<String>.from((d['modelAnimations'] as List?)?.whereType<String>() ?? const []),
      variants: [for (final v in rawVariants) if (v is Map && v['id'] != null) ProductVariant.fromMap(v)],
      category: (d['category'] as String?) ?? '',
      active: d['active'] != false,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
      customization: [
        for (final o in (d['customization'] as List? ?? const []))
          if (o is Map && o['id'] != null) ProductOption.fromMap(o),
      ],
      rating: (d['rating'] as num?)?.toDouble(),
      reviewCount: (d['reviewCount'] as num?)?.toInt() ?? 0,
      textures: [
        for (final t in (d['textures'] as List? ?? const []))
          if (t is Map && (t['url'] ?? '').toString().startsWith('https://')) ProductTexture.fromMap(t),
      ],
    );
  }
}

/// One thing a buyer can customize: a choice (color, material, size…) that
/// may switch the 3D model's material variant, or a short text (engraving).
@immutable
class ProductOption {
  const ProductOption({
    required this.id,
    required this.label,
    this.type = ProductOptionType.choice,
    this.required = false,
    this.maxLength = 20,
    this.priceDelta = 0,
    this.choices = const [],
  });

  final String id;
  final String label;
  final ProductOptionType type;
  final bool required;

  /// Text options only.
  final int maxLength;
  final num priceDelta;
  final List<OptionChoice> choices;

  factory ProductOption.fromMap(Map m) => ProductOption(
        id: m['id'].toString(),
        label: (m['label'] ?? 'Option').toString(),
        type: m['type'] == 'text' ? ProductOptionType.text : ProductOptionType.choice,
        required: m['required'] == true,
        maxLength: (m['maxLength'] as num?)?.toInt() ?? 20,
        priceDelta: (m['priceDelta'] as num?) ?? 0,
        choices: [
          for (final c in (m['choices'] as List? ?? const []))
            if (c is Map && c['id'] != null) OptionChoice.fromMap(c),
        ],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type.name,
        'required': required,
        if (type == ProductOptionType.text) 'maxLength': maxLength,
        if (type == ProductOptionType.text && priceDelta > 0) 'priceDelta': priceDelta,
        if (type == ProductOptionType.choice) 'choices': [for (final c in choices) c.toMap()],
      };

  ProductOption copyWith({String? label, bool? required, int? maxLength, num? priceDelta, List<OptionChoice>? choices}) =>
      ProductOption(
        id: id,
        label: label ?? this.label,
        type: type,
        required: required ?? this.required,
        maxLength: maxLength ?? this.maxLength,
        priceDelta: priceDelta ?? this.priceDelta,
        choices: choices ?? this.choices,
      );
}

enum ProductOptionType { choice, text }

@immutable
class OptionChoice {
  const OptionChoice({required this.id, required this.label, this.priceDelta = 0, this.colorHex, this.modelVariant, this.texture});

  /// Texture this choice puts on the model (e.g. Leather → Cognac).
  final ProductTexture? texture;
  final String id;
  final String label;
  final num priceDelta;
  final String? colorHex;

  /// Material variant name inside the GLB that this choice shows.
  final String? modelVariant;

  Color? get color {
    final h = colorHex?.replaceAll('#', '');
    if (h == null || h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  factory OptionChoice.fromMap(Map m) => OptionChoice(
        id: m['id'].toString(),
        label: (m['label'] ?? m['id']).toString(),
        priceDelta: (m['priceDelta'] as num?) ?? 0,
        colorHex: m['colorHex'] as String?,
        modelVariant: m['modelVariant'] as String?,
        texture: m['texture'] is Map && ((m['texture'] as Map)['url'] ?? '').toString().startsWith('https://')
            ? ProductTexture.fromMap(m['texture'] as Map)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        if (texture != null) 'texture': texture!.toMap(),
        if (priceDelta > 0) 'priceDelta': priceDelta,
        if (colorHex != null) 'colorHex': colorHex,
        if (modelVariant != null && modelVariant!.isNotEmpty) 'modelVariant': modelVariant,
      };
}

/// Seller store settings shown to buyers and used by the portal.
@immutable
class StoreSettings {
  const StoreSettings({
    this.returnsPolicy = '',
    this.shippingNote = '',
    this.contact = '',
    this.pickup = true,
    this.delivery = true,
    this.countries = const [],
    this.lowStockAt = 5,
  });

  final String returnsPolicy;
  final String shippingNote;
  final String contact;
  final bool pickup;
  final bool delivery;

  /// ISO country codes the shop ships to (empty = its own country).
  final List<String> countries;
  final int lowStockAt;

  factory StoreSettings.parse(Map<String, dynamic> d) {
    final pol = d['policies'] is Map ? d['policies'] as Map : const {};
    final ship = d['shipping'] is Map ? d['shipping'] as Map : const {};
    return StoreSettings(
      returnsPolicy: (pol['returns'] ?? '').toString(),
      shippingNote: (pol['shipping'] ?? '').toString(),
      contact: (pol['contact'] ?? '').toString(),
      pickup: ship['pickup'] != false,
      delivery: ship['delivery'] != false,
      countries: List<String>.from((ship['countries'] as List?)?.whereType<String>() ?? const []),
      lowStockAt: (d['lowStockAt'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic> toMap() => {
        'policies': {'returns': returnsPolicy.trim(), 'shipping': shippingNote.trim(), 'contact': contact.trim()},
        'shipping': {'pickup': pickup, 'delivery': delivery, 'countries': countries},
        'lowStockAt': lowStockAt,
      };
}

/// A seller discount code (`biz_shops/{uid}/codes/{CODE}`).
@immutable
class DiscountCode {
  const DiscountCode({required this.code, this.active = true, this.percentOff, this.amountOff, this.minSpend, this.maxUses, this.uses = 0, this.endsAt});
  final String code;
  final bool active;
  final int? percentOff;
  final num? amountOff;
  final num? minSpend;
  final int? maxUses;
  final int uses;
  final DateTime? endsAt;

  factory DiscountCode.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DiscountCode(
      code: doc.id,
      active: d['active'] != false,
      percentOff: (d['percentOff'] as num?)?.toInt(),
      amountOff: d['amountOff'] as num?,
      minSpend: d['minSpend'] as num?,
      maxUses: (d['maxUses'] as num?)?.toInt(),
      uses: (d['uses'] as num?)?.toInt() ?? 0,
      endsAt: _date(d['endsAt']),
    );
  }

  String get summary => percentOff != null ? '$percentOff% off' : (amountOff != null ? '$amountOff off' : 'Discount');
}

/// A live session the shop owner is running right now (from `live_streams`).
@immutable
class ShopLive {
  final String streamId;
  final String title;
  final int viewerCount;
  final String? featuredProductId;

  const ShopLive({required this.streamId, required this.title, this.viewerCount = 0, this.featuredProductId});
}

/// A seamless material image from the hosted texture library or a seller's
/// own set, with the physical look the 3D viewer applies with it.
@immutable
class ShopTexture {
  const ShopTexture({
    required this.id,
    required this.name,
    required this.url,
    this.kind = '',
    this.category = '',
    this.roughness = 0.6,
    this.metallic = 0,
    this.scale = 1,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String url;
  final String kind;
  final String category;
  final double roughness;
  final double metallic;

  /// Repeats across the model's UVs (higher = smaller pattern).
  final double scale;
  final bool builtIn;

  factory ShopTexture.fromMap(String id, Map m) => ShopTexture(
        id: id,
        name: (m['name'] ?? 'Texture').toString(),
        url: (m['url'] ?? '').toString(),
        kind: (m['kind'] ?? '').toString(),
        category: (m['category'] ?? '').toString(),
        roughness: (m['roughness'] as num?)?.toDouble() ?? 0.6,
        metallic: (m['metallic'] as num?)?.toDouble() ?? 0,
        scale: (m['scale'] as num?)?.toDouble() ?? 1,
        builtIn: m['builtIn'] == true,
      );
}

/// A texture put on one material of a product's model ('' = every material).
@immutable
class ProductTexture {
  const ProductTexture({required this.material, required this.texture});
  final String material;
  final ShopTexture texture;

  factory ProductTexture.fromMap(Map m) => ProductTexture(
        material: (m['material'] ?? '').toString(),
        texture: ShopTexture.fromMap((m['textureId'] ?? '').toString(), m),
      );

  Map<String, dynamic> toMap() => {
        'material': material,
        'textureId': texture.id,
        'name': texture.name,
        'url': texture.url,
        'roughness': texture.roughness,
        'metallic': texture.metallic,
        'scale': texture.scale,
      };
}
