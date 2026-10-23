class CreatorServiceListing {
  final String id;
  final String title;
  final String description;
  final double? price; // Optional pricing
  final String currency;

  const CreatorServiceListing({
    required this.id,
    required this.title,
    required this.description,
    this.price,
    this.currency = 'USD',
  });
}

class CreatorMarketplaceProfile {
  final String userId;
  final String displayName;
  final List<String> skills;
  final List<CreatorServiceListing> services;
  final List<String> portfolioUrls;
  final bool isAvailable;
  final String locationScope; // 'Global', 'Local', 'Remote', etc.
  final List<String> languages;
  final List<String> categories;
  
  // Private field explicitly guarded
  final String _privateEmail;
  final String _privatePhone;
  final bool allowDirectContact;

  const CreatorMarketplaceProfile({
    required this.userId,
    required this.displayName,
    required this.skills,
    required this.services,
    required this.portfolioUrls,
    required this.isAvailable,
    required this.locationScope,
    required this.languages,
    required this.categories,
    required this._privateEmail,
    required this._privatePhone,
    this.allowDirectContact = false,
  });

  /// Strict contact exposure guard
  String? get contactEmail => allowDirectContact ? _privateEmail : null;
  String? get contactPhone => allowDirectContact ? _privatePhone : null;
}

enum CollaborationStatus {
  pending,
  accepted,
  declined,
  completed,
}

class CollaborationRequest {
  final String id;
  final String requestorId;
  final String targetCreatorId;
  final String serviceId;
  final String message;
  final double? agreedPrice;
  CollaborationStatus status;

  CollaborationRequest({
    required this.id,
    required this.requestorId,
    required this.targetCreatorId,
    required this.serviceId,
    required this.message,
    this.agreedPrice,
    this.status = CollaborationStatus.pending,
  });
}
