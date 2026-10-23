import 'dart:io';

import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/geometry/geometry.dart';

/// Test-only fakes: the prototype cast (Host, Guest 01–06 with the prototype
/// accents; 02/04/06 muted, cameras off so avatars render).
final StudioGeometry kTestGeometry =
    StudioGeometry.parse(File('assets/live_studio/studio-geometry.json').readAsStringSync());

const List<String> kWallUids = ['g1', 'g2', 'g3', 'g4', 'g5', 'g6'];

Map<String, StageMember> fakeMembers({bool camerasOn = false}) => {
      'host': StageMember(
          uid: 'host', displayName: 'Host', accent: kAccentPalette[0], role: StudioRole.host, camOn: camerasOn),
      for (var i = 0; i < 6; i++)
        kWallUids[i]: StageMember(
          uid: kWallUids[i],
          displayName: 'Guest 0${i + 1}',
          accent: kAccentPalette[i + 1],
          role: StudioRole.guest,
          micOn: i.isEven, // Guest 02, 04, 06 muted
          camOn: camerasOn,
          joinedAtMs: i,
        ),
    };

StudioState fakeState(StudioSettings settings, {StageLayout? stage}) => StudioState(
      streamId: 'test',
      hostId: 'host',
      title: 'Single Searching',
      status: StudioStatus.live,
      settings: settings,
      stage: stage ?? const StageLayout(centerUid: 'host', wall: kWallUids),
    );

/// Prototype: eq bars whenever unmuted.
bool Function(String) speakingFrom(Map<String, StageMember> m) => (uid) => m[uid]?.micOn ?? false;
