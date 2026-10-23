import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/recommendation/algorithm/geo_radius_distribution_engine.dart';
import 'package:oneova/backend/social/models/content.dart';

void main() {
  group('GeoRadiusDistributionEngine Tests', () {
    late GeoRadiusDistributionEngine engine;

    setUp(() {
      engine = GeoRadiusDistributionEngine();
    });

    test('calculateDistanceKm returns 0 for identical coordinates', () {
      final distance = GeoRadiusDistributionEngine.calculateDistanceKm(
        37.7749, -122.4194,
        37.7749, -122.4194,
      );
      expect(distance, closeTo(0.0, 0.001));
    });

    test('calculateDistanceKm returns accurate distance between SF and Oakland (~13 km)', () {
      final distance = GeoRadiusDistributionEngine.calculateDistanceKm(
        37.7749, -122.4194, // San Francisco
        37.8044, -122.2712, // Oakland
      );
      expect(distance, greaterThan(10.0));
      expect(distance, lessThan(20.0));
    });

    test('calculateGeoRelevanceScore applies correct tier multipliers', () {
      // Content at downtown Nairobi: -1.286389, 36.817223
      final content = Content(
        id: 'nairobi_post',
        authorId: 'creator_1',
        description: 'Vibes in the city #nairobi',
        mediaUrl: 'https://video.mp4',
        mediaMetadata: MediaMetadata(),
        latitude: -1.286389,
        longitude: 36.817223,
        createdAt: DateTime.now(),
      );

      // 1. Hyperlocal (< 10 km): ~3 km away
      final hyperlocalScore = engine.calculateGeoRelevanceScore(
        content,
        -1.260000, 36.800000,
      );
      expect(hyperlocalScore, 1.5);

      // 2. City (10 - 50 km): ~25 km away
      final cityScore = engine.calculateGeoRelevanceScore(
        content,
        -1.100000, 36.900000,
      );
      expect(cityScore, 1.3);

      // 3. Regional (50 - 200 km): ~140 km away (Nakuru)
      final regionalScore = engine.calculateGeoRelevanceScore(
        content,
        -0.303099, 36.080025,
      );
      expect(regionalScore, 1.1);

      // 4. Global (> 200 km): Mombasa (~440 km)
      final globalScore = engine.calculateGeoRelevanceScore(
        content,
        -4.043477, 39.668206,
      );
      expect(globalScore, 1.0);

      // 5. Fallback for null coordinates
      expect(engine.calculateGeoRelevanceScore(content, null, null), 1.0);
    });

    test('determineContentGeoTier graduates content based on views and engagement', () {
      // Tier 0 incubator (< 300 views) with low engagement remains hyperlocal
      expect(
        engine.determineContentGeoTier(150, 0.05),
        ContentGeoTier.hyperlocal,
      );

      // Tier 0 incubator (< 300 views) with high engagement (> 15%) breaks out to city
      expect(
        engine.determineContentGeoTier(150, 0.18),
        ContentGeoTier.city,
      );

      // Tier 1 emerging (300 - 2,500) with standard engagement -> city
      expect(
        engine.determineContentGeoTier(1200, 0.08),
        ContentGeoTier.city,
      );

      // Tier 1 emerging with high engagement (> 12%) -> regional
      expect(
        engine.determineContentGeoTier(1200, 0.14),
        ContentGeoTier.regional,
      );

      // Tier 2 trending (2,500 - 25,000) with high engagement (> 10%) -> global
      expect(
        engine.determineContentGeoTier(10000, 0.12),
        ContentGeoTier.global,
      );

      // Tier 3 megapool (25,000+) -> global unconditionally
      expect(
        engine.determineContentGeoTier(30000, 0.04),
        ContentGeoTier.global,
      );
    });

    test('evaluateDistributionStatus returns correct status payload and notes', () {
      final status = engine.evaluateDistributionStatus(100, 0.04);
      expect(status.tier, ContentGeoTier.hyperlocal);
      expect(status.isRestrictedToLocal, isTrue);
      expect(status.isEligibleForGlobal, isFalse);
      expect(status.radiusKm, 10.0);
      expect(status.graduationNote, contains('hyperlocal'));
    });
  });
}
