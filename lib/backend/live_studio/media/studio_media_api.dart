// LIVE STUDIO v2 — typed wrappers over the media callables (workstream #1).
//
// lsStart · lsToken · lsEnd · lsStateFull · lsSetOwnMedia. lsTime is used by
// the session clock (session/studio_clock.dart).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../security/studio_security_models.dart';

/// Where and how to join the LiveKit room.
class StudioJoinCredentials {
  const StudioJoinCredentials({required this.url, required this.token, required this.role, this.e2ee});
  final String url;
  final String token;
  final StudioRole role;

  /// Shared media key for frame encryption, or null when the server has
  /// E2EE off (`LIVE_STUDIO_E2EE=false`) or sent no valid key.
  final StudioMediaKey? e2ee;

  factory StudioJoinCredentials.fromJson(Map<String, dynamic> j) => StudioJoinCredentials(
        url: j['url'] is String ? j['url'] as String : '',
        token: j['token'] is String ? j['token'] as String : '',
        role: StudioRole.fromWire(j['role']),
        e2ee: StudioMediaKey.fromJson(j['e2ee']),
      );
}

/// Result of [StudioMediaApi.start].
class StudioStartResult {
  const StudioStartResult({required this.streamId, required this.credentials});
  final String streamId;
  final StudioJoinCredentials credentials;
}

class StudioMediaApi {
  const StudioMediaApi(this._call);
  final StudioCallPort _call;

  /// Starts a v2 live as host. [settings] is an optional partial override of
  /// the host's saved settings. [gaming] opens a Game Live (screen share in
  /// the center, camera PiP) with an optional [gameTitle] (≤ 60 chars).
  ///
  /// Setup-wizard extras (all optional): [category], [coverUrl] (https),
  /// [audienceMode] (`public` | `followers` | `private`) and
  /// [allowGuestRequests].
  Future<StudioStartResult> start(String title,
      {Map<String, dynamic>? settings,
      bool gaming = false,
      String? gameTitle,
      String? category,
      String? coverUrl,
      String? audienceMode,
      bool? allowGuestRequests}) async {
    final game = gameTitle?.trim();
    final r = await _call.call(StudioCallables.start, {
      'title': title,
      'settings': ?settings,
      if (gaming) 'kind': 'gaming',
      if (gaming && game != null && game.isNotEmpty) 'gameTitle': game,
      'category': ?category,
      'coverUrl': ?coverUrl,
      'audienceMode': ?audienceMode,
      'allowGuestRequests': ?allowGuestRequests,
    });
    return StudioStartResult(
      streamId: r['streamId'] is String ? r['streamId'] as String : '',
      credentials: StudioJoinCredentials.fromJson({...r, 'role': r['role'] ?? 'host'}),
    );
  }

  Future<StudioJoinCredentials> token(String streamId) async =>
      StudioJoinCredentials.fromJson(await _call.call(StudioCallables.token, {'streamId': streamId}));

  Future<void> end(String streamId) => _call.call(StudioCallables.end, {'streamId': streamId});

  /// Host keep-alive (lsHeartbeat). Returns true when the server already
  /// closed the live (e.g. after a long network loss).
  Future<bool> heartbeat(String streamId) async {
    final r = await _call.call(StudioCallables.heartbeat, {'streamId': streamId});
    return r['ended'] == true;
  }

  /// Authoritative state, or null when the response has none.
  Future<StudioState?> stateFull(String streamId) async {
    final r = await _call.call(StudioCallables.stateFull, {'streamId': streamId});
    final s = r['state'];
    return s is Map ? StudioState.fromJson(Map<String, dynamic>.from(s)) : null;
  }

  /// Current media key after a `key.update` (lsMediaKey); null when E2EE is off.
  Future<StudioMediaKey?> mediaKey(String streamId) async {
    final r = await _call.call(StudioSecurityWire.mediaKey, {'streamId': streamId});
    return r['enabled'] == true ? StudioMediaKey.fromJson(r) : null;
  }

  Future<void> setOwnMedia(String streamId, {required bool micOn, required bool camOn}) =>
      _call.call(StudioCallables.setOwnMedia, {'streamId': streamId, 'micOn': micOn, 'camOn': camOn});
}

/// Join credentials returned by lsStart, kept until the studio's room
/// connects so the host joins without an extra lsToken round trip.
final studioStartCredentialsProvider = Provider<Map<String, StudioJoinCredentials>>((ref) => {});

/// Host's mic / camera choice from the setup wizard, by stream id.
final studioStartMediaProvider = Provider<Map<String, ({bool mic, bool camera})>>((ref) => {});

final studioMediaApiProvider =
    Provider<StudioMediaApi>((ref) => StudioMediaApi(ref.watch(studioCallPortProvider)));
