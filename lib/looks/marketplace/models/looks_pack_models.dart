import 'package:flutter/foundation.dart';
import '../../models/oneova_look.dart';

/// A pair of before and after preview image URLs for showcasing a look.
@immutable
class BeforeAfterStillPair {
  final String beforeUrl;
  final String afterUrl;
  final String lookTitle;

  const BeforeAfterStillPair({
    required this.beforeUrl,
    required this.afterUrl,
    required this.lookTitle,
  });

  Map<String, dynamic> toJson() => {
        'before_url': beforeUrl,
        'after_url': afterUrl,
        'look_title': lookTitle,
      };

  factory BeforeAfterStillPair.fromJson(Map<String, dynamic> json) {
    return BeforeAfterStillPair(
      beforeUrl: json['before_url'] as String,
      afterUrl: json['after_url'] as String,
      lookTitle: json['look_title'] as String,
    );
  }
}

/// A published or downloadable Look Pack (`.oneovafx` / `.oneovapack`).
@immutable
class OneovaLookPack {
  final String id;
  final String title;
  final String description;
  final String creatorId;
  final String creatorName;
  final String creatorAvatarUrl;
  final int priceCoins;
  final double priceFiat;
  final String currency;
  final String previewVideoUrl;
  final String thumbnailUrl;
  final List<BeforeAfterStillPair> beforeAfterStills;
  final List<OneovaLook> looks;
  final List<String> tags;
  final int downloadCount;
  final double rating;
  final DateTime publishedAt;
  final bool isFeatured;

  const OneovaLookPack({
    required this.id,
    required this.title,
    required this.description,
    required this.creatorId,
    required this.creatorName,
    required this.creatorAvatarUrl,
    required this.priceCoins,
    required this.priceFiat,
    this.currency = 'USD',
    required this.previewVideoUrl,
    required this.thumbnailUrl,
    required this.beforeAfterStills,
    required this.looks,
    this.tags = const [],
    this.downloadCount = 0,
    this.rating = 5.0,
    required this.publishedAt,
    this.isFeatured = false,
  });

  bool get isFree => priceCoins == 0 && priceFiat == 0.0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'creator_id': creatorId,
      'creator_name': creatorName,
      'creator_avatar_url': creatorAvatarUrl,
      'price_coins': priceCoins,
      'price_fiat': priceFiat,
      'currency': currency,
      'preview_video_url': previewVideoUrl,
      'thumbnail_url': thumbnailUrl,
      'before_after_stills': beforeAfterStills.map((s) => s.toJson()).toList(),
      'looks': looks.map((l) => l.toMap()).toList(),
      'tags': tags,
      'download_count': downloadCount,
      'rating': rating,
      'published_at': publishedAt.toIso8601String(),
      'is_featured': isFeatured,
    };
  }

  factory OneovaLookPack.fromJson(Map<String, dynamic> json) {
    return OneovaLookPack(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      creatorId: json['creator_id'] as String,
      creatorName: json['creator_name'] as String? ?? 'Oneova Creator',
      creatorAvatarUrl: json['creator_avatar_url'] as String? ?? '',
      priceCoins: (json['price_coins'] as num?)?.toInt() ?? 0,
      priceFiat: (json['price_fiat'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      previewVideoUrl: json['preview_video_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      beforeAfterStills: (json['before_after_stills'] as List<dynamic>?)
              ?.map((s) => BeforeAfterStillPair.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      looks: (json['looks'] as List<dynamic>?)
              ?.map((l) => OneovaLook.fromMap(l as Map<String, dynamic>))
              .toList() ??
          const [],
      tags: (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? const [],
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : DateTime.now(),
      isFeatured: json['is_featured'] as bool? ?? false,
    );
  }

  /// Official starter marketplace look packs.
  static List<OneovaLookPack> starterPacks = [
    OneovaLookPack(
      id: 'pack_cine_blockbuster',
      title: 'Cinematic Blockbuster Master Pack',
      description: '5 Hollywood color grades inspired by sci-fi, drama, and anamorphic blockbusters.',
      creatorId: 'oneova_curation',
      creatorName: 'Oneova Studios',
      creatorAvatarUrl: 'assets/avatars/oneova_studios.jpg',
      priceCoins: 150,
      priceFiat: 4.99,
      previewVideoUrl: 'https://cdn.example.com/showcase/cine_blockbuster.mp4',
      thumbnailUrl: 'assets/marketplace/cine_pack.jpg',
      tags: ['Cinematic', 'Hollywood', 'Teal & Orange', 'Sci-Fi'],
      beforeAfterStills: const [
        BeforeAfterStillPair(
          beforeUrl: 'assets/stills/take1_before.jpg',
          afterUrl: 'assets/stills/take1_after.jpg',
          lookTitle: 'Neo Tokyo Teal',
        ),
      ],
      looks: const [
        OneovaLook(
          id: 'look_cine_blockbuster_1',
          name: 'Neo Tokyo Teal',
          categories: ['Cinematic'],
          intensity: 0.90,
        ),
      ],
      downloadCount: 1420,
      rating: 4.9,
      publishedAt: CustomPackTime(daysAgo: 7),
      isFeatured: true,
    ),
    OneovaLookPack(
      id: 'pack_vintage_kodak',
      title: 'Analog Film & 35mm Gold',
      description: 'Authentic warm halide grain, halation, and rich film curve emulation.',
      creatorId: 'creator_film_lab',
      creatorName: 'Kodak Revival Lab',
      creatorAvatarUrl: 'assets/avatars/film_lab.jpg',
      priceCoins: 100,
      priceFiat: 2.99,
      previewVideoUrl: 'https://cdn.example.com/showcase/vintage_film.mp4',
      thumbnailUrl: 'assets/marketplace/film_pack.jpg',
      tags: ['Film', '35mm', 'Kodak', 'Halation'],
      beforeAfterStills: const [
        BeforeAfterStillPair(
          beforeUrl: 'assets/stills/take2_before.jpg',
          afterUrl: 'assets/stills/take2_after.jpg',
          lookTitle: 'Gold 200 Warmth',
        ),
      ],
      looks: const [
        OneovaLook(
          id: 'look_vintage_gold_1',
          name: 'Gold 200 Warmth',
          categories: ['Film Stocks'],
          intensity: 0.85,
        ),
      ],
      downloadCount: 890,
      rating: 4.8,
      publishedAt: CustomPackTime(daysAgo: 12),
      isFeatured: true,
    ),
    OneovaLookPack(
      id: 'pack_clean_commercial',
      title: 'Clean Executive Commercial',
      description: 'High dynamic range clarity and pure whites designed for product launches and business branding.',
      creatorId: 'oneova_curation',
      creatorName: 'Oneova Studios',
      creatorAvatarUrl: 'assets/avatars/oneova_studios.jpg',
      priceCoins: 0,
      priceFiat: 0.0,
      previewVideoUrl: 'https://cdn.example.com/showcase/clean_commercial.mp4',
      thumbnailUrl: 'assets/marketplace/commercial_pack.jpg',
      tags: ['Clean', 'Business', 'Corporate', 'HDR'],
      beforeAfterStills: const [],
      looks: const [
        OneovaLook(
          id: 'look_clean_comm_1',
          name: 'Executive Clean HDR',
          categories: ['Clean Commercial'],
          intensity: 1.0,
        ),
      ],
      downloadCount: 3100,
      rating: 5.0,
      publishedAt: CustomPackTime(daysAgo: 20),
      isFeatured: false,
    ),
  ];
}

class CustomPackTime implements DateTime {
  final int daysAgo;
  const CustomPackTime({this.daysAgo = 0});

  @override
  DateTime subtract(Duration duration) => DateTime.now().subtract(duration);
  @override
  String toIso8601String() => DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// User entitlement record verifying ownership of a purchased pack.
@immutable
class PackEntitlement {
  final String entitlementId;
  final String userId;
  final String packId;
  final DateTime purchasedAt;
  final String transactionRef;

  const PackEntitlement({
    required this.entitlementId,
    required this.userId,
    required this.packId,
    required this.purchasedAt,
    required this.transactionRef,
  });

  Map<String, dynamic> toJson() => {
        'entitlement_id': entitlementId,
        'user_id': userId,
        'pack_id': packId,
        'purchased_at': purchasedAt.toIso8601String(),
        'transaction_ref': transactionRef,
      };

  factory PackEntitlement.fromJson(Map<String, dynamic> json) {
    return PackEntitlement(
      entitlementId: json['entitlement_id'] as String,
      userId: json['user_id'] as String,
      packId: json['pack_id'] as String,
      purchasedAt: DateTime.parse(json['purchased_at'] as String),
      transactionRef: json['transaction_ref'] as String,
    );
  }
}
