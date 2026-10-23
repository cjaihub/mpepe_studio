import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// ICE server list for WebRTC.
///
/// STUN alone connects most Wi-Fi calls but fails on many mobile carriers
/// (symmetric NAT). Add a TURN server in Firebase Remote Config under the key
/// `webrtc_ice_servers` as a JSON array, for example:
///
/// `[{"urls":["turn:turn.example.com:3478"],"username":"u","credential":"p"}]`
///
/// The value is merged with the default STUN servers, so nothing breaks if the
/// key is missing.
class CallIceConfig {
  static const List<Map<String, dynamic>> _defaultStun = [
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
    },
  ];

  static Map<String, dynamic> configuration() {
    final servers = <Map<String, dynamic>>[..._defaultStun];
    try {
      final raw = FirebaseRemoteConfig.instance.getString('webrtc_ice_servers');
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          servers.addAll(decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
        }
      }
    } catch (e) {
      debugPrint('[CallIceConfig] Remote Config ICE servers unavailable: $e');
    }
    return {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    };
  }
}
