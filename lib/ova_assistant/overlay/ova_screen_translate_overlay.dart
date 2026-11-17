import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../shared/audio/ova_vertex_audio_engine.dart';
import '../../shared/language/world_languages.dart';
import '../../shared/theme/app_theme.dart';

/// Spatial screen text block extracted from Android AssistStructure,
/// AccessibilityNodeInfo bounds, or ML Kit on-device OCR.
class OvaScreenBlock {
  final String id;
  final String text;
  final Rect normRect; // 0..1 normalized coordinates
  final String? translated;
  final bool sameLanguage;

  const OvaScreenBlock({
    required this.id,
    required this.text,
    required this.normRect,
    this.translated,
    this.sameLanguage = false,
  });

  factory OvaScreenBlock.fromMap(Map<dynamic, dynamic> map, int index) {
    final l = ((map['left'] as num?)?.toDouble() ?? 0.05).clamp(0.0, 0.98);
    final t = ((map['top'] as num?)?.toDouble() ?? 0.1).clamp(0.0, 0.98);
    final r = ((map['right'] as num?)?.toDouble() ?? (l + 0.25)).clamp(l + 0.01, 1.0);
    final b = ((map['bottom'] as num?)?.toDouble() ?? (t + 0.04)).clamp(t + 0.01, 1.0);
    return OvaScreenBlock(
      id: (map['id'] ?? 'blk_$index').toString(),
      text: (map['text'] ?? '').toString().trim(),
      normRect: Rect.fromLTRB(l, t, r, b),
    );
  }

  OvaScreenBlock copyWith({String? translated, bool? sameLanguage}) =>
      OvaScreenBlock(
        id: id,
        text: text,
        normRect: normRect,
        translated: translated ?? this.translated,
        sameLanguage: sameLanguage ?? this.sameLanguage,
      );
}

enum OvaScreenMode { translate, highlight }

/// Fluid Holla / Gemini screen-edge light aura animation when Ova awakens.
class OvaEdgeAuraOverlay extends StatefulWidget {
  const OvaEdgeAuraOverlay({super.key, this.reduceMotion = false});

  final bool reduceMotion;

  @override
  State<OvaEdgeAuraOverlay> createState() => _OvaEdgeAuraOverlayState();
}

class _OvaEdgeAuraOverlayState extends State<OvaEdgeAuraOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.reduceMotion ? 260 : 950),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final v = _ctrl.value;
          if (v >= 1.0) return const SizedBox.shrink();
          return CustomPaint(
            painter: _EdgeAuraPainter(progress: v),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _EdgeAuraPainter extends CustomPainter {
  final double progress;
  _EdgeAuraPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final fade = progress < 0.25
        ? (progress / 0.25)
        : (1.0 - ((progress - 0.25) / 0.75)).clamp(0.0, 1.0);
    if (fade <= 0) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(28));
    final shader = SweepGradient(
      center: Alignment.bottomCenter,
      transform: GradientRotation(progress * math.pi * 1.4),
      colors: [
        AppColors.brandBlue.withValues(alpha: 0.75 * fade),
        AppColors.brandPink.withValues(alpha: 0.85 * fade),
        AppColors.brandBlue.withValues(alpha: 0.65 * fade),
        AppColors.brandPink.withValues(alpha: 0.80 * fade),
      ],
    ).createShader(rect);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..shader = shader;

    canvas.drawRRect(rrect, glow);
    canvas.drawRRect(rrect, core);
  }

  @override
  bool shouldRepaint(covariant _EdgeAuraPainter old) => old.progress != progress;
}

/// Interactive Holla / Gemini Screen Translate + Finger Highlight Layer that
/// stays cleanly over the active screen without navigating away.
class OvaScreenTranslateHighlightLayer extends StatefulWidget {
  final Uint8List? screenshotBytes;
  final List<OvaScreenBlock> initialBlocks;
  final OvaScreenMode initialMode;
  final VoidCallback onClose;
  final void Function(String prompt, Uint8List? regionBytes)? onAskOva;

  const OvaScreenTranslateHighlightLayer({
    super.key,
    required this.screenshotBytes,
    required this.initialBlocks,
    required this.initialMode,
    required this.onClose,
    this.onAskOva,
  });

  @override
  State<OvaScreenTranslateHighlightLayer> createState() =>
      _OvaScreenTranslateHighlightLayerState();
}

class _OvaScreenTranslateHighlightLayerState
    extends State<OvaScreenTranslateHighlightLayer> {
  late OvaScreenMode _mode = widget.initialMode;
  late List<OvaScreenBlock> _blocks = widget.initialBlocks;
  String _targetLang = '';
  bool _translating = false;
  bool _peekOriginal = false;
  String? _statusNote;

  // Freehand highlight / circle lasso state
  final List<Offset> _brushPoints = [];
  Rect? _selectedNormRect;
  bool _analyzingHighlight = false;
  Map<String, dynamic>? _highlightResult;
  Uint8List? _croppedBytes;

  @override
  void initState() {
    super.initState();
    final localeLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _targetLang = localeLang.isNotEmpty ? localeLang : 'en';
    if (_mode == OvaScreenMode.translate) {
      unawaited(_runInPlaceTranslation());
    }
  }

  @override
  void didUpdateWidget(covariant OvaScreenTranslateHighlightLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBlocks.length > _blocks.length && !_translating) {
      _blocks = widget.initialBlocks;
      if (_mode == OvaScreenMode.translate) {
        unawaited(_runInPlaceTranslation());
      }
    }
  }

  Future<void> _runInPlaceTranslation() async {
    final blocks = _blocks.where((b) => b.text.trim().isNotEmpty).take(55).toList();
    if (blocks.isEmpty) {
      if (mounted) {
        setState(() {
          _statusNote =
              'No readable text boxes found yet — switch to Highlight & drag your finger over any area.';
        });
      }
      return;
    }

    setState(() {
      _translating = true;
      _statusNote = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'chatAssist',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final res = await callable.call<dynamic>({
        'op': 'translateScreenBlocks',
        'target': _targetLang,
        'blocks': blocks
            .map((b) => {'id': b.id, 'text': b.text})
            .toList(),
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {};
      final list = (data['translations'] as List?) ?? const [];
      final byId = <String, Map<String, dynamic>>{};
      for (final item in list) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          byId[(m['id'] ?? '').toString()] = m;
        }
      }

      if (!mounted) return;
      setState(() {
        _blocks = _blocks.map((b) {
          final hit = byId[b.id];
          if (hit == null) return b;
          return b.copyWith(
            translated: (hit['translated'] ?? b.text).toString(),
            sameLanguage: hit['same'] == true,
          );
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusNote = 'Could not translate this screen right now.';
        });
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _analyzeHighlightedRegion(Rect normRect) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedNormRect = normRect;
      _analyzingHighlight = true;
      _highlightResult = null;
      _statusNote = null;
    });

    // Collect intersecting blocks inside or touching the highlighted box.
    final expanded = normRect.inflate(0.02);
    final selectedBlocks = _blocks
        .where((b) => b.normRect.overlaps(expanded))
        .map((b) => b.translated?.isNotEmpty == true ? b.text : b.text)
        .toList();
    final selectedText = selectedBlocks.join('\n').trim();
    final surroundingText = _blocks.take(20).map((b) => b.text).join('\n');

    Uint8List? cropBytes;
    if (widget.screenshotBytes != null) {
      try {
        final decoded = img.decodeImage(widget.screenshotBytes!);
        if (decoded != null) {
          final x = (normRect.left * decoded.width).round().clamp(0, decoded.width - 2);
          final y = (normRect.top * decoded.height).round().clamp(0, decoded.height - 2);
          final w = (normRect.width * decoded.width).round().clamp(16, decoded.width - x);
          final h = (normRect.height * decoded.height).round().clamp(16, decoded.height - y);
          final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
          cropBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 82));
        }
      } catch (_) {}
    }
    _croppedBytes = cropBytes;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'chatAssist',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final res = await callable.call<dynamic>({
        'op': 'highlightAnalyze',
        'mode': 'explain_and_translate',
        'target': _targetLang,
        'selectedText': selectedText,
        'surroundingText': surroundingText,
        if (cropBytes != null) 'imageBase64': base64Encode(cropBytes),
      });
      final map = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
      if (!mounted) return;
      setState(() => _highlightResult = map);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _highlightResult = {
          'title': 'Highlighted Text',
          'answer': selectedText.isNotEmpty
              ? selectedText
              : 'Highlighted screen area ready for Ova.',
          'extractedText': selectedText,
        };
      });
    } finally {
      if (mounted) setState(() => _analyzingHighlight = false);
    }
  }

  void _speakAllVisible() {
    HapticFeedback.selectionClick();
    final lines = _blocks
        .map((b) => (!_peekOriginal && (b.translated?.isNotEmpty == true))
            ? b.translated!
            : b.text)
        .where((s) => s.trim().isNotEmpty)
        .take(15)
        .join('. ');
    if (lines.isNotEmpty) {
      unawaited(
        OvaVertexAudioEngine.instance.speak(lines, languageCode: _targetLang),
      );
    }
  }

  void _copyAllTranslated() {
    HapticFeedback.selectionClick();
    final text = _blocks
        .map((b) => (!_peekOriginal && (b.translated?.isNotEmpty == true))
            ? b.translated!
            : b.text)
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _statusNote = 'Copied translated text.');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDark = context.isDark;

    return Stack(
      children: [
        // 1. Frozen screen under the overlay so user never leaves their app
        if (widget.screenshotBytes != null)
          Positioned.fill(
            child: Image.memory(
              widget.screenshotBytes!,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          )
        else
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.14),
            ),
          ),

        // 2. Subtle tint in translate/highlight mode so overlays pop cleanly
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: 180.ms,
              color: _mode == OvaScreenMode.highlight
                  ? Colors.black.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ),

        // 3. In-place translated text pills mapped directly to original boxes
        if (_mode == OvaScreenMode.translate && !_peekOriginal)
          ..._blocks.map((b) {
            final text = (b.translated ?? '').trim();
            if (text.isEmpty || b.sameLanguage) return const SizedBox.shrink();
            final left = b.normRect.left * size.width;
            final top = b.normRect.top * size.height;
            final width = math.max(54.0, b.normRect.width * size.width);
            final height = math.max(20.0, b.normRect.height * size.height);
            return Positioned(
              left: left.clamp(4.0, size.width - 60.0),
              top: top.clamp(74.0, size.height - 90.0),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Clipboard.setData(ClipboardData(text: text));
                  setState(() => _statusNote = 'Copied: "$text"');
                },
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  unawaited(
                    OvaVertexAudioEngine.instance.speak(
                      text,
                      languageCode: _targetLang,
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (width + 26).clamp(90.0, size.width - left - 6),
                    minHeight: height.clamp(18.0, 56.0),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xEC101218)
                          : const Color(0xF2FFFFFF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.brandBlue.withValues(alpha: 0.65),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.22,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),

        // 4. Freehand Finger Highlight / Circle-to-Search canvas
        if (_mode == OvaScreenMode.highlight)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (d) {
                setState(() {
                  _highlightResult = null;
                  _selectedNormRect = null;
                  _brushPoints
                    ..clear()
                    ..add(d.localPosition);
                });
              },
              onPanUpdate: (d) {
                setState(() => _brushPoints.add(d.localPosition));
              },
              onPanEnd: (_) {
                if (_brushPoints.length < 3 || size.width <= 0 || size.height <= 0) {
                  return;
                }
                double minX = _brushPoints.first.dx;
                double maxX = minX;
                double minY = _brushPoints.first.dy;
                double maxY = minY;
                for (final p in _brushPoints) {
                  minX = math.min(minX, p.dx);
                  maxX = math.max(maxX, p.dx);
                  minY = math.min(minY, p.dy);
                  maxY = math.max(maxY, p.dy);
                }
                if ((maxX - minX) < 18 && (maxY - minY) < 18) {
                  // Single tap highlight: create a generous box around tap point
                  minX = (minX - 60).clamp(0, size.width);
                  maxX = (maxX + 60).clamp(0, size.width);
                  minY = (minY - 26).clamp(0, size.height);
                  maxY = (maxY + 26).clamp(0, size.height);
                }
                final norm = Rect.fromLTRB(
                  (minX / size.width).clamp(0.0, 1.0),
                  (minY / size.height).clamp(0.0, 1.0),
                  (maxX / size.width).clamp(0.0, 1.0),
                  (maxY / size.height).clamp(0.0, 1.0),
                );
                unawaited(_analyzeHighlightedRegion(norm));
              },
              child: CustomPaint(
                painter: _HighlightStrokePainter(
                  points: _brushPoints,
                  selectedNormRect: _selectedNormRect,
                ),
                size: Size.infinite,
              ),
            ),
          ),

        // 5. Top Compact Floating Control Pill (Mode + Language + Peek + Speak + Close)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 12,
          right: 12,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.45),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _modeChip(
                      context,
                      icon: Icons.translate_rounded,
                      label: 'Translate',
                      selected: _mode == OvaScreenMode.translate,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _mode = OvaScreenMode.translate);
                        if (_blocks.every((b) => b.translated == null)) {
                          unawaited(_runInPlaceTranslation());
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _modeChip(
                      context,
                      icon: Icons.draw_rounded,
                      label: 'Highlight',
                      selected: _mode == OvaScreenMode.highlight,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _mode = OvaScreenMode.highlight);
                      },
                    ),
                    const SizedBox(width: 8),
                    _languagePickerChip(context),
                    if (_mode == OvaScreenMode.translate) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTapDown: (_) => setState(() => _peekOriginal = true),
                        onTapUp: (_) => setState(() => _peekOriginal = false),
                        onTapCancel: () => setState(() => _peekOriginal = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: _peekOriginal
                                ? AppColors.brandPink.withValues(alpha: 0.18)
                                : context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(color: context.border),
                          ),
                          child: Text(
                            _peekOriginal ? 'Original' : 'Peek',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _peekOriginal ? AppColors.brandPink : context.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Listen (Vertex Live Voice)',
                        visualDensity: VisualDensity.compact,
                        onPressed: _speakAllVisible,
                        icon: const Icon(Icons.volume_up_rounded, size: 17, color: AppColors.brandBlue),
                      ),
                      IconButton(
                        tooltip: 'Copy translated text',
                        visualDensity: VisualDensity.compact,
                        onPressed: _copyAllTranslated,
                        icon: Icon(Icons.copy_rounded, size: 16, color: context.textPrimary),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Close screen overlay',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        unawaited(OvaVertexAudioEngine.instance.stop());
                        widget.onClose();
                      },
                      icon: Icon(Icons.close_rounded, size: 18, color: context.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.1, end: 0),
        ),

        // 6. Highlight hint pill when waiting for finger draw
        if (_mode == OvaScreenMode.highlight &&
            _selectedNormRect == null &&
            !_analyzingHighlight)
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: context.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gesture_rounded, size: 15, color: AppColors.brandPink),
                    const SizedBox(width: 7),
                    Text(
                      'Circle or highlight anything on screen',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 7. Anchored Highlight Insight / Translation Result Card (staying in place!)
        if (_mode == OvaScreenMode.highlight &&
            (_analyzingHighlight || _highlightResult != null))
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 14,
            left: 14,
            right: 14,
            child: _highlightResultCard(context),
          ),

        // 8. Translating or status pill
        if (_translating || _statusNote != null)
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 18,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: context.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: context.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_translating) ...[
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.brandBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        _translating ? 'Translating screen in place…' : (_statusNote ?? ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _modeChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? AppColors.brandBlue : context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? Colors.white : context.textPrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languagePickerChip(BuildContext context) {
    final current = WorldLanguages.byCode(_targetLang) ??
        const WorldLanguage('en', 'English', 'English');
    return PopupMenuButton<String>(
      tooltip: 'Choose translation language',
      color: context.surface,
      onSelected: (code) {
        setState(() => _targetLang = code);
        if (_mode == OvaScreenMode.translate) {
          unawaited(_runInPlaceTranslation());
        } else if (_selectedNormRect != null) {
          unawaited(_analyzeHighlightedRegion(_selectedNormRect!));
        }
      },
      itemBuilder: (_) => WorldLanguages.all
          .take(28)
          .map(
            (lang) => PopupMenuItem<String>(
              value: lang.code,
              child: Text(
                '${lang.name} (${lang.native})',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: lang.code == _targetLang ? FontWeight.w700 : FontWeight.w500,
                  color: lang.code == _targetLang ? AppColors.brandBlue : context.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.name,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 15, color: context.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _highlightResultCard(BuildContext context) {
    if (_analyzingHighlight) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
            ),
            const SizedBox(width: 10),
            Text(
              'Reading highlighted selection…',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
          ],
        ),
      );
    }

    final res = _highlightResult ?? const {};
    final title = (res['title'] ?? 'Ova Insight').toString();
    final answer = (res['answer'] ?? '').toString();
    final translated = (res['translated'] ?? '').toString();
    final extracted = (res['extractedText'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.brandPink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Listen with Vertex Voice',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final spoken = translated.isNotEmpty ? translated : answer;
                  if (spoken.isNotEmpty) {
                    unawaited(OvaVertexAudioEngine.instance.speak(spoken, languageCode: _targetLang));
                  }
                },
                icon: const Icon(Icons.volume_up_rounded, size: 17, color: AppColors.brandBlue),
              ),
              IconButton(
                tooltip: 'Clear highlight',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _selectedNormRect = null;
                  _highlightResult = null;
                  _brushPoints.clear();
                }),
                icon: Icon(Icons.close_rounded, size: 17, color: context.textSecondary),
              ),
            ],
          ),
          if (translated.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35)),
              ),
              child: Text(
                translated,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
          ],
          if (answer.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              answer,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _miniAction(
                context,
                Icons.copy_rounded,
                'Copy',
                () {
                  final clip = translated.isNotEmpty
                      ? translated
                      : (extracted.isNotEmpty ? extracted : answer);
                  Clipboard.setData(ClipboardData(text: clip));
                  setState(() => _statusNote = 'Copied selection.');
                },
              ),
              if (widget.onAskOva != null)
                _miniAction(
                  context,
                  Icons.chat_bubble_outline_rounded,
                  'Ask Ova more',
                  () {
                    widget.onAskOva!(
                      'Tell me more about this highlighted area${extracted.isNotEmpty ? ": $extracted" : ""}',
                      _croppedBytes ?? widget.screenshotBytes,
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _miniAction(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.brandBlue),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightStrokePainter extends CustomPainter {
  final List<Offset> points;
  final Rect? selectedNormRect;

  _HighlightStrokePainter({required this.points, required this.selectedNormRect});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      final shader = const LinearGradient(
        colors: [AppColors.brandBlue, AppColors.brandPink],
      ).createShader(Offset.zero & size);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = shader
          ..color = AppColors.brandBlue.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = shader,
      );
    }

    if (selectedNormRect != null) {
      final r = Rect.fromLTRB(
        selectedNormRect!.left * size.width,
        selectedNormRect!.top * size.height,
        selectedNormRect!.right * size.width,
        selectedNormRect!.bottom * size.height,
      );
      final rr = RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(12));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = AppColors.brandPink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HighlightStrokePainter old) =>
      old.points.length != points.length || old.selectedNormRect != selectedNormRect;
}
