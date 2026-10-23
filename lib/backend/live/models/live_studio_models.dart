import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STUDIO MODELS
//
// Firestore layout (all under live_streams/{streamId}):
//   • stream doc fields: featuredProductId (string?), stageFocusUserId (string?)
//   • products/{productId}: name, price, currency, imageUrl, productUrl,
//                           createdAt, sortOrder
// ─────────────────────────────────────────────────────────────────────────────

DateTime _parseDate(dynamic val) {
  if (val is Timestamp) return val.toDate();
  if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
  return DateTime.now();
}

/// Studio-specific fields of the live_streams doc that `LiveStream` does not
/// model (kept separate so the large LiveStream model is untouched).
class LiveStudioDocState {
  final String? featuredProductId;
  final String? stageFocusUserId;
  final DateTime? featuredAt;

  const LiveStudioDocState({
    this.featuredProductId,
    this.stageFocusUserId,
    this.featuredAt,
  });

  factory LiveStudioDocState.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) => (v is String && v.isNotEmpty) ? v : null;
    return LiveStudioDocState(
      featuredProductId: str(json['featuredProductId']),
      stageFocusUserId: str(json['stageFocusUserId']),
      featuredAt:
          json['featuredAt'] == null ? null : _parseDate(json['featuredAt']),
    );
  }
}

class LiveProduct {
  final String id;
  final String name;
  final num? price;
  final String currency;
  final String imageUrl;
  final String productUrl;
  final int sortOrder;
  final DateTime createdAt;

  const LiveProduct({
    required this.id,
    required this.name,
    this.price,
    this.currency = 'USD',
    this.imageUrl = '',
    this.productUrl = '',
    this.sortOrder = 0,
    required this.createdAt,
  });

  factory LiveProduct.fromJson(String id, Map<String, dynamic> json) {
    return LiveProduct(
      id: id,
      name: json['name'] as String? ?? '',
      price: json['price'] as num?,
      currency: json['currency'] as String? ?? 'USD',
      imageUrl: json['imageUrl'] as String? ?? '',
      productUrl: json['productUrl'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'currency': currency,
        'imageUrl': imageUrl,
        'productUrl': productUrl,
        'sortOrder': sortOrder,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
