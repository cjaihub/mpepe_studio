import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';

/// What a finished recording produced.
class VideoNoteResult {
  final File file;
  final Duration duration;
  const VideoNoteResult(this.file, this.duration);
}

/// One hold-to-record session (video message or camera GIF), shown as a
/// full-screen overlay with a round live preview and a progress ring.
///
/// Video message flow (WhatsApp / Telegram style), driven by the composer's
/// long-press: [VideoNoteSession.start] on press, [drag] while the finger
/// moves (slide left to cancel, slide up to lock), [release] on lift.
/// GIF flow: the overlay has its own hold-to-record button.
class VideoNoteSession {
  final bool gifMode;
  final Duration maxDuration;
  final void Function(VideoNoteResult result) onDone;
  final VoidCallback? onCancelled;

  final _state = _RecorderState();
  OverlayEntry? _entry;
  bool _closed = false;

  VideoNoteSession._(this.gifMode, this.maxDuration, this.onDone, this.onCancelled);

  /// Opens the overlay. In video-note mode recording starts as soon as the
  /// camera is ready (the user is already holding the button).
  static VideoNoteSession start(
    BuildContext context, {
    bool gifMode = false,
    required void Function(VideoNoteResult result) onDone,
    VoidCallback? onCancelled,
  }) {
    final s = VideoNoteSession._(
      gifMode,
      gifMode ? const Duration(seconds: 6) : const Duration(seconds: 60),
      onDone,
      onCancelled,
    );
    s._entry = OverlayEntry(builder: (_) => _RecorderOverlay(session: s));
    Overlay.of(context, rootOverlay: true).insert(s._entry!);
    s._init();
    return s;
  }

  bool get isLocked => _state.locked;

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('No camera found');
      _state.cameras = cams;
      final front = cams.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _state.camIndex = front >= 0 ? front : 0;
      await _openCamera();
      if (_closed) return;
      if (!gifMode && !_state.releasedEarly) await _startRecording();
      if (!gifMode && _state.releasedEarly) {
        // Finger lifted before the camera was ready: treat as a tap.
        await cancel();
      }
    } catch (e) {
      _state.error = e is CameraException
          ? (e.code.contains('Access') ? 'Allow camera${gifMode ? '' : ' and microphone'} access to record.' : 'Camera unavailable.')
          : 'Camera unavailable.';
      _state.notify();
    }
  }

  Future<void> _openCamera() async {
    final old = _state.cam;
    _state.cam = null;
    _state.notify();
    await old?.dispose();
    final c = CameraController(
      _state.cameras[_state.camIndex],
      ResolutionPreset.medium,
      enableAudio: !gifMode,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await c.initialize();
    if (_closed) {
      await c.dispose();
      return;
    }
    _state.cam = c;
    _state.notify();
  }

  Future<void> _startRecording() async {
    final c = _state.cam;
    if (c == null || c.value.isRecordingVideo || _closed) return;
    try {
      await c.prepareForVideoRecording();
      await c.startVideoRecording();
    } catch (e) {
      _state.error = 'Could not start recording.';
      _state.notify();
      return;
    }
    HapticFeedback.mediumImpact();
    _state.recording = true;
    _state.startedAt = DateTime.now();
    _state.ticker?.cancel();
    _state.ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _state.notify();
      if (_state.elapsed >= maxDuration) finish();
    });
    _state.notify();
  }

  Future<void> switchCamera() async {
    if (_state.cameras.length < 2 || _state.recording) return;
    HapticFeedback.selectionClick();
    _state.camIndex = (_state.camIndex + 1) % _state.cameras.length;
    try {
      await _openCamera();
    } catch (_) {}
  }

  /// Finger moved while holding the composer button.
  void drag(Offset fromStart) {
    if (_state.locked) return;
    _state.slide = fromStart;
    if (fromStart.dx < -110) {
      cancel();
      return;
    }
    if (fromStart.dy < -90) {
      HapticFeedback.heavyImpact();
      _state.locked = true;
    }
    _state.notify();
  }

  /// Finger lifted. Sends unless the recording was locked.
  Future<void> release() async {
    if (_closed) return;
    if (_state.locked) return;
    if (!_state.recording) {
      _state.releasedEarly = true;
      if (_state.cam != null || _state.error != null) await cancel();
      return;
    }
    await finish();
  }

  /// Stop and deliver the clip.
  Future<void> finish() async {
    if (_closed) return;
    final c = _state.cam;
    final elapsed = _state.elapsed;
    _state.ticker?.cancel();
    if (c == null || !c.value.isRecordingVideo) {
      await cancel();
      return;
    }
    XFile? file;
    try {
      file = await c.stopVideoRecording();
    } catch (_) {}
    _state.recording = false;
    await _close();
    if (file == null || elapsed < const Duration(milliseconds: 700)) {
      onCancelled?.call();
      return;
    }
    HapticFeedback.lightImpact();
    onDone(VideoNoteResult(File(file.path), elapsed));
  }

  Future<void> cancel() async {
    if (_closed) return;
    _state.ticker?.cancel();
    final c = _state.cam;
    if (c != null && c.value.isRecordingVideo) {
      try {
        final f = await c.stopVideoRecording();
        File(f.path).delete().catchError((_) => File(f.path));
      } catch (_) {}
    }
    HapticFeedback.selectionClick();
    await _close();
    onCancelled?.call();
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _entry?.remove();
    _entry = null;
    final c = _state.cam;
    _state.cam = null;
    await c?.dispose();
    _state.dispose();
  }
}

class _RecorderState extends ChangeNotifier {
  List<CameraDescription> cameras = const [];
  int camIndex = 0;
  CameraController? cam;
  bool recording = false;
  bool locked = false;
  bool releasedEarly = false;
  Offset slide = Offset.zero;
  DateTime? startedAt;
  Timer? ticker;
  String? error;
  bool _disposed = false;

  Duration get elapsed => startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  void notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ticker?.cancel();
    super.dispose();
  }
}

class _RecorderOverlay extends StatelessWidget {
  final VideoNoteSession session;
  const _RecorderOverlay({required this.session});

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final diameter = math.min(size.width * 0.78, 320.0);
    return Material(
      color: AppColors.brandBlack.withValues(alpha: 0.82),
      child: ListenableBuilder(
        listenable: session._state,
        builder: (context, _) {
          final st = session._state;
          final cam = st.cam;
          final progress = (st.elapsed.inMilliseconds / session.maxDuration.inMilliseconds).clamp(0.0, 1.0);
          final cancelHint = (-st.slide.dx / 110).clamp(0.0, 1.0);
          return SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.brandWhite),
                      onPressed: session.cancel,
                    ),
                    const Spacer(),
                    Text(
                      session.gifMode ? 'Make a GIF' : 'Video message',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brandWhite),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.cameraswitch_rounded, color: AppColors.brandWhite),
                      onPressed: st.recording ? null : session.switchCamera,
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: diameter + 14,
                  height: diameter + 14,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: diameter + 14,
                        height: diameter + 14,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          color: AppColors.brandPink,
                          backgroundColor: AppColors.brandWhite.withValues(alpha: 0.15),
                        ),
                      ),
                      ClipOval(
                        child: SizedBox(
                          width: diameter,
                          height: diameter,
                          child: st.error != null
                              ? ColoredBox(
                                  color: AppColors.darkSurface,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(st.error!,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.brandWhite)),
                                    ),
                                  ),
                                )
                              : cam == null || !cam.value.isInitialized
                                  ? const ColoredBox(
                                      color: AppColors.darkSurface,
                                      child: Center(
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                                      ),
                                    )
                                  : FittedBox(
                                      fit: BoxFit.cover,
                                      clipBehavior: Clip.hardEdge,
                                      child: SizedBox(
                                        width: cam.value.previewSize?.height ?? diameter,
                                        height: cam.value.previewSize?.width ?? diameter,
                                        child: CameraPreview(cam),
                                      ),
                                    ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (st.recording)
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      st.recording ? _fmt(st.elapsed) : (session.gifMode ? 'Hold to record' : 'Starting…'),
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.brandWhite),
                    ),
                    Text(
                      '  / ${_fmt(session.maxDuration)}',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.brandWhite.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const Spacer(),
                if (session.gifMode)
                  _GifShutter(session: session)
                else if (st.locked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _roundButton(Icons.delete_outline_rounded, AppColors.darkSurfaceHighlight, session.cancel),
                        _roundButton(Icons.send_rounded, AppColors.brandBlue, session.finish, big: true),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Column(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            color: AppColors.brandWhite.withValues(alpha: 0.75 - cancelHint * 0.5), size: 20),
                        Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.brandWhite.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: 1 - cancelHint * 0.6,
                          child: Text(
                            '‹  Slide to cancel   ·   Release to send',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: Color.lerp(AppColors.brandWhite, AppColors.brandPink, cancelHint),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _roundButton(IconData icon, Color fill, VoidCallback onTap, {bool big = false}) {
    final s = big ? 62.0 : 52.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle, boxShadow: AppShadows.md),
        child: Icon(icon, color: AppColors.brandWhite, size: big ? 26 : 22),
      ),
    );
  }
}

/// Hold-to-record shutter for camera GIFs.
class _GifShutter extends StatelessWidget {
  final VideoNoteSession session;
  const _GifShutter({required this.session});

  @override
  Widget build(BuildContext context) {
    final rec = session._state.recording;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: GestureDetector(
        onLongPressStart: (_) => session._startRecording(),
        onLongPressEnd: (_) => session.finish(),
        onTap: () => HapticFeedback.selectionClick(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: rec ? 84 : 72,
          height: rec ? 84 : 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandWhite, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: Container(
            decoration: BoxDecoration(
              color: rec ? AppColors.brandPink : AppColors.brandWhite,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.gif_rounded, color: rec ? AppColors.brandWhite : AppColors.brandBlue, size: 30),
          ),
        ),
      ),
    );
  }
}
