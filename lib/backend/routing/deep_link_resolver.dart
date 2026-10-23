import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../observability/telemetry_service.dart';

final deepLinkResolverProvider = Provider<DeepLinkResolver>((ref) {
  return DeepLinkResolver(ref.read(telemetryServiceProvider));
});

/// Resolves incoming deep links (e.g. from Notifications or SMS).
/// Rule: Before opening: authenticate, authorize, resolve object, load destination.
/// Rule: Never expose private resource existence (return 404/NotFound if unauthorized).
class DeepLinkResolver {
  final TelemetryService _telemetry;

  DeepLinkResolver(this._telemetry);

  /// Resolves a resource and returns the safe GoRouter path, or '/404' if unauthorized/missing.
  Future<String> resolveAndAuthorize(String type, String id, {String? mockUid}) async {
    final uid = mockUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // Must authenticate first. The GoRouter redirect guard will handle kicking to /auth/main_login.
      // But we preserve the intention if possible via query params, or just let it fail safely.
      return '/auth/main_login'; 
    }

    _telemetry.logEvent('deep_link_resolution_started', {'type': type, 'id': id});

    try {
      final isAuthorized = await _checkResourceAuthorization(type, id, uid);
      
      if (!isAuthorized) {
        // Obfuscate existence: If they don't have access, pretend it doesn't exist.
        return '/404'; 
      }

      // Map verified resource to the exact routing path
      switch (type) {
        case 'profile':
          return '/communication/contact/$id';
        case 'video':
          return '/creator_studio/video/$id';
        case 'comment':
          // Hypothetical route to open a video scrolled to a specific comment
          return '/creator_studio/video/$id?focus=comment';
        case 'message':
          return '/remote_chat?thread=$id';
        case 'live':
          return '/live/viewer/$id';
        case 'subscription':
          return '/studio/subscriptions';
        case 'payment':
          return '/studio/monetization?tab=payments&id=$id';
        case 'ai_activity':
          return '/automations/$id/history';
        default:
          return '/404';
      }
    } catch (e) {
      _telemetry.recordException(e as Exception, StackTrace.current);
      return '/404'; // Default safe fallback
    }
  }

  /// Simulates a backend call to verify existence AND authorization.
  /// In a real app, this would be an RPC call: `POST /api/v1/resolve_link { type, id }`
  /// which evaluates Firestore rules server-side.
  Future<bool> _checkResourceAuthorization(String type, String id, String uid) async {
    // Simulated backend check latency
    await Future.delayed(const Duration(milliseconds: 300));
    
    // For demonstration: allow all EXCEPT a specific blacklisted ID pattern to prove functionality.
    if (id == 'secret-resource' || id.startsWith('private_')) {
      return false; // Triggers the 404
    }
    
    return true; 
  }
}
