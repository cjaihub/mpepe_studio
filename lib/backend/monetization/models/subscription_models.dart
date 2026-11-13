import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionPerks {
  final bool exclusiveVideos;
  final bool exclusiveLiveStreams;
  final bool subscriberChat;
  final bool privateCommunity;
  final bool earlyAccess;
  final List<String> customPerks;
  final String? badgeImageUrl;
  final List<String> customEmojis; // URLs or standard emojis

  const SubscriptionPerks({
    this.exclusiveVideos = false,
    this.exclusiveLiveStreams = false,
    this.subscriberChat = false,
    this.privateCommunity = false,
    this.earlyAccess = false,
    this.customPerks = const [],
    this.badgeImageUrl,
    this.customEmojis = const [],
  });

  factory SubscriptionPerks.fromMap(Map<String, dynamic> map) {
    return SubscriptionPerks(
      exclusiveVideos: map['exclusiveVideos'] ?? false,
      exclusiveLiveStreams: map['exclusiveLiveStreams'] ?? false,
      subscriberChat: map['subscriberChat'] ?? false,
      privateCommunity: map['privateCommunity'] ?? false,
      earlyAccess: map['earlyAccess'] ?? false,
      customPerks: List<String>.from(map['customPerks'] ?? []),
      badgeImageUrl: map['badgeImageUrl'],
      customEmojis: List<String>.from(map['customEmojis'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'exclusiveVideos': exclusiveVideos,
      'exclusiveLiveStreams': exclusiveLiveStreams,
      'subscriberChat': subscriberChat,
      'privateCommunity': privateCommunity,
      'earlyAccess': earlyAccess,
      'customPerks': customPerks,
      'badgeImageUrl': badgeImageUrl,
      'customEmojis': customEmojis,
    };
  }
}

class SubscriptionTier {
  final String id;
  final String creatorId;
  final String name;
  final String description;
  final double price;
  final String currency;
  final SubscriptionPerks perks;
  final bool isActive;
  final String? productRef; // payment partner's product id
  final String? priceRef;   // payment partner's price id

  const SubscriptionTier({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.description,
    required this.price,
    this.currency = 'USD',
    required this.perks,
    this.isActive = true,
    this.productRef,
    this.priceRef,
  });

  factory SubscriptionTier.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionTier(
      id: doc.id,
      creatorId: data['creatorId'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: (data['price'] ?? 0.0).toDouble(),
      currency: data['currency'] ?? 'USD',
      perks: SubscriptionPerks.fromMap(data['perks'] ?? {}),
      isActive: data['isActive'] ?? true,
      productRef: data['productRef'],
      priceRef: data['priceRef'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'creatorId': creatorId,
      'name': name,
      'description': description,
      'price': price,
      'currency': currency,
      'perks': perks.toMap(),
      'isActive': isActive,
      'productRef': productRef,
      'priceRef': priceRef,
    };
  }
}

enum SubscriptionStatus {
  active,
  pastDue,
  canceled,
  expired,
}

class UserSubscription {
  final String id;
  final String subscriberId;
  final String creatorId;
  final String tierId;
  final SubscriptionStatus status;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String? providerSubscriptionId; // e.g. sub_xxx

  const UserSubscription({
    required this.id,
    required this.subscriberId,
    required this.creatorId,
    required this.tierId,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.providerSubscriptionId,
  });

  factory UserSubscription.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserSubscription(
      id: doc.id,
      subscriberId: data['subscriberId'] ?? '',
      creatorId: data['creatorId'] ?? '',
      tierId: data['tierId'] ?? '',
      status: SubscriptionStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => SubscriptionStatus.expired,
      ),
      currentPeriodStart: (data['currentPeriodStart'] as Timestamp).toDate(),
      currentPeriodEnd: (data['currentPeriodEnd'] as Timestamp).toDate(),
      cancelAtPeriodEnd: data['cancelAtPeriodEnd'] ?? false,
      providerSubscriptionId: data['providerSubscriptionId'],
    );
  }
}
