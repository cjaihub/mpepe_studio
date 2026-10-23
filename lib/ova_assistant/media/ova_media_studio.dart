import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../shared/theme/app_theme.dart';
import 'ova_brand_voice_sheet.dart';
import 'ova_media_brain.dart';

/// Full-screen premium reader for chat media (photo, video, voice note, PDF,
/// file) with Ova Vision: one-tap skills and free questions that run in the
/// background and keep going after the reader closes.
class OvaMediaStudio extends ConsumerStatefulWidget {
  /// Network URL or local file path.
  final String source;
  final OvaMediaKind kind;
  final String? fileName;

  /// The file came from an end-to-end encrypted chat.
  final bool fromEncryptedChat;
  final void Function(String text)? onInsertIntoChat;

  const OvaMediaStudio({
    super.key,
    required this.source,
    required this.kind,
    this.fileName,
    this.fromEncryptedChat = false,
    this.onInsertIntoChat,
  });

  static Future<void> open(
    BuildContext context, {
    required String source,
    required OvaMediaKind kind,
    String? fileName,
    bool fromEncryptedChat = false,
    void Function(String text)? onInsertIntoChat,
  }) {
    HapticFeedback.lightImpact();
    return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => OvaMediaStudio(
        source: source,
        kind: kind,
        fileName: fileName,
        fromEncryptedChat: fromEncryptedChat,
        onInsertIntoChat: onInsertIntoChat,
      ),
      transitionsBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        );
      },
    ));
  }

  @override
  ConsumerState<OvaMediaStudio> createState() => _OvaMediaStudioState();
}

class _OvaResult {
  final String title;
  final IconData icon;
  String? text;
  String? error;
  _OvaResult(this.title, this.icon);
  bool get loading => text == null && error == null;
}

class _OvaMediaStudioState extends ConsumerState<OvaMediaStudio> {
  // Results survive closing and reopening the same file in this app run.
  static final Map<String, List<_OvaResult>> _history = {};
  static bool _encryptedConsentGiven = false;

  File? _file;
  String? _loadError;
  final _ask = TextEditingController();
  final _askFocus = FocusNode();
  bool _panelOpen = true;
  double _dragDy = 0;

  List<_OvaResult> get _results => _history.putIfAbsent(widget.source, () => []);
  String get _label => widget.fileName?.isNotEmpty == true ? widget.fileName! : _kindName;
  String get _kindName => switch (widget.kind) {
        OvaMediaKind.image => 'Photo',
        OvaMediaKind.video => 'Video',
        OvaMediaKind.audio => 'Voice note',
        OvaMediaKind.pdf => 'PDF',
        OvaMediaKind.document => 'File',
      };

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _ask.dispose();
    _askFocus.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    try {
      if (widget.source.startsWith('/')) {
        _file = File(widget.source);
      } else {
        final dir = await getTemporaryDirectory();
        final ext = _extension(widget.fileName, widget.source);
        final f = File('${dir.path}/ova_media_${widget.source.hashCode.toUnsigned(32)}$ext');
        if (!await f.exists() || await f.length() == 0) {
          final res = await http.get(Uri.parse(widget.source));
          if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
          await f.writeAsBytes(res.bodyBytes, flush: true);
        }
        _file = f;
      }
    } catch (e) {
      _loadError = 'Could not open this file ($e).';
    }
    if (mounted) setState(() {});
  }

  static String _extension(String? fileName, String url) {
    final name = (fileName ?? '').isNotEmpty ? fileName! : Uri.parse(url).pathSegments.lastOrNull ?? '';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || name.length - dot > 6) return '';
    return name.substring(dot);
  }

  Future<bool> _consent() async {
    if (!widget.fromEncryptedChat || _encryptedConsentGiven) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text('Let Ova read this file?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Text(
          'This chat is end-to-end encrypted. To read the file, Ova sends a copy to its AI provider (Google Gemini). '
          'Nothing is shared with the chat or saved by Oneova.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow for this session'),
          ),
        ],
      ),
    );
    if (ok == true) _encryptedConsentGiven = true;
    return ok == true;
  }

  Future<void> _runSkill({OvaMediaSkill? skill, String? question}) async {
    final file = _file;
    if (file == null) return;
    if (!await _consent()) return;
    HapticFeedback.selectionClick();
    final r = _OvaResult(skill?.label ?? 'You asked: ${question ?? ''}', skill?.icon ?? Icons.forum_rounded);
    setState(() {
      _results.insert(0, r);
      _panelOpen = true;
    });
    try {
      r.text = await ref.read(ovaMediaBrainProvider).run(
            file: file,
            kind: widget.kind,
            skill: skill,
            question: question,
            fileLabel: _label,
          );
    } catch (e) {
      r.error = e.toString();
    }
    if (mounted) setState(() {});
  }

  void _submitAsk() {
    final q = _ask.text.trim();
    if (q.isEmpty) return;
    _ask.clear();
    _askFocus.unfocus();
    _runSkill(question: q);
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: _label));
  }

  Future<void> _editBrandVoice() => showOvaBrandVoiceEditor(context, ref);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final opacity = (1 - (_dragDy.abs() / 400)).clamp(0.4, 1.0);
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.darkBackground.withValues(alpha: opacity),
        resizeToAvoidBottomInset: true,
        body: Stack(children: [
          // Ambient brand glow behind the media.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.6),
                    radius: 1.2,
                    colors: [AppColors.brandBlue.withValues(alpha: 0.16), AppColors.darkBackground.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: top + 52,
            bottom: 0,
            child: GestureDetector(
              onVerticalDragUpdate: widget.kind == OvaMediaKind.image
                  ? (d) => setState(() => _dragDy += d.delta.dy)
                  : null,
              onVerticalDragEnd: widget.kind == OvaMediaKind.image
                  ? (d) {
                      if (_dragDy.abs() > 140 || d.primaryVelocity!.abs() > 900) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _dragDy = 0);
                      }
                    }
                  : null,
              child: AnimatedContainer(
                duration: _dragDy == 0 ? const Duration(milliseconds: 220) : Duration.zero,
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, _dragDy, 0),
                child: _viewer(),
              ),
            ),
          ),
          Positioned(top: top, left: 0, right: 0, child: _topBar()),
          Positioned(left: 0, right: 0, bottom: 0, child: _visionPanel()),
        ]),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      height: 52,
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Row(children: [
              if (widget.fromEncryptedChat) ...[
                const Icon(Icons.lock_rounded, size: 10, color: AppColors.textSecondary),
                const SizedBox(width: 3),
              ],
              Text(widget.fromEncryptedChat ? 'End-to-end encrypted · $_kindName' : _kindName,
                  style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
            ]),
          ]),
        ),
        IconButton(
          tooltip: 'Brand voice',
          icon: const Icon(Icons.diamond_outlined, size: 20, color: AppColors.textPrimary),
          onPressed: _editBrandVoice,
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.ios_share_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: _file == null ? null : _share,
        ),
      ]),
    );
  }

  Widget _viewer() {
    if (_loadError != null) return _Centered(icon: Icons.broken_image_rounded, text: _loadError!);
    final f = _file;
    if (f == null) {
      return const Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)),
      );
    }
    final bottomGap = _panelOpen ? 230.0 : 120.0;
    final child = switch (widget.kind) {
      OvaMediaKind.image => _PhotoView(file: f),
      OvaMediaKind.video => _VideoView(file: f),
      OvaMediaKind.audio => _AudioView(file: f, title: _label),
      OvaMediaKind.pdf => _PdfView(file: f),
      OvaMediaKind.document => _Centered(icon: Icons.description_rounded, text: _label),
    };
    return AnimatedPadding(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomGap),
      child: child,
    );
  }

  Widget _visionPanel() {
    final skills = ovaSkillsFor(widget.kind);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: EdgeInsets.fromLTRB(0, 8, 0, 10 + bottom),
          decoration: BoxDecoration(
            color: AppColors.darkSurface.withValues(alpha: 0.82),
            border: Border(top: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1)),
            boxShadow: [
              BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, -6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _panelOpen = !_panelOpen),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 12, 8),
                child: Row(children: [
                  const _OvaOrb(size: 22),
                  const SizedBox(width: 8),
                  Text('Ova Vision',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text('RUNS IN BACKGROUND',
                        style: GoogleFonts.inter(
                            fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: AppColors.brandPink)),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _panelOpen ? 0 : 0.5,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                  ),
                ]),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: skills.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _SkillChip(skill: skills[i], onTap: () => _runSkill(skill: skills[i]))
                    .animate()
                    .fadeIn(delay: (40 * i).ms, duration: 260.ms)
                    .slideX(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _panelOpen && _results.isNotEmpty
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _ResultCard(
                          result: _results[i],
                          onInsert: widget.onInsertIntoChat == null
                              ? null
                              : (t) {
                                  widget.onInsertIntoChat!(t);
                                  Navigator.of(context).pop();
                                },
                          onDismiss: () => setState(() => _results.removeAt(i)),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ask,
                    focusNode: _askFocus,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitAsk(),
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                    cursorColor: AppColors.brandBlue,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ask Ova about this ${_kindName.toLowerCase()}…',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.darkSurfaceHighlight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: const BorderSide(color: AppColors.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: const BorderSide(color: AppColors.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _GlowButton(icon: Icons.arrow_upward_rounded, onTap: _submitAsk),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── Viewers ─────────────────────────

class _PhotoView extends StatefulWidget {
  final File file;
  const _PhotoView({required this.file});

  @override
  State<_PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<_PhotoView> with SingleTickerProviderStateMixin {
  final _ctrl = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  TapDownDetails? _tap;

  @override
  void dispose() {
    _ctrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _ctrl.value.getMaxScaleOnAxis() > 1.01;
    final end = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-(_tap?.localPosition.dx ?? 0) * 1.5, -(_tap?.localPosition.dy ?? 0) * 1.5, 0, 1)
          ..scaleByDouble(2.5, 2.5, 1, 1));
    final tween = Matrix4Tween(begin: _ctrl.value, end: end)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    void tick() => _ctrl.value = tween.value;
    tween.addListener(tick);
    _anim.forward(from: 0).whenComplete(() => tween.removeListener(tick));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _ctrl,
        maxScale: 6,
        child: Center(
          child: Container(
            decoration: BoxDecoration(boxShadow: [
              BoxShadow(color: AppColors.brandBlack.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 18)),
            ]),
            child: Image.file(widget.file, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ).animate().fadeIn(duration: 260.ms),
        ),
      ),
    );
  }
}

class _VideoView extends StatefulWidget {
  final File file;
  const _VideoView({required this.file});

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  bool _ready = false;
  bool _chrome = true;
  double _speed = 1;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
      _scheduleHide();
    });
    _c.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _chrome = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)),
      );
    }
    final v = _c.value;
    return GestureDetector(
      onTap: () {
        setState(() => _chrome = !_chrome);
        _scheduleHide();
      },
      child: Stack(alignment: Alignment.center, children: [
        Center(
          child: AspectRatio(
            aspectRatio: v.aspectRatio,
            child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: VideoPlayer(_c)),
          ),
        ),
        AnimatedOpacity(
          opacity: _chrome || !v.isPlaying ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: _GlowButton(
            size: 58,
            icon: v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: () {
              v.isPlaying ? _c.pause() : _c.play();
              _scheduleHide();
            },
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: AnimatedOpacity(
            opacity: _chrome || !v.isPlaying ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: _Scrubber(
              position: v.position,
              duration: v.duration,
              onSeek: (d) => _c.seekTo(d),
              speed: _speed,
              onSpeed: () {
                final next = _speed == 1 ? 1.5 : (_speed == 1.5 ? 2.0 : 1.0);
                _c.setPlaybackSpeed(next);
                setState(() => _speed = next);
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _AudioView extends StatefulWidget {
  final File file;
  final String title;
  const _AudioView({required this.file, required this.title});

  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> with SingleTickerProviderStateMixin {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  bool _ready = false;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    });
    _c.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) {
              final t = v.isPlaying ? _pulse.value : 0.0;
              return Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    transform: GradientRotation(t * 2 * math.pi),
                    colors: [
                      AppColors.brandBlue,
                      AppColors.brandPink.withValues(alpha: 0.85),
                      AppColors.brandBlue,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.35 + 0.15 * math.sin(t * 2 * math.pi)),
                      blurRadius: 50,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.darkSurface),
                  child: const Icon(Icons.graphic_eq_rounded, size: 64, color: AppColors.textPrimary),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (_ready)
            _Scrubber(
              position: v.position,
              duration: v.duration,
              onSeek: (d) => _c.seekTo(d),
              speed: _speed,
              onSpeed: () {
                final next = _speed == 1 ? 1.5 : (_speed == 1.5 ? 2.0 : 1.0);
                _c.setPlaybackSpeed(next);
                setState(() => _speed = next);
              },
            ),
          const SizedBox(height: 12),
          _GlowButton(
            size: 56,
            icon: v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: !_ready ? null : () => v.isPlaying ? _c.pause() : _c.play(),
          ),
        ]),
      ),
    );
  }
}

class _PdfView extends StatefulWidget {
  final File file;
  const _PdfView({required this.file});

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  late final PdfControllerPinch _c = PdfControllerPinch(document: PdfDocument.openFile(widget.file.path));
  int _page = 1;
  int _pages = 0;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Centered(icon: Icons.picture_as_pdf_rounded, text: _error!);
    return Stack(children: [
      PdfViewPinch(
        controller: _c,
        padding: 12,
        backgroundDecoration: const BoxDecoration(color: Colors.transparent),
        onDocumentLoaded: (doc) => setState(() => _pages = doc.pagesCount),
        onPageChanged: (p) => setState(() => _page = p),
        onDocumentError: (e) => setState(() => _error = 'Could not open this PDF.'),
      ),
      if (_pages > 0)
        Positioned(
          right: 14,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.darkSurface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.outline),
            ),
            child: Text('$_page / $_pages',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ),
    ]);
  }
}

// ───────────────────────── Pieces ─────────────────────────

class _Scrubber extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final double speed;
  final VoidCallback onSpeed;
  const _Scrubber({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.speed,
    required this.onSpeed,
  });

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final value = (position.inMilliseconds / total).clamp(0.0, 1.0);
    return Row(children: [
      Text(_fmt(position), style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: AppColors.brandBlue,
            inactiveTrackColor: AppColors.textPrimary.withValues(alpha: 0.15),
            thumbColor: AppColors.brandWhite,
            overlayColor: AppColors.brandBlue.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            onChanged: (v) => onSeek(Duration(milliseconds: (v * total).round())),
          ),
        ),
      ),
      Text(_fmt(duration), style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: onSpeed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(color: AppColors.outline),
          ),
          child: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      ),
    ]);
  }
}

class _SkillChip extends StatelessWidget {
  final OvaMediaSkill skill;
  final VoidCallback onTap;
  const _SkillChip({required this.skill, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = skill.accent ? AppColors.brandPink : AppColors.brandBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            color: c.withValues(alpha: 0.12),
            border: Border.all(color: c.withValues(alpha: 0.45), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(skill.icon, size: 14, color: c),
            const SizedBox(width: 6),
            Text(skill.label,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _OvaResult result;
  final void Function(String text)? onInsert;
  final VoidCallback onDismiss;
  const _ResultCard({required this.result, required this.onInsert, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighlight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: r.error != null ? AppColors.brandPink.withValues(alpha: 0.5) : AppColors.outline),
        boxShadow: [BoxShadow(color: AppColors.brandBlack.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r.icon, size: 14, color: AppColors.brandBlue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          InkWell(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 15, color: AppColors.textMuted),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        if (r.loading)
          Row(children: [
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandPink)),
            const SizedBox(width: 8),
            Text('Ova is reading… you can close this, it keeps going.',
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textSecondary)),
          ]).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 600.ms).then().fade(begin: 1, end: 0.55)
        else if (r.error != null)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 4),
            child: Text(r.error!, style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: AppColors.textSecondary)),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SelectableText(r.text!,
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.42, color: AppColors.textPrimary)),
          ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.04, end: 0),
          const SizedBox(height: 4),
          Row(children: [
            _MiniAction(
              icon: Icons.copy_rounded,
              label: 'Copy',
              onTap: () {
                Clipboard.setData(ClipboardData(text: r.text!));
                HapticFeedback.lightImpact();
              },
            ),
            if (onInsert != null) _MiniAction(icon: Icons.reply_rounded, label: 'Use in chat', onTap: () => onInsert!(r.text!)),
            _MiniAction(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: () => SharePlus.instance.share(ShareParams(text: r.text!)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: AppColors.brandBlue),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandBlue)),
          ]),
        ),
      );
}

class _GlowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const _GlowButton({required this.icon, required this.onTap, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandBlue, Color.lerp(AppColors.brandBlue, AppColors.brandPink, 0.35)!],
          ),
          boxShadow: [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Icon(icon, size: size * 0.48, color: AppColors.brandWhite),
      ),
    );
  }
}

class _OvaOrb extends StatelessWidget {
  final double size;
  const _OvaOrb({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
          boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.35), blurRadius: 10)],
        ),
        child: Icon(Icons.auto_awesome_rounded, size: size * 0.55, color: AppColors.brandWhite),
      );
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Centered({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          ]),
        ),
      );
}
