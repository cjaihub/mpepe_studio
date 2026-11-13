import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/backend/social/models/comment.dart';
import 'package:oneova/backend/social/services/comment_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../auth/widgets/auth_interaction_gate.dart';
import '../../shared/audio/cloud_dictation.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/audio/speech_hub.dart';
import '../../shared/theme/app_theme.dart';
import 'oneova_gif_picker_sheet.dart';
import 'reel_palette.dart';

enum _BarMode { idle, transcribing, recording }

/// The reel's "Add comment…" bar.
///
/// - Tap the mic: live transcription. Words appear in the bar as you speak;
///   tap send to post them as a text comment.
/// - Press and hold the mic: record a voice comment. Release to send, slide
///   left to cancel. It appears as a small playable card in the reel's stream.
class ReelCommentBar extends ConsumerStatefulWidget {
  final String contentId;
  final String contentAuthorId;

  /// Opens the full comments sheet (tap on the hint text).
  final VoidCallback onOpenComments;

  /// Opens the Oneova assistant (Ova).
  final VoidCallback onOpenAssistant;

  /// Quick emoji reactions shown inside the bar.
  final Widget reactions;

  const ReelCommentBar({
    super.key,
    required this.contentId,
    required this.contentAuthorId,
    required this.onOpenComments,
    required this.onOpenAssistant,
    required this.reactions,
  });

  @override
  ConsumerState<ReelCommentBar> createState() => _ReelCommentBarState();
}

class _ReelCommentBarState extends ConsumerState<ReelCommentBar> with SingleTickerProviderStateMixin {
  static const _maxVoice = Duration(seconds: 60);

  final SpeechHub _speech = SpeechHub.instance;
  MicLease? _micLease;
  CloudDictation? _cloud;
  bool _usingCloud = false;
  AudioRecorder? _recorder;
  _BarMode _mode = _BarMode.idle;
  String _transcript = '';
  bool _sending = false;

  DateTime? _recStart;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  bool _cancelArmed = false;

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _recTimer?.cancel();
    _pulse.dispose();
    unawaited(_speech.cancel(this));
    unawaited(_cloud?.dispose());
    unawaited(_micLease?.release());
    _micLease = null;
    try {
      _recorder?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _releaseMic() async {
    final lease = _micLease;
    _micLease = null;
    await lease?.release();
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        action: action,
      ),
    );
  }

  Future<bool> _ensureMic() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (!mounted) return false;
    _snack(
      status.isPermanentlyDenied
          ? 'Microphone is off for Oneova. Turn it on in Settings.'
          : 'Microphone permission is needed.',
      action: status.isPermanentlyDenied ? SnackBarAction(label: 'Settings', onPressed: openAppSettings) : null,
    );
    return false;
  }

  // ── Live transcription ────────────────────────────────────────────────

  Future<void> _toggleTranscribe() async {
    if (_mode == _BarMode.transcribing) {
      await _finishTranscribe(commitCloud: true);
      return;
    }
    if (_mode != _BarMode.idle) return;
    HapticFeedback.lightImpact();
    if (!await _ensureMic()) return;

    final got = await MicCoordinator.instance.acquire(
      MicUser.voiceTyping,
      onPreempted: () async {
        await _finishTranscribe(commitCloud: false, releaseLease: false);
        _micLease = null;
      },
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && _mode == _BarMode.transcribing && mounted) {
          unawaited(_finishTranscribe(commitCloud: true));
        }
      },
    );
    if (got is MicBusy) {
      if (mounted) _snack(got.message);
      return;
    }
    _micLease = got as MicLease;
    if (!mounted) {
      await _releaseMic();
      return;
    }

    _usingCloud = false;
    setState(() {
      _mode = _BarMode.transcribing;
      _transcript = '';
    });

    final ready = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onStatus: (s) {
        if (_usingCloud || !mounted || _mode != _BarMode.transcribing) return;
        if (s == 'done' || s == 'notListening' || s == 'preempted') {
          unawaited(_finishTranscribe(commitCloud: false));
        }
      },
      onError: (err) {
        if (_usingCloud || !mounted || _mode != _BarMode.transcribing) return;
        if (err.errorMsg == 'error_no_match' || err.errorMsg == 'error_speech_timeout') {
          unawaited(_finishTranscribe(commitCloud: false));
        } else {
          unawaited(_startCloudTranscribe());
        }
      },
      onResult: (r) {
        if (_usingCloud || !mounted) return;
        setState(() => _transcript = r.recognizedWords);
      },
    );
    if (!ready && mounted && _mode == _BarMode.transcribing) {
      await _startCloudTranscribe();
    }
  }

  Future<void> _startCloudTranscribe() async {
    if (_usingCloud || !mounted || _mode != _BarMode.transcribing) return;
    await _speech.cancel(this);
    _usingCloud = true;
    _cloud ??= CloudDictation();
    final ok = await _cloud!.start(
      autoStopOnSilence: true,
      onSilenceCommit: () => unawaited(_finishTranscribe(commitCloud: true)),
    );
    if (!ok) {
      _usingCloud = false;
      if (mounted) _snack('Voice typing is not available right now.');
      await _finishTranscribe(commitCloud: false);
    }
  }

  Future<void> _finishTranscribe({required bool commitCloud, bool releaseLease = true}) async {
    final wasCloud = _usingCloud;
    _usingCloud = false;
    await _speech.stop(this);
    if (wasCloud) {
      if (commitCloud) {
        try {
          final text = (await _cloud?.stopAndTranscribe() ?? '').trim();
          if (mounted && text.isNotEmpty) {
            setState(() => _transcript = text);
          }
        } catch (_) {}
      } else {
        await _cloud?.cancel();
      }
    }
    if (releaseLease) {
      await _releaseMic();
    }
    if (mounted && _mode == _BarMode.transcribing) {
      setState(() => _mode = _BarMode.idle);
    }
  }

  void _clearTranscript() {
    _usingCloud = false;
    unawaited(_speech.cancel(this));
    unawaited(_cloud?.cancel());
    unawaited(_releaseMic());
    setState(() {
      _transcript = '';
      _mode = _BarMode.idle;
    });
  }

  Future<void> _sendTranscript() async {
    if (_sending) return;
    if (_mode == _BarMode.transcribing) {
      await _finishTranscribe(commitCloud: true);
    }
    final text = _transcript.trim();
    if (text.isEmpty || _sending) return;
    await _post(Comment(
      id: '',
      postId: widget.contentId,
      authorId: FirebaseAuth.instance.currentUser?.uid ?? '',
      content: text,
      createdAt: DateTime.now(),
    ));
    if (mounted) {
      setState(() {
        _transcript = '';
        _mode = _BarMode.idle;
      });
    }
  }

  Future<void> _post(Comment c) async {
    setState(() => _sending = true);
    try {
      await ref.read(commentServiceProvider).addComment(
            c,
            isCreator: widget.contentAuthorId == c.authorId,
          );
      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) _snack('Could not post comment: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Voice comment (hold to record) ────────────────────────────────────

  Future<void> _startRecording() async {
    if (_mode != _BarMode.idle) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      AuthInteractionGate.requireAuth(context, actionTitle: 'send voice comments', onAuthenticated: () {});
      return;
    }
    if (!await _ensureMic()) return;
    final got = await MicCoordinator.instance.acquire(
      MicUser.voiceNote,
      onPreempted: () async {
        await _finishRecording(send: false, releaseLease: false);
        _micLease = null;
      },
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && _mode == _BarMode.recording && mounted) {
          unawaited(_finishRecording(send: false));
        }
      },
    );
    if (got is MicBusy) {
      if (mounted) _snack(got.message);
      return;
    }
    _micLease = got as MicLease;
    if (!mounted) {
      await _releaseMic();
      return;
    }
    _recorder ??= AudioRecorder();
    final path = '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder!.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000), path: path);
    } catch (_) {
      await _releaseMic();
      if (mounted) _snack('Could not start recording.');
      return;
    }
    HapticFeedback.mediumImpact();
    _recStart = DateTime.now();
    _recTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _recStart == null) return;
      final el = DateTime.now().difference(_recStart!);
      setState(() => _recElapsed = el);
      if (el >= _maxVoice) _finishRecording(send: true);
    });
    setState(() {
      _mode = _BarMode.recording;
      _recElapsed = Duration.zero;
      _cancelArmed = false;
    });
  }

  Future<void> _finishRecording({required bool send, bool releaseLease = true}) async {
    if (_mode != _BarMode.recording) {
      if (releaseLease) await _releaseMic();
      return;
    }
    _recTimer?.cancel();
    final elapsed = _recStart == null ? Duration.zero : DateTime.now().difference(_recStart!);
    _recStart = null;
    String? path;
    try {
      if (await _recorder?.isRecording() ?? false) {
        path = await _recorder?.stop();
      }
    } catch (e) {
      debugPrint('[ReelCommentBar] recorder stop error: $e');
    }
    if (releaseLease) {
      await _releaseMic();
    }
    if (mounted) setState(() => _mode = _BarMode.idle);
    if (path == null) return;
    final file = File(path);
    if (!send || elapsed < const Duration(seconds: 1)) {
      if (send && mounted) _snack('Hold a little longer to record a voice comment.');
      try {
        await file.delete();
      } catch (_) {}
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (mounted) setState(() => _sending = true);
    try {
      final ref0 = FirebaseStorage.instance
          .ref('voice_comments/${widget.contentId}/${uid}_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await ref0.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
      final url = await ref0.getDownloadURL();
      await _post(Comment(
        id: '',
        postId: widget.contentId,
        authorId: uid,
        content: url,
        type: CommentType.voice,
        voiceDurationMs: elapsed.inMilliseconds,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      if (mounted) _snack('Could not send voice comment: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _pickAndPostGif() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      AuthInteractionGate.requireAuth(context, actionTitle: 'post GIFs', onAuthenticated: _pickAndPostGif);
      return;
    }
    final gif = await OneovaGifPickerSheet.show(context);
    if (gif == null || !mounted) return;
    await _post(Comment(
      id: '',
      postId: widget.contentId,
      authorId: uid,
      content: '',
      type: CommentType.gif,
      gif: gif,
      createdAt: DateTime.now(),
    ));
  }

  // ── UI ────────────────────────────────────────────────────────────────

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _label(ReelPalette p) {
    switch (_mode) {
      case _BarMode.recording:
        return Row(
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.brandPink),
              ),
            ),
            const SizedBox(width: 7),
            Text(_fmt(_recElapsed),
                style: GoogleFonts.inter(color: p.fg, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _cancelArmed ? 'Release to cancel' : '‹ Slide to cancel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _cancelArmed ? AppColors.brandPink : p.fgSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      case _BarMode.transcribing:
        return Text(
          _transcript.isEmpty ? 'Listening…' : _transcript,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: _transcript.isEmpty ? p.fgSoft : p.fg,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        );
      case _BarMode.idle:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _transcript.isNotEmpty
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  widget.onOpenComments();
                },
          child: Text(
            _transcript.isNotEmpty ? _transcript : 'Add comment…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: _transcript.isNotEmpty ? p.fg : p.fgSoft,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ReelPalette.of(context);
    final recording = _mode == _BarMode.recording;
    final hasTranscript = _transcript.trim().isNotEmpty && _mode != _BarMode.recording;

    Widget circle(IconData icon, {Color? fill, Color? iconColor}) => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: (fill ?? AppColors.brandPink).withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(color: (fill ?? AppColors.brandPink).withValues(alpha: 0.6), width: 1.0),
          ),
          child: Icon(icon, color: iconColor ?? (p.dark ? Colors.white : AppColors.brandPink), size: 15),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(
          color: p.glassStrong,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: recording || _mode == _BarMode.transcribing ? AppColors.brandPink.withValues(alpha: 0.7) : p.glassBorder,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: _label(p)),
            if (_mode == _BarMode.idle && !hasTranscript) ...[
              widget.reactions,
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _pickAndPostGif,
                child: circle(Icons.gif_box_rounded, fill: AppColors.brandPink),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onOpenAssistant,
                child: circle(Icons.auto_awesome_rounded, fill: AppColors.brandBlue),
              ),
              const SizedBox(width: 4),
            ],
            if (hasTranscript || _mode == _BarMode.transcribing && _transcript.isNotEmpty) ...[
              GestureDetector(onTap: _clearTranscript, child: circle(Icons.close_rounded, fill: AppColors.brandBlue)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _sending ? null : _sendTranscript,
                child: circle(Icons.arrow_upward_rounded, fill: AppColors.brandPink),
              ),
              const SizedBox(width: 4),
            ],
            // Tap = live transcription, hold = voice comment.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AuthInteractionGate.requireAuth(
                context,
                actionTitle: 'comment on videos',
                onAuthenticated: _toggleTranscribe,
              ),
              onLongPressStart: (_) => _startRecording(),
              onLongPressMoveUpdate: (d) {
                if (!recording) return;
                final armed = d.localOffsetFromOrigin.dx < -60;
                if (armed != _cancelArmed) setState(() => _cancelArmed = armed);
              },
              onLongPressEnd: (_) => _finishRecording(send: !_cancelArmed),
              onLongPressCancel: () => _finishRecording(send: false),
              child: AnimatedScale(
                scale: recording ? 1.25 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: circle(
                  recording
                      ? Icons.mic_rounded
                      : _mode == _BarMode.transcribing
                          ? Icons.stop_rounded
                          : Icons.mic_none_rounded,
                  fill: AppColors.brandPink,
                  iconColor: recording ? Colors.white : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
