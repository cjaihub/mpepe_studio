import 'package:cloud_firestore/cloud_firestore.dart';

enum MonetizationFeatureType {
  subscriptions,
  premiumSeries,
  tips,
  gifts,
  creatorRewards,
  digitalProducts,
  affiliateLinks,
  brandCollaborations,
  creatorMarketplace,
  paidCommunities,
  paidEvents,
}

enum MonetizationStatus {
  notEligible,
  eligible,
  active,
  suspended,
}

class MonetizationFeature {
  final MonetizationFeatureType type;
  final MonetizationStatus status;
  final Map<String, dynamic> config; // Feature-specific configuration (e.g. price tiers)
  
  const MonetizationFeature({
    required this.type,
    this.status = MonetizationStatus.notEligible,
    this.config = const {},
  });

  factory MonetizationFeature.fromMap(Map<String, dynamic> map) {
    return MonetizationFeature(
      type: MonetizationFeatureType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MonetizationFeatureType.tips,
      ),
      status: MonetizationStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MonetizationStatus.notEligible,
      ),
      config: Map<String, dynamic>.from(map['config'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'status': status.name,
      'config': config,
    };
  }
}

class CreatorMonetizationProfile {
  final String creatorId;
  final Map<MonetizationFeatureType, MonetizationFeature> features;
  final double totalRevenue;
  final double pendingPayout;
  final String currency;

  const CreatorMonetizationProfile({
    required this.creatorId,
    required this.features,
    this.totalRevenue = 0.0,
    this.pendingPayout = 0.0,
    this.currency = 'USD',
  });

  factory CreatorMonetizationProfile.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) {
      return CreatorMonetizationProfile(creatorId: doc.id, features: {});
    }
    
    final data = doc.data() as Map<String, dynamic>;
    final rawFeatures = data['features'] as Map<String, dynamic>? ?? {};
    
    final Map<MonetizationFeatureType, MonetizationFeature> parsedFeatures = {};
    rawFeatures.forEach((key, value) {
      final feature = MonetizationFeature.fromMap(value as Map<String, dynamic>);
      parsedFeatures[feature.type] = feature;
    });

    return CreatorMonetizationProfile(
      creatorId: doc.id,
      features: parsedFeatures,
      totalRevenue: (data['totalRevenue'] ?? 0.0).toDouble(),
      pendingPayout: (data['pendingPayout'] ?? 0.0).toDouble(),
      currency: data['currency'] ?? 'USD',
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> mappedFeatures = {};
    features.forEach((key, value) {
      mappedFeatures[key.name] = value.toMap();
    });

    return {
      'features': mappedFeatures,
      'totalRevenue': totalRevenue,
      'pendingPayout': pendingPayout,
      'currency': currency,
    };
  }
}
