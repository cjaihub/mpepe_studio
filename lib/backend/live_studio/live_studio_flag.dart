import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../flags/feature_flag_service.dart';

/// Build-time override for testing: `--dart-define=LIVE_STUDIO_V2=true`.
const bool kLiveStudioV2Forced = bool.fromEnvironment('LIVE_STUDIO_V2');

/// Whether Live Studio v2 is on for the current user.
///
/// Uses the `live_studio_v2` Remote Config flag (`flag_live_studio_v2`, see
/// FeatureFlagService). The service was never initialized at app start, so
/// this provider initializes it on first use (idempotent).
final liveStudioV2EnabledProvider = FutureProvider<bool>((ref) async {
  if (kLiveStudioV2Forced) return true;
  final flags = ref.read(featureFlagServiceProvider);
  await flags.initialize();
  return flags.isEnabled(AppFeature.liveStudioV2);
});

/// `studioVersion` of a live stream doc (2 = Live Studio v2, else v1).
///
/// A snapshot listener rather than a one-time get: it shares the stream
/// doc listener the viewer gate already holds, so it resolves from cache
/// instead of adding a server round trip before the studio opens.
final liveStudioVersionProvider = StreamProvider.autoDispose.family<int, String>((ref, streamId) {
  return FirebaseFirestore.instance.collection('live_streams').doc(streamId).snapshots().map((snap) {
    final v = snap.data()?['studioVersion'];
    return v is num ? v.toInt() : 1;
  });
});
