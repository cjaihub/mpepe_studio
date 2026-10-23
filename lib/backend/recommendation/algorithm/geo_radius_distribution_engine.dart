import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../social/models/content.dart';

final geoRadiusDistributionEngineProvider = Provider<GeoRadiusDistributionEngine>((ref) {
  return GeoRadiusDistributionEngine();
});

/// Geo-distribution tiers representing content reach zones
enum ContentGeoTier {
  hyperlocal(radiusKm: 10.0, label: 'Hyperlocal (< 10 km)'),
  city(radiusKm: 50.0, label: 'City (10 - 50 km)'),
  regional(radiusKm: 200.0, label: 'Regional (50 - 200 km)'),
  global(radiusKm: double.infinity, label: 'Global (> 200 km)');

  final double radiusKm;
  final String label;

  const ContentGeoTier({required this.radiusKm, required this.label});

  /// True if content has broken out to worldwide distribution
  bool get isGlobal => this == ContentGeoTier.global;

  /// True if content is confined to local or city-scale reach
  bool get isRestrictedToLocal => this == ContentGeoTier.hyperlocal || this == ContentGeoTier.city;
}

/// Comprehensive outcome of geo-tier evaluation
class GeoDistributionStatus {
  final ContentGeoTier tier;
  final bool isEligibleForGlobal;
  final bool isRestrictedToLocal;
  final double radiusKm;
  final String graduationNote;

  const GeoDistributionStatus({
    required this.tier,
    required this.isEligibleForGlobal,
    required this.isRestrictedToLocal,
    required this.radiusKm,
    required this.graduationNote,
  });
}

/// Smart Geo-Radius Distribution Engine for Oneova.
///
/// Seeds fresh creator uploads to nearby local audiences first (5km/25km/50km/city),
/// graduating to regional and global discovery pools as viral thresholds and high
/// engagement ratios are achieved.
class GeoRadiusDistributionEngine {
  static const double earthRadiusKm = 6371.0;

  // Multiplier Constants
  static const double tier0HyperlocalMultiplier = 1.5; // < 10 km
  static const double tier1CityMultiplier = 1.3;       // 10 - 50 km
  static const double tier2RegionalMultiplier = 1.1;   // 50 - 200 km
  static const double tier3GlobalMultiplier = 1.0;     // > 200 km

  /// Calculates the great-circle distance between two GPS coordinates using the Haversine formula.
  static double calculateDistanceKm(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final dLat = _toRadians(endLat - startLat);
    final dLng = _toRadians(endLng - startLng);

    final lat1Rad = _toRadians(startLat);
    final lat2Rad = _toRadians(endLat);

    final a = math.sin(dLat / 2.0) * math.sin(dLat / 2.0) +
        math.sin(dLng / 2.0) * math.sin(dLng / 2.0) * math.cos(lat1Rad) * math.cos(lat2Rad);

    final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));

    return earthRadiusKm * c;
  }

  static double _toRadians(double degree) => degree * (math.pi / 180.0);

  /// Computes the geo-relevance score multiplier for a viewer relative to the content's origin.
  ///
  /// Multipliers:
  /// - Tier 0: < 10 km   -> 1.5x (Hyperlocal boost for new posts)
  /// - Tier 1: 10 - 50 km -> 1.3x (City boost)
  /// - Tier 2: 50 - 200 km -> 1.1x (Regional boost)
  /// - Tier 3: > 200 km  -> 1.0x (Global standard)
  ///
  /// If either the content or viewer geolocation is missing, standard 1.0x is returned.
  double calculateGeoRelevanceScore(Content content, double? userLat, double? userLng) {
    if (userLat == null || userLng == null) return tier3GlobalMultiplier;
    if (content.latitude == null || content.longitude == null) return tier3GlobalMultiplier;

    final distanceKm = calculateDistanceKm(
      content.latitude!,
      content.longitude!,
      userLat,
      userLng,
    );

    if (distanceKm < 10.0) {
      return tier0HyperlocalMultiplier;
    } else if (distanceKm < 50.0) {
      return tier1CityMultiplier;
    } else if (distanceKm <= 200.0) {
      return tier2RegionalMultiplier;
    } else {
      return tier3GlobalMultiplier;
    }
  }

  /// Determines whether content is restricted to local/city or eligible for global promotion
  /// based on audience view pool saturation and engagement rate.
  ContentGeoTier determineContentGeoTier(int viewCount, double engagementRate) {
    // Tier 0 Sandbox: under 300 impressions
    if (viewCount < 300) {
      // Early breakout: exceptionally high engagement (> 15%) moves content to city tier
      return (engagementRate >= 0.15) ? ContentGeoTier.city : ContentGeoTier.hyperlocal;
    }

    // Tier 1 Emerging: 300 - 2,500 impressions
    if (viewCount < 2500) {
      return (engagementRate >= 0.12) ? ContentGeoTier.regional : ContentGeoTier.city;
    }

    // Tier 2 Trending: 2,500 - 25,000 impressions
    if (viewCount < 25000) {
      return (engagementRate >= 0.10) ? ContentGeoTier.global : ContentGeoTier.regional;
    }

    // Tier 3 Megapool: 25,000+ impressions
    return ContentGeoTier.global;
  }

  /// Detailed geo-distribution analysis with human-readable rationale
  GeoDistributionStatus evaluateDistributionStatus(int viewCount, double engagementRate) {
    final tier = determineContentGeoTier(viewCount, engagementRate);
    final isGlobal = tier == ContentGeoTier.global;
    final isRestricted = tier.isRestrictedToLocal;

    String note;
    switch (tier) {
      case ContentGeoTier.hyperlocal:
        note = 'Seeded in hyperlocal neighborhood sandbox (< 10 km). Needs 15% engagement to graduate.';
        break;
      case ContentGeoTier.city:
        note = 'Graduated to metropolitan city pool (10 - 50 km). Escalating with active local viewer resonance.';
        break;
      case ContentGeoTier.regional:
        note = 'Regional distribution unlocked (50 - 200 km). Strong engagement velocity driving national expansion.';
        break;
      case ContentGeoTier.global:
        note = 'Global megapool unlocked. Content has breached viral thresholds worldwide.';
        break;
    }

    return GeoDistributionStatus(
      tier: tier,
      isEligibleForGlobal: isGlobal,
      isRestrictedToLocal: isRestricted,
      radiusKm: tier.radiusKm,
      graduationNote: note,
    );
  }
}
