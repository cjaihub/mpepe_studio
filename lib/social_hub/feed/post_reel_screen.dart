import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../backend/social/models/content.dart';
import '../../backend/social/services/reels/reel_upload_service.dart';
import '../../shared/theme/app_theme.dart';

/// Pick or record a video, add a caption, post it as a reel.
///
/// After the file upload finishes the creator can leave: the server keeps
/// processing, and this screen shows when the reel is live if they stay.
class PostReelScreen extends ConsumerStatefulWidget {
  const PostReelScreen({super.key});

  @override
  ConsumerState<PostReelScreen> createState() => _PostReelScreenState();
}

enum _Stage { choosing, uploading, processing, live, failed }

class _PostReelScreenState extends ConsumerState<PostReelScreen> {
  // Matches storage.rules (isUnder200MB); the worker accepts up to 10 min.
  static const int _maxBytes = 200 * 1024 * 1024;
  static const Duration _maxDuration = Duration(minutes: 3);

  final _caption = TextEditingController();
  File? _video;
  int _videoBytes = 0;
  _Stage _stage = _Stage.choosing;
  double _progress = 0;
  String? _error;
  StreamSubscription<ContentStatus>? _statusSub;

  @override
  void dispose() {
    _caption.dispose();
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(source: source, maxDuration: _maxDuration);
    if (picked == null) return;
    final file = File(picked.path);
    final bytes = await file.length();
    setState(() {
      _video = file;
      _videoBytes = bytes;
      _error = bytes >= _maxBytes ? 'This video is over 200 MB. Please pick a shorter one.' : null;
    });
  }

  /// Hashtags are taken from the caption ("#music #live").
  List<String> _hashtags(String text) => RegExp(r'#(\w{1,40})')
      .allMatches(text)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet()
      .take(20)
      .toList();

  Future<void> _post() async {
    final video = _video;
    if (video == null || _videoBytes >= _maxBytes) return;
    final caption = _caption.text.trim();
    setState(() {
      _stage = _Stage.uploading;
      _progress = 0;
      _error = null;
    });
    try {
      String? contentId;
      await for (final p in ref.read(reelUploadServiceProvider).upload(
            video,
            description: caption,
            hashtags: _hashtags(caption),
          )) {
        contentId = p.contentId;
        if (!mounted) return;
        setState(() {
          _progress = p.fraction;
          if (p.status == ContentStatus.processing) _stage = _Stage.processing;
        });
      }
      if (contentId == null || !mounted) return;
      _statusSub = ref.read(reelUploadServiceProvider).watch(contentId).listen((status) {
        if (!mounted) return;
        if (status == ContentStatus.ready) setState(() => _stage = _Stage.live);
        if (status == ContentStatus.failed) {
          setState(() {
            _stage = _Stage.failed;
            _error = 'We could not process this video. Please try another file.';
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'Upload failed. Check your connection and try again.';
      });
    }
  }

  void _reset() {
    _statusSub?.cancel();
    setState(() {
      _stage = _Stage.choosing;
      _video = null;
      _videoBytes = 0;
      _progress = 0;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Post a reel'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: switch (_stage) {
            _Stage.choosing => _choosing(),
            _Stage.uploading => _status(
                icon: Icons.cloud_upload_outlined,
                title: 'Uploading ${(_progress * 100).round()}%',
                body: 'Keep the app open until the upload finishes.',
                progress: _progress,
              ),
            _Stage.processing => _status(
                icon: Icons.auto_awesome_outlined,
                title: 'Getting your reel ready',
                body: 'Upload done. We are preparing it for smooth playback. '
                    'You can leave this screen; it will go live on its own.',
                action: _button('Back to reels', () => context.pop()),
              ),
            _Stage.live => _status(
                icon: Icons.check_circle_outline,
                title: 'Your reel is live',
                body: 'People can now see it in their feed.',
                action: _button('Post another', _reset),
              ),
            _Stage.failed => _status(
                icon: Icons.error_outline,
                title: 'Something went wrong',
                body: _error ?? '',
                action: _button('Try again', _reset),
              ),
          },
        ),
      ),
    );
  }

  List<Widget> _choosing() {
    final hasVideo = _video != null;
    return [
      Row(
        children: [
          Expanded(child: _pickTile(Icons.video_library_outlined, 'Choose video', ImageSource.gallery)),
          const SizedBox(width: 12),
          Expanded(child: _pickTile(Icons.videocam_outlined, 'Record', ImageSource.camera)),
        ],
      ),
      if (hasVideo) ...[
        const SizedBox(height: 16),
        Text(
          'Video selected • ${(_videoBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      ],
      const SizedBox(height: 20),
      TextField(
        controller: _caption,
        maxLines: 4,
        maxLength: 2200,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Write a caption. Add #tags to help people find it.',
          hintStyle: const TextStyle(color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.darkSurface,
          counterStyle: const TextStyle(color: AppColors.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _button('Post', hasVideo && _error == null ? _post : null),
    ];
  }

  Widget _pickTile(IconData icon, String label, ImageSource source) {
    return Material(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pick(source),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 30),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _status({
    required IconData icon,
    required String title,
    required String body,
    double? progress,
    Widget? action,
  }) {
    return [
      const SizedBox(height: 40),
      Icon(icon, size: 56, color: AppColors.textPrimary),
      const SizedBox(height: 16),
      Text(title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
      if (progress != null) ...[
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: progress,
          color: AppColors.mpepeMaroon,
          backgroundColor: AppColors.darkSurface,
        ),
      ],
      if (action != null) ...[const SizedBox(height: 28), action],
    ];
  }

  Widget _button(String label, VoidCallback? onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.mpepeMaroon,
        disabledBackgroundColor: AppColors.darkSurfaceHighlight,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
