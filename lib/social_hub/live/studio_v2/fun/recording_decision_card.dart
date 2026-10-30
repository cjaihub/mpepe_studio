// LIVE STUDIO v2 — after the live: the host decides what happens to the
// 1080p recording (keep it in their library, share it, or delete it).

import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../shell/shell_widgets.dart';
import '../theme/live_studio_tokens.dart';

class RecordingDecisionCard extends ConsumerStatefulWidget {
  const RecordingDecisionCard({super.key, required this.streamId});
  final String streamId;

  @override
  ConsumerState<RecordingDecisionCard> createState() => _RecordingDecisionCardState();
}

class _RecordingDecisionCardState extends ConsumerState<RecordingDecisionCard> {
  LiveRecordingStatus? _s;
  bool _loaded = false;
  bool _busy = false;
  Timer? _poll;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    // The MP4 finalizes a few seconds after the live ends.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (++_tries > 80 || (_s != null && !(_s!.active || _s!.status == 'stopping'))) {
        _poll?.cancel();
        return;
      }
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await ref.read(studioBroadcastApiProvider).status(widget.streamId);
      if (mounted) setState(() {
        _s = s;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _decide(bool keep) async {
    setState(() => _busy = true);
    try {
      await ref.read(studioBroadcastApiProvider).decide(widget.streamId, keep: keep);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not update the recording.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final path = _s?.path;
    if (path == null) return;
    try {
      final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      await SharePlus.instance.share(ShareParams(uri: Uri.parse(url), subject: 'My Oneova live'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not open the recording.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (!_loaded || s == null || !s.record) return const SizedBox.shrink();
    final (icon, title, body) = switch ((s.status, s.decision)) {
      (_, 'kept') => (Icons.video_library_rounded, 'Saved to your library', 'Settings → Camera & Live → Live recordings.'),
      (_, 'discarded') => (Icons.delete_outline_rounded, 'Recording deleted', 'Nothing was kept.'),
      ('ready', _) => (
          Icons.movie_rounded,
          'Your 1080p recording is ready',
          s.durationMs == null ? 'Keep it or delete it.' : '${_mins(s.durationMs!)} · keep it or delete it.'
        ),
      ('failed', _) => (Icons.error_outline_rounded, 'Recording failed', s.error ?? 'The video could not be saved.'),
      _ => (Icons.hourglass_top_rounded, 'Finishing your recording…', 'This takes a few seconds.'),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LiveStudioWorld.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LiveStudioAccent.pinkA(0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: LiveStudioAccent.pink),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: LiveStudioType.s(15, FontWeight.w800, LiveStudioWorld.textHigh))),
          ]),
          const SizedBox(height: 4),
          Text(body, style: LiveStudioType.s(12.5, FontWeight.w500, LiveStudioWorld.textMedium)),
          if (s.ready && s.decision == null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: StudioPillButton(
                  label: 'Keep',
                  icon: Icons.download_done_rounded,
                  onTap: _busy ? null : () => _decide(true),
                  fill: LiveStudioAccent.blue,
                  textColor: LiveStudioAccent.white,
                  height: 44,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StudioPillButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  onTap: _busy ? null : () => _decide(false),
                  fill: LiveStudioWorld.surface3,
                  textColor: LiveStudioAccent.white,
                  height: 44,
                ),
              ),
            ]),
          ],
          if (s.decision == 'kept') ...[
            const SizedBox(height: 12),
            StudioPillButton(
              label: 'Share or download',
              icon: Icons.ios_share_rounded,
              onTap: _share,
              fill: LiveStudioAccent.blue,
              textColor: LiveStudioAccent.white,
              height: 44,
            ),
          ],
        ]),
      ),
    );
  }

  static String _mins(int ms) {
    final m = ms ~/ 60000, sec = (ms ~/ 1000) % 60;
    return '${m}m ${sec.toString().padLeft(2, '0')}s';
  }
}
