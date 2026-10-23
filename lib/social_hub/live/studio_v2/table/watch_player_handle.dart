// LIVE STUDIO v2 — the local watch-party player seam (workstream #5).
//
// The real player (package:video_player) lives in video_watch_player.dart and
// is loaded through a deferred import only when a viewer taps Join, so its
// code and platform view are built only for the active watch mode.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/table/watch_party_sync.dart';
import 'video_watch_player.dart' deferred as vwp;

abstract class WatchPlayerHandle {
  WatchPlayer get player;
  Widget buildView(BuildContext context);
  Future<void> dispose();
}

/// Creates a player for an HLS URL taken from a `live_watch_catalog` entry.
typedef WatchPlayerFactory = Future<WatchPlayerHandle> Function(String hlsUrl);

final watchPlayerFactoryProvider = Provider<WatchPlayerFactory>((ref) => (hlsUrl) async {
      await vwp.loadLibrary();
      return vwp.createVideoWatchPlayer(hlsUrl);
    });
