import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import '../../shared/theme/app_theme.dart';

/// Tiny playable voice comment: play/pause, waveform with progress, duration.
/// Only one card plays at a time.
class VoiceCommentMiniCard extends StatefulWidget {
  final String url;
  final int? durationMs;

  /// Stable string (comment id) that shapes the waveform so it doesn't flicker.
  final String seed;

  const VoiceCommentMiniCard({super.key, required this.url, required this.seed, this.durationMs});

  @override
  State<VoiceCommentMiniCard> createState() => _VoiceCommentMiniCardState();
}

class _VoiceCommentMiniCardState extends State<VoiceCommentMiniCard> {
  static _VoiceCommentMiniCardState? _active;

  Player? _player;
  final List<StreamSubscription> _subs = [];
  bool _playing = false;
  double _progress = 0;
  Duration _total = Duration.zero;

  late final List<double> _bars = _barsFor(widget.seed);

  static List<double> _barsFor(String seed) {
    var h = 17;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return List.generate(16, (i) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      return 0.25 + (h % 1000) / 1000 * 0.75;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.durationMs != null) _total = Duration(milliseconds: widget.durationMs!);
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        p.stop();
        p.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    if (_playing) {
      try {
        await _player?.pause();
      } catch (_) {}
      return;
    }
    if (_active != null && _active != this) {
      try {
        await _active!._player?.pause();
      } catch (_) {}
    }
    _active = this;
    if (_player == null) {
      final p = Player();
      _player = p;
      _subs.addAll([
        p.stream.playing.listen((v) {
          if (mounted) setState(() => _playing = v);
        }),
        p.stream.duration.listen((d) {
          if (mounted && d > Duration.zero) setState(() => _total = d);
        }),
        p.stream.position.listen((pos) {
          if (mounted && _total.inMilliseconds > 0) {
            setState(() => _progress = (pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0));
          }
        }),
        p.stream.completed.listen((done) {
          if (done && mounted) setState(() => _progress = 0);
        }),
        p.stream.error.listen((err) {
          debugPrint('[VoiceComment] player error: $err');
          if (mounted) setState(() => _playing = false);
        }),
      ]);
      try {
        await p.open(Media(widget.url), play: true);
      } catch (e) {
        debugPrint('[VoiceComment] open failed: $e');
        if (mounted) setState(() => _playing = false);
      }
    } else {
      try {
        if (_progress >= 0.99) await _player!.seek(Duration.zero);
        await _player!.play();
      } catch (e) {
        debugPrint('[VoiceComment] play error: $e');
        if (mounted) setState(() => _playing = false);
      }
    }
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.brandBlue),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 14, color: Colors.white),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _bars.length; i++)
                Container(
                  width: 2,
                  height: 4 + 12 * _bars[i],
                  margin: const EdgeInsets.symmetric(horizontal: 0.6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color: (i / _bars.length) < _progress
                        ? AppColors.brandPink
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _fmt(_total),
          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}
