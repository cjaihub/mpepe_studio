// LIVE STUDIO v2 — security models (security workstream).
//
// Wire mirrors of functions/src/liveStudio/security_logic.ts:
// incidents (`live_streams/{id}/studio_security`), advisories
// (`live_streams/{id}/studio_security_advisories`), the `security` data topic
// and the shared media key returned by lsStart / lsToken / lsMediaKey.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Names that are not (yet) in the integrator-owned contracts.
class StudioSecurityWire {
  StudioSecurityWire._();

  /// Data-message topic for advisories and key updates.
  static const String topic = 'security';

  static String incidents(String streamId) => 'live_streams/$streamId/studio_security';
  static String advisories(String streamId) => 'live_streams/$streamId/studio_security_advisories';

  // Callables owned by this workstream / requested from the integrator.
  static const String mediaKey = 'lsMediaKey';
  static const String setChatMode = 'lsSetChatMode';
  static const String setJoinRequests = 'lsSetJoinRequests';
}

enum StudioSeverity {
  info('info'),
  warn('warn'),
  critical('critical');

  const StudioSeverity(this.wire);
  final String wire;

  static StudioSeverity fromWire(Object? w) =>
      values.firstWhere((v) => v.wire == w, orElse: () => StudioSeverity.info);

  int get rank => index;
}

String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num ? v.toInt() : 0;

/// One detector incident.
@immutable
class StudioSecurityIncident {
  const StudioSecurityIncident({
    required this.id,
    required this.detector,
    required this.severity,
    required this.reason,
    required this.count,
    required this.atMs,
    this.uid,
  });

  final String id;
  final String detector;
  final StudioSeverity severity;
  final String reason;
  final int count;
  final int atMs;

  /// Offending account (null for stream-wide incidents).
  final String? uid;

  factory StudioSecurityIncident.fromJson(String id, Map<String, dynamic> j) => StudioSecurityIncident(
        id: id,
        detector: _s(j['detector']),
        severity: StudioSeverity.fromWire(j['severity']),
        reason: _s(j['reason']),
        count: _i(j['count']),
        atMs: _i(j['atMs']),
        uid: j['uid'] is String && (j['uid'] as String).isNotEmpty ? j['uid'] as String : null,
      );
}

/// The fixed action allow-list (server validates the model against it too).
enum StudioAdvisoryActionType {
  muteUser('mute_user', 'Mute chat', true),
  removeFromStage('remove_from_stage', 'Remove from stage', true),
  blockUser('block_user', 'Block', true),
  slowMode('slow_mode', 'Slow mode', false),
  followersOnly('followers_only', 'Followers-only chat', false),
  pauseJoinRequests('pause_join_requests', 'Pause join requests', false),
  endLive('end_live', 'End live', false);

  const StudioAdvisoryActionType(this.wire, this.label, this.targetsUser);
  final String wire;
  final String label;
  final bool targetsUser;

  static StudioAdvisoryActionType? fromWire(Object? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }
}

@immutable
class StudioAdvisoryAction {
  const StudioAdvisoryAction(this.type, {this.targetUid, this.targetName = ''});
  final StudioAdvisoryActionType type;
  final String? targetUid;
  final String targetName;

  /// Stable key for in-flight tracking.
  String get key => '${type.wire}:${targetUid ?? ''}';

  /// Button label, e.g. "Block Ana".
  String get label {
    if (!type.targetsUser) return type.label;
    return targetName.isEmpty ? type.label : '${type.label} $targetName';
  }

  /// Null when the action is not allow-listed or misses its target.
  static StudioAdvisoryAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = StudioAdvisoryActionType.fromWire(raw['type']);
    if (type == null) return null;
    final uid = raw['targetUid'] is String ? raw['targetUid'] as String : null;
    if (type.targetsUser && (uid == null || uid.isEmpty)) return null;
    return StudioAdvisoryAction(type, targetUid: type.targetsUser ? uid : null, targetName: _s(raw['targetName']));
  }
}

/// A live-health advisory for the host / co-hosts.
@immutable
class StudioAdvisory {
  const StudioAdvisory({
    required this.id,
    required this.atMs,
    required this.severity,
    required this.assessment,
    required this.actions,
    required this.fromAi,
  });

  final String id;
  final int atMs;
  final StudioSeverity severity;
  final String assessment;
  final List<StudioAdvisoryAction> actions;
  final bool fromAi;

  factory StudioAdvisory.fromJson(Map<String, dynamic> j, {String? id}) {
    final raw = j['actions'];
    final actions = <StudioAdvisoryAction>[
      if (raw is List)
        for (final a in raw) ?StudioAdvisoryAction.fromJson(a),
    ];
    return StudioAdvisory(
      id: id ?? _s(j['id']),
      atMs: _i(j['atMs']),
      severity: StudioSeverity.fromWire(j['severity']),
      assessment: _s(j['assessment']),
      actions: actions.take(3).toList(growable: false),
      fromAi: j['source'] == 'ai',
    );
  }
}

/// The stream's shared media key (32 bytes) and its ring index.
@immutable
class StudioMediaKey {
  const StudioMediaKey(this.bytes, this.keyIndex);
  final Uint8List bytes;
  final int keyIndex;

  static const int length = 32;

  /// Parses `{key: base64, keyIndex}`; null when absent or malformed.
  static StudioMediaKey? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final idx = raw['keyIndex'];
    if (key is! String || idx is! num) return null;
    try {
      final bytes = base64.decode(key);
      if (bytes.length != length || idx < 0 || idx > 255) return null;
      return StudioMediaKey(Uint8List.fromList(bytes), idx.toInt());
    } on FormatException {
      return null;
    }
  }
}

/// A decoded `security` topic message.
sealed class StudioSecurityPacket {
  const StudioSecurityPacket();

  /// Null for packets that are not ours, or malformed.
  static StudioSecurityPacket? decode(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'key.update':
        final idx = j['keyIndex'];
        return idx is num ? KeyUpdatePacket(idx.toInt()) : null;
      case 'security.advisory':
        final a = j['advisory'];
        return a is Map ? AdvisoryPacket(StudioAdvisory.fromJson(Map<String, dynamic>.from(a))) : null;
      default:
        return null;
    }
  }

  /// Decodes raw packet bytes (server-sent only; see studio_packet_decoder).
  static StudioSecurityPacket? decodeBytes(List<int> data) {
    try {
      final j = jsonDecode(utf8.decode(data));
      return j is Map ? decode(Map<String, dynamic>.from(j)) : null;
    } on FormatException {
      return null;
    }
  }
}

class KeyUpdatePacket extends StudioSecurityPacket {
  const KeyUpdatePacket(this.keyIndex);
  final int keyIndex;
}

class AdvisoryPacket extends StudioSecurityPacket {
  const AdvisoryPacket(this.advisory);
  final StudioAdvisory advisory;
}
