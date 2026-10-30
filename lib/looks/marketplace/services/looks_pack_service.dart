import 'dart:async';
import '../../models/oneova_look.dart';
import '../models/looks_pack_models.dart';
import 'wallet_service.dart';

/// Service coordinating the publication, packaging, purchase, and entitlement of `.oneovapack` bundles.
class LooksPackService {
  final WalletService walletService;

  // In-memory catalog of published packs
  final List<OneovaLookPack> _catalogPacks = List.from(OneovaLookPack.starterPacks);

  // In-memory entitlement store: userId -> Set<packId>
  final Map<String, Set<String>> _userEntitlements = {
    'user_studio_pro': {'pack_clean_commercial'},
  };

  LooksPackService({required this.walletService});

  /// Packages a collection of looks into a publishable `.oneovapack` JSON structure.
  Map<String, dynamic> exportPackBundle({
    required String title,
    required String description,
    required String creatorId,
    required String creatorName,
    required int priceCoins,
    required double priceFiat,
    required List<OneovaLook> looks,
    required List<BeforeAfterStillPair> stills,
    String? previewVideoUrl,
    List<String> tags = const [],
  }) {
    final packId = 'pack_${DateTime.now().millisecondsSinceEpoch}';
    final pack = OneovaLookPack(
      id: packId,
      title: title,
      description: description,
      creatorId: creatorId,
      creatorName: creatorName,
      creatorAvatarUrl: '',
      priceCoins: priceCoins,
      priceFiat: priceFiat,
      previewVideoUrl: previewVideoUrl ?? '',
      thumbnailUrl: stills.isNotEmpty ? stills.first.afterUrl : '',
      beforeAfterStills: stills,
      looks: looks,
      tags: tags,
      publishedAt: DateTime.now(),
    );

    return {
      'format': 'oneovapack_v1',
      'manifest': pack.toJson(),
      'checksum': '${packId}_sha256_mock',
    };
  }

  /// Publishes a pack to the Oneova Biz Marketplace.
  Future<OneovaLookPack> publishPack(OneovaLookPack pack) async {
    _catalogPacks.insert(0, pack);
    return pack;
  }

  /// Fetches published marketplace packs, optionally filtered by tag or category.
  Future<List<OneovaLookPack>> getMarketplacePacks({String? searchTag}) async {
    if (searchTag == null || searchTag.isEmpty) {
      return List.unmodifiable(_catalogPacks);
    }
    return _catalogPacks.where((p) => p.tags.any((t) => t.toLowerCase().contains(searchTag.toLowerCase()))).toList();
  }

  /// Checks if a user has unlocked a specific pack.
  bool hasUserUnlockedPack(String userId, String packId) {
    final userPacks = _userEntitlements[userId];
    if (userPacks != null && userPacks.contains(packId)) {
      return true;
    }
    // Free packs are considered automatically unlocked
    final pack = _catalogPacks.firstWhere((p) => p.id == packId, orElse: () => _catalogPacks.first);
    return pack.isFree;
  }

  /// Unlocks a pack for a user using Oneova Coins.
  Future<PackEntitlement> purchasePackWithCoins({
    required String userId,
    required String packId,
  }) async {
    final pack = _catalogPacks.firstWhere(
      (p) => p.id == packId,
      orElse: () => throw Exception('Pack $packId not found in catalog'),
    );

    if (hasUserUnlockedPack(userId, packId)) {
      throw Exception('Pack "${pack.title}" is already unlocked');
    }

    if (pack.priceCoins > 0) {
      await walletService.deductCoins(
        userId: userId,
        amountCoins: pack.priceCoins,
        description: 'Purchase look pack: ${pack.title}',
        referenceId: packId,
      );

      // Credit the creator (80% creator rev-share, 20% platform fee)
      final creatorEarningsCoins = (pack.priceCoins * 0.8).toInt();
      await walletService.creditCoins(
        userId: pack.creatorId,
        amountCoins: creatorEarningsCoins,
        description: 'Marketplace sale: ${pack.title} (80% rev share)',
        referenceId: packId,
      );
    }

    // Register entitlement
    _userEntitlements.putIfAbsent(userId, () => <String>{}).add(packId);

    final entitlement = PackEntitlement(
      entitlementId: 'ent_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      packId: packId,
      purchasedAt: DateTime.now(),
      transactionRef: 'txn_coin_$packId',
    );

    return entitlement;
  }
}
