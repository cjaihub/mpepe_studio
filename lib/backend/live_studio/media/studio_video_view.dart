// LIVE STUDIO v2 — render a [StudioVideoHandle] (workstream #1).
//
// The only widget the media workstream ships. It:
// - reports its pixel size to the handle (drives the simulcast layer:
//   wall tile → low, center / pop-out → high);
// - reports 0×0 when [visible] is false or on dispose (pauses the track);
// - rebuilds when the handle's track appears, mutes or is suppressed;
// - shows [placeholder] (e.g. the avatar fallback) when there is no video.

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

import '../contracts/studio_ports.dart';
import 'livekit_video_handle.dart';

class StudioVideoView extends StatefulWidget {
  const StudioVideoView(
    this.handle, {
    super.key,
    this.fit = BoxFit.cover,
    this.visible = true,
    this.mirrorLocal = true,
    this.placeholder,
  });

  final StudioVideoHandle? handle;

  /// [BoxFit.cover] (tiles) or [BoxFit.contain] (screen share / full screen).
  final BoxFit fit;

  /// False while the view is off screen or covered: the track is paused.
  final bool visible;

  /// Mirror the local camera preview.
  final bool mirrorLocal;

  /// Shown when there is no video (no track, muted, audio-only).
  final Widget? placeholder;

  @override
  State<StudioVideoView> createState() => _StudioVideoViewState();
}

class _StudioVideoViewState extends State<StudioVideoView> {
  final Object _viewKey = Object();
  Size _lastPx = Size.zero;

  LiveKitVideoHandle? get _lk => widget.handle is LiveKitVideoHandle ? widget.handle as LiveKitVideoHandle : null;

  @override
  void initState() {
    super.initState();
    _lk?.addListener(_onHandle);
  }

  @override
  void didUpdateWidget(StudioVideoView old) {
    super.didUpdateWidget(old);
    if (!identical(old.handle, widget.handle)) {
      final prev = old.handle;
      if (prev is LiveKitVideoHandle) {
        prev.removeListener(_onHandle);
        prev.removeView(_viewKey);
      } else {
        prev?.setRenderSize(0, 0);
      }
      _lk?.addListener(_onHandle);
      _lastPx = Size.zero;
    }
    if (!widget.visible) _report(Size.zero);
  }

  @override
  void dispose() {
    final h = widget.handle;
    if (h is LiveKitVideoHandle) {
      h.removeListener(_onHandle);
      h.removeView(_viewKey);
    } else {
      h?.setRenderSize(0, 0);
    }
    super.dispose();
  }

  void _onHandle() {
    if (mounted) setState(() {});
  }

  void _report(Size px) {
    if (px == _lastPx) return;
    _lastPx = px;
    final h = widget.handle;
    if (h is LiveKitVideoHandle) {
      h.reportView(_viewKey, px.width, px.height);
    } else {
      h?.setRenderSize(px.width, px.height);
    }
  }

  VideoViewFit get _fit => widget.fit == BoxFit.contain ? VideoViewFit.contain : VideoViewFit.cover;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(builder: (context, c) {
      final px = widget.visible && c.hasBoundedWidth && c.hasBoundedHeight
          ? Size(c.maxWidth * dpr, c.maxHeight * dpr)
          : Size.zero;
      // Reporting is a side effect on the SFU subscription, not on this tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _report(px);
      });
      final lk = _lk;
      final track = lk?.track;
      if (lk == null || track == null || !lk.hasVideo || !widget.visible) {
        return widget.placeholder ?? const SizedBox.expand();
      }
      return VideoTrackRenderer(
        track,
        key: ValueKey(track.sid ?? track.mediaStreamTrack.id),
        fit: _fit,
        mirrorMode: lk.isLocal && widget.mirrorLocal && !lk.isTableScreen
            ? VideoViewMirrorMode.mirror
            : VideoViewMirrorMode.off,
      );
    });
  }
}
