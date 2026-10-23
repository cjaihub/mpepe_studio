// LIVE STUDIO v2 — share (workstream #2).
//
// Calls `lsShare` (counts the share and posts the "shared this live" line),
// then opens the system share sheet with the returned deep link. If the
// callable fails, the canonical link is still shared, just not counted.

import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';

typedef StudioShareLauncher = Future<ShareResult> Function(ShareParams params);

class StudioShareService {
  StudioShareService(this._port, {StudioShareLauncher? launcher})
      : _launch = launcher ?? SharePlus.instance.share;

  final StudioCallPort _port;
  final StudioShareLauncher _launch;

  /// Returns the shared URL. [origin] anchors the sheet on iPad.
  Future<String> share(String streamId, {String? title, Rect? origin}) async {
    var url = studioShareUrl(streamId);
    try {
      final res = await _port.call(StudioCallables.share, {'streamId': streamId});
      final u = res['url'];
      if (u is String && u.startsWith('https://')) url = u;
    } catch (_) {
      // Fall back to the canonical link; sharing should never be blocked.
    }
    final t = (title ?? '').trim();
    await _launch(ShareParams(
      text: t.isEmpty ? 'Watch this live on Oneova: $url' : '$t — live on Oneova: $url',
      subject: t.isEmpty ? 'Live on Oneova' : t,
      sharePositionOrigin: origin,
    ));
    return url;
  }
}

final studioShareServiceProvider =
    Provider<StudioShareService>((ref) => StudioShareService(ref.watch(studioCallPortProvider)));
