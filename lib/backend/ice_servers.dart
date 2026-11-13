import 'package:flutter/foundation.dart';

/// ICE servers for the phone ↔ computer link, from the `getIceServers`
/// Cloud Function (short-lived TURN credentials when the relay is set up,
/// otherwise STUN). Cached until shortly before the credentials expire;
/// falls back to public STUN if the function can't be reached, so a
/// connection attempt never waits on it for long.
class IceServers {
  IceServers._();

  static const List<Map<String, dynamic>> stunOnly = [
    {
      'urls': ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'],
    },
  ];

  static List<Map<String, dynamic>>? _cached;
  static DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  static bool relayAvailable = false;

  /// [fetch] calls the callable and returns its data map.
  static Future<List<Map<String, dynamic>>> resolve(
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    final cached = _cached;
    if (cached != null && DateTime.now().isBefore(_expires)) return cached;
    try {
      final data = await fetch().timeout(const Duration(seconds: 4));
      final list = (data['iceServers'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (list.isEmpty) return stunOnly;
      final ttl = (data['ttl'] as num?)?.toInt() ?? 3600;
      relayAvailable = data['relay'] == true;
      _cached = list;
      // Refresh 10 minutes before the TURN credentials expire.
      _expires = DateTime.now().add(Duration(seconds: (ttl - 600).clamp(60, ttl)));
      return list;
    } catch (e) {
      debugPrint('[IceServers] using STUN only: $e');
      return stunOnly;
    }
  }
}
