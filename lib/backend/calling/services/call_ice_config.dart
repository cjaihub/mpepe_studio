import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../../ice_servers.dart';

/// ICE server list for WebRTC calls & multi-cam links.
///
/// Combines default public STUN servers, Firebase Remote Config overrides
/// (`webrtc_ice_servers`), and short-lived Cloudflare TURN relay credentials
/// fetched from the `getIceServers` Cloud Function so calls connect reliably
/// behind symmetric NATs and carrier CGNATs.
class CallIceConfig {
  static const List<Map<String, dynamic>> _defaultStun = [
    {
      'urls': [
        'stun:stun.cloudflare.com:3478',
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];

  static List<Map<String, dynamic>> _cachedRelayServers = const [];
  static DateTime _cacheExpires = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void>? _inFlightWarmUp;

  static bool get relayAvailable => IceServers.relayAvailable;

  /// Pre-warms short-lived TURN credentials in the background so call setup
  /// has relay candidates ready without waiting on a network round-trip.
  static Future<void> warmUp() {
    if (_cachedRelayServers.isNotEmpty && DateTime.now().isBefore(_cacheExpires)) {
      return Future<void>.value();
    }
    return _inFlightWarmUp ??= _fetchTurnServers().whenComplete(() {
      _inFlightWarmUp = null;
    });
  }

  static Future<void> _fetchTurnServers() async {
    try {
      final resolved = await IceServers.resolve(() async {
        final res = await FirebaseFunctions.instance
            .httpsCallable('getIceServers')
            .call<Map<String, dynamic>>();
        return Map<String, dynamic>.from(res.data);
      }).timeout(const Duration(seconds: 3));
      _cachedRelayServers = resolved;
      _cacheExpires = DateTime.now().add(const Duration(minutes: 45));
    } catch (e) {
      debugPrint('[CallIceConfig] getIceServers warm-up skipped: $e');
    }
  }

  /// Synchronous ICE configuration (uses STUN + any cached TURN relay +
  /// Firebase Remote Config `webrtc_ice_servers`).
  static Map<String, dynamic> configuration() {
    return buildConfiguration(extraServers: _cachedRelayServers);
  }

  /// Fetches fresh TURN relay credentials if not cached, then returns the
  /// full WebRTC configuration. Falls back cleanly to STUN on offline/error.
  static Future<Map<String, dynamic>> configurationAsync() async {
    await warmUp();
    return buildConfiguration(extraServers: _cachedRelayServers);
  }

  @visibleForTesting
  static Map<String, dynamic> buildConfiguration({
    List<Map<String, dynamic>> extraServers = const [],
    List<Map<String, dynamic>> remoteConfigServers = const [],
  }) {
    final rcServers = remoteConfigServers.isNotEmpty ? remoteConfigServers : _readRemoteConfigServers();
    final merged = mergeIceServers([
      ..._defaultStun,
      ...extraServers,
      ...rcServers,
    ]);
    return {
      'iceServers': merged,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceCandidatePoolSize': 4,
      'iceTransportPolicy': 'all',
    };
  }

  static List<Map<String, dynamic>> _readRemoteConfigServers() {
    try {
      final raw = FirebaseRemoteConfig.instance.getString('webrtc_ice_servers');
      if (raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (e) {
      debugPrint('[CallIceConfig] Remote Config ICE servers unavailable: $e');
      return const [];
    }
  }

  /// Merges and deduplicates ICE server entries by URL + credential signature.
  @visibleForTesting
  static List<Map<String, dynamic>> mergeIceServers(List<Map<String, dynamic>> raw) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in raw) {
      final urls = item['urls'];
      final urlKey = urls is List ? urls.join(',') : '$urls';
      if (urlKey.isEmpty) continue;
      final sig = '$urlKey|${item['username'] ?? ''}|${item['credential'] ?? ''}';
      if (seen.add(sig)) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }
}
