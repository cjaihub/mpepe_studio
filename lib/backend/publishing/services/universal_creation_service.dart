import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/publishing_destination.dart';

final universalCreationServiceProvider = Provider<UniversalCreationService>((ref) {
  return UniversalCreationService();
});

class CrossPlatformPublishRequest {
  final CreationType type;
  final String mediaUrl;
  final String caption;
  final List<ConnectedAccount> selectedDestinations;

  CrossPlatformPublishRequest({
    required this.type,
    required this.mediaUrl,
    required this.caption,
    required this.selectedDestinations,
  });
}

class UniversalCreationService {
  /// Resolves the valid, connected accounts for the user.
  Future<List<ConnectedAccount>> getConnectedAccounts(String userId) async {
    // In a real app, query OAuth tokens from the secure vault
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      ConnectedAccount(
        accountId: 'internal_1',
        platform: PlatformDestination.internal,
        accountName: 'My ONEROVA Account',
        avatarUrl: 'https://example.com/avatar1.jpg',
        isAuthorized: true,
      ),
      ConnectedAccount(
        accountId: 'ig_123',
        platform: PlatformDestination.instagram,
        accountName: 'my.insta.creator',
        avatarUrl: 'https://example.com/avatar2.jpg',
        isAuthorized: true,
      ),
      ConnectedAccount(
        accountId: 'fb_123',
        platform: PlatformDestination.facebook,
        accountName: 'My FB Page',
        avatarUrl: 'https://example.com/avatar3.jpg',
        isAuthorized: true,
      ),
      ConnectedAccount(
        accountId: 'tk_123',
        platform: PlatformDestination.tiktok,
        accountName: 'tiktok_star',
        avatarUrl: 'https://example.com/avatar4.jpg',
        isAuthorized: true,
      ),
    ];
  }

  /// Filters down the user's connected accounts strictly to those that
  /// technically support the [CreationType] currently being created.
  /// Never display unsupported controls.
  Future<List<ConnectedAccount>> getAvailableDestinationsFor(String userId, CreationType type) async {
    final accounts = await getConnectedAccounts(userId);
    return accounts.where((account) => account.capabilities.canPublish(type)).toList();
  }

  /// Broadcasts the content to the selected destinations concurrently.
  Future<Map<PlatformDestination, bool>> publishToDestinations(CrossPlatformPublishRequest request) async {
    final Map<PlatformDestination, bool> results = {};
    
    // Safety check: Filter out any selected destinations that don't support the type
    // (In case the UI leaked or was bypassed)
    final validDestinations = request.selectedDestinations.where(
      (dest) => dest.capabilities.canPublish(request.type)
    ).toList();

    // Map each API request natively 
    await Future.wait(validDestinations.map((dest) async {
      try {
        // Enforce capabilities (e.g. caption length)
        final safeCaption = request.caption.length > dest.capabilities.maxCaptionLength 
            ? request.caption.substring(0, dest.capabilities.maxCaptionLength)
            : request.caption;
            
        // Mock API call to specific platform
        await _dispatchToPlatform(dest, request.type, request.mediaUrl, safeCaption);
        results[dest.platform] = true;
      } catch (e) {
        results[dest.platform] = false;
      }
    }));

    return results;
  }

  Future<void> _dispatchToPlatform(ConnectedAccount dest, CreationType type, String url, String caption) async {
    // Dispatch to specific OAuth platform API mapping
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
