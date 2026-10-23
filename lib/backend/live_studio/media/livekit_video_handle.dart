// LIVE STUDIO v2 — LiveKit-backed [StudioVideoHandle].
//
// One handle per (publisher, source). It is a [ChangeNotifier]: it notifies
// when the publication is bound/unbound, muted, subscribed or suppressed by
// the audio-only fallback, so [StudioVideoView] rebuilds by itself.
//
// Render size → subscription: every view that shows this handle reports its
// pixel size; the largest wins. All views 0×0 (or none) → the remote track is
// disabled (paused at the SFU). Wall tiles report small sizes and get the low
// simulcast layer; center / pop-out report large sizes and get the high one.

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../contracts/studio_ports.dart';
import 'publish_profile.dart';

class LiveKitVideoHandle extends ChangeNotifier implements StudioVideoHandle {
  LiveKitVideoHandle(this.uid, {this.isTableScreen = false});

  @override
  final String uid;
  final bool isTableScreen;

  static const Object _portKey = Object();

  TrackPublication? _pub;
  bool _suppressed = false;
  bool _disposed = false;
  final Map<Object, ({double w, double h})> _views = {};
  StudioSubscriptionPlan? _applied;

  TrackPublication? get publication => _pub;

  /// The video track to render, if any.
  VideoTrack? get track {
    final t = _pub?.track;
    return t is VideoTrack ? t : null;
  }

  bool get isLocal => _pub is LocalTrackPublication;

  /// True when there is a live, unmuted, not-suppressed video track.
  @override
  bool get hasVideo => !_suppressed && track != null && !(_pub?.muted ?? true);

  /// The plan currently requested from the SFU (null = none sent yet).
  StudioSubscriptionPlan? get appliedPlan => _applied;

  /// Effective plan: the largest reported view.
  StudioSubscriptionPlan get plan {
    var best = StudioSubscriptionPlan.paused;
    for (final v in _views.values) {
      final p = StudioSubscriptionPlan.forSize(v.w, v.h);
      if (p.enabled && p.width * p.height > best.width * best.height) best = p;
    }
    return best;
  }

  @override
  void setRenderSize(double width, double height) => reportView(_portKey, width, height);

  /// A view ([key]) is drawn at [width]×[height] physical pixels.
  void reportView(Object key, double width, double height) {
    _views[key] = (w: width, h: height);
    _apply();
  }

  void removeView(Object key) {
    if (_views.remove(key) != null) _apply();
  }

  /// (Re)binds the current publication (null = unpublished).
  void bind(TrackPublication? pub) {
    if (!identical(pub, _pub)) {
      _pub = pub;
      _applied = null;
    }
    _apply();
    _notify();
  }

  /// Audio-only fallback hides video without dropping the binding.
  void setSuppressed(bool suppressed) {
    if (suppressed == _suppressed) return;
    _suppressed = suppressed;
    _notify();
  }

  /// Something about the track changed (mute, subscription, stream state).
  /// Re-sends the plan: manual settings are ignored by LiveKit until the
  /// publication is subscribed.
  void refresh() {
    _applied = null;
    _apply();
    _notify();
  }

  void _apply() {
    final pub = _pub;
    if (pub is! RemoteTrackPublication || _suppressed) return;
    final p = plan;
    if (p == _applied) return;
    _applied = p;
    if (!p.enabled) {
      pub.disable();
    } else {
      pub.enable();
      pub.setVideoDimensions(VideoDimensions(p.width, p.height));
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
