import 'package:flutter/widgets.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../theme/live_studio_tokens.dart';

/// Live video for a publisher at a rendered size (the media workstream
/// provides `StudioVideoView`). The size lets the SFU pick a simulcast layer.
typedef StudioVideoBuilder = Widget Function(String uid, Size renderSize);

/// Everything a screen needs about the person in it.
@immutable
class StageSeat {
  const StageSeat({
    required this.uid,
    required this.name,
    required this.accent,
    required this.role,
    required this.camOn,
    required this.speaking,
    required this.muted,
    required this.popped,
  });

  final String uid;
  final String name;
  final Color accent;
  final StudioRole role;
  final bool camOn;
  final bool speaking;
  final bool muted;
  final bool popped;

  factory StageSeat.of(
    String uid,
    StageMember? m, {
    required bool Function(String) isSpeaking,
    required bool Function(String) isMuted,
    required bool popped,
  }) =>
      StageSeat(
        uid: uid,
        name: m?.displayName ?? '',
        accent: studioHex(m?.accent ?? kAccentPalette[1], fallback: LiveStudioAccent.blue),
        role: m?.role ?? StudioRole.guest,
        camOn: m?.camOn ?? false,
        speaking: isSpeaking(uid),
        muted: isMuted(uid),
        popped: popped,
      );

  /// Role line under the ON STAGE name.
  String get roleLabel => switch (role) {
        StudioRole.host => 'Presenting',
        StudioRole.coHost => 'Co-host',
        StudioRole.guest => 'Guest',
        StudioRole.viewer => 'Viewer',
      };
}
