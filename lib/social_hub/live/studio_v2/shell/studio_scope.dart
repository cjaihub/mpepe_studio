import 'package:flutter_riverpod/misc.dart' show Override;

import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../../../../backend/live_studio/settings/studio_settings_controller.dart';
import '../../../../backend/live_studio/social/studio_social_ports.dart';

/// Connects the Live Studio v2 workstreams to the session layer.
///
/// Social and settings read the LiveKit room and the authoritative
/// `StudioState` through small adapter providers so they could be built and
/// tested in isolation. These overrides point the adapters at the real session
/// providers. They are installed once, in the root `ProviderScope`
/// (lib/main.dart), so every studio screen shares one room and one session per
/// stream.
final List<Override> liveStudioV2Overrides = [
  studioSocialRoomPortProvider.overrideWith((ref, id) => ref.watch(studioRoomProvider(id))),
  studioSocialStateSourceProvider
      .overrideWith((ref, id) => ref.watch(studioSessionProvider(id).notifier).states),
  studioSettingsStateSourceProvider
      .overrideWith((ref, id) => ref.watch(studioSessionProvider(id).notifier).states),
];
