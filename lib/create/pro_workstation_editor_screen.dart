import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../shared/theme/app_theme.dart';
import '../backend/projects/models/oneova_draft_model.dart';
import '../backend/projects/services/oneova_draft_engine.dart';
import '../shared/widgets/oneova_file_picker.dart';
import 'media_preview_screen.dart';
import 'widgets/exporting_progress_sheet.dart';
import 'widgets/oneova_clip_trimmer_sheet.dart';

/// Oneova Pro Workstation Editor
/// Merges fluid mobile velocity with the deep color science of Oneova Studio.
/// Features responsive adaptation (Portrait Mobile vs Landscape/Tablet Studio Console).
class ProWorkstationEditorScreen extends ConsumerStatefulWidget {
  final OneovaDraft draft;

  const ProWorkstationEditorScreen({super.key, required this.draft});

  @override
  ConsumerState<ProWorkstationEditorScreen> createState() =>
      _ProWorkstationEditorScreenState();
}

class _ProWorkstationEditorScreenState
    extends ConsumerState<ProWorkstationEditorScreen> {
  late OneovaDraft _draft;
  VideoPlayerController? _videoController;
  bool _isPlayerInitialized = false;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // Active Tool Panel: 'none', 'cut', 'text', 'audio', 'color', 'ai', 'inspector'
  String _activeTool = 'none';

  // Selected Text Overlay for Interactive Drag & Edit
  String? _selectedTextOverlayId;
  final TextEditingController _textInputController = TextEditingController();

  // Oneova Color Science state
  late OneovaColorGrade _colorGrade;

  // Audio Mix state
  late OneovaAudioMix _audioMix;

  // Auto-Save Debouncer
  Timer? _autoSaveTimer;
  bool _hasUnsavedChanges = false;

  // UI Modes
  bool _showScopes = false;
  bool _showSafeAreas = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _colorGrade = _draft.colorGrade;
    _audioMix = _draft.audioMix;

    if (_draft.isVideo && _draft.mediaPath.isNotEmpty) {
      _initVideoPlayer();
    }
  }

  Future<void> _initVideoPlayer() async {
    try {
      final file = File(_draft.mediaPath);
      if (await file.exists()) {
        _videoController = VideoPlayerController.file(file);
        await _videoController!.initialize();
        _videoController!.setLooping(true);
        _videoController!.setVolume(_audioMix.originalVolume);

        _videoController!.addListener(() {
          if (mounted && _videoController!.value.isInitialized) {
            final pos = _videoController!.value.position;
            // Enforce trim range loop if trimmed
            if (_draft.trimEndSeconds > _draft.trimStartSeconds) {
              final endMillis = (_draft.trimEndSeconds * 1000).toInt();
              final startMillis = (_draft.trimStartSeconds * 1000).toInt();
              if (pos.inMilliseconds >= endMillis || pos.inMilliseconds < startMillis - 200) {
                _videoController!.seekTo(Duration(milliseconds: startMillis));
              }
            }
            setState(() {
              _currentPosition = _videoController!.value.position;
              _totalDuration = _videoController!.value.duration;
              _isPlaying = _videoController!.value.isPlaying;
            });
          }
        });

        if (mounted) {
          setState(() {
            _isPlayerInitialized = true;
            _totalDuration = _videoController!.value.duration;
            if (_draft.durationSeconds == 0.0) {
              _draft = _draft.copyWith(
                durationSeconds: _totalDuration.inMilliseconds / 1000.0,
              );
            }
          });
          if (_draft.trimStartSeconds > 0) {
            _videoController!.seekTo(
              Duration(milliseconds: (_draft.trimStartSeconds * 1000).toInt()),
            );
          }
          if (_draft.speedMultiplier != 1.0) {
            _videoController!.setPlaybackSpeed(_draft.speedMultiplier);
          }
          _videoController!.play();
        }
      }
    } catch (e) {
      debugPrint('[ProWorkstationEditor] Video player initialization notice: $e');
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _videoController?.dispose();
    _textInputController.dispose();
    super.dispose();
  }

  void _markChanged() {
    _hasUnsavedChanges = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      _persistDraft(silent: true);
    });
  }

  Future<void> _persistDraft({bool silent = false}) async {
    final updated = _draft.copyWith(
      colorGrade: _colorGrade,
      audioMix: _audioMix,
      updatedAt: DateTime.now(),
    );
    _draft = updated;
    await ref.read(oneovaDraftEngineProvider.notifier).saveDraft(updated);
    _hasUnsavedChanges = false;

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Draft saved to Oneova Projects',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: AppColors.brandBlue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Safeguard: TikTok / IG Standard Exit Confirmation
  // ──────────────────────────────────────────────────────────────────────────
  Future<bool> _onWillPop() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.border),
        ),
        title: Text(
          'Save to Drafts?',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        content: Text(
          'Your edits will be saved so you can continue editing anytime from Studio Projects.',
          style: GoogleFonts.inter(
            color: context.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(
              'Keep Editing',
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(
              'Discard',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Save Draft',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _persistDraft(silent: true);
      return true;
    } else if (result == 'discard') {
      return true;
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DaVinci Resolve Color Matrix Transformer
  // ──────────────────────────────────────────────────────────────────────────
  ColorFilter _buildColorFilter() {
    final exp = _colorGrade.exposure;     // -1.0 to 1.0
    final cont = _colorGrade.contrast;   // 0.5 to 1.5
    final sat = _colorGrade.saturation;  // 0.0 to 2.0
    final temp = _colorGrade.temperature;// -1.0 to 1.0
    final tint = _colorGrade.tint;       // -1.0 to 1.0

    // Red, Green, Blue channel gain adjustments for temperature & tint
    double rGain = (1.0 + exp) * cont * (1.0 + temp * 0.2);
    double gGain = (1.0 + exp) * cont * (1.0 - tint * 0.2);
    double bGain = (1.0 + exp) * cont * (1.0 - temp * 0.2);

    // Apply LUT preset biases
    switch (_colorGrade.lutPreset) {
      case 'cinematic':
        // Teal and Orange Hollywood contrast
        rGain *= 1.15;
        bGain *= 1.1;
        break;
      case 'warm_gold':
        rGain *= 1.25;
        gGain *= 1.05;
        bGain *= 0.85;
        break;
      case 'noir':
        // Desaturate completely with high contrast
        return const ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0,    1, 0,
        ]);
      case 'cyber_pink':
        rGain *= 1.3;
        bGain *= 1.25;
        gGain *= 0.85;
        break;
      case 'vibrant':
        rGain *= 1.1;
        gGain *= 1.1;
        bGain *= 1.1;
        break;
    }

    // Luminance constants for saturation calculation
    const rw = 0.2126;
    const gw = 0.7152;
    const bw = 0.0722;

    final invSat = 1.0 - sat;
    final rR = invSat * rw + sat;
    final rG = invSat * gw;
    final rB = invSat * bw;

    final gR = invSat * rw;
    final gG = invSat * gw + sat;
    final gB = invSat * bw;

    final bR = invSat * rw;
    final bG = invSat * gw;
    final bB = invSat * bw + sat;

    final matrix = [
      rR * rGain, rG * rGain, rB * rGain, 0.0, 0.0,
      gR * gGain, gG * gGain, gB * gGain, 0.0, 0.0,
      bR * bGain, bG * bGain, bB * bGain, 0.0, 0.0,
      0.0,        0.0,        0.0,        1.0, 0.0,
    ];

    return ColorFilter.matrix(matrix);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.bg,
        body: SafeArea(
          child: OrientationBuilder(
            builder: (context, orientation) {
              final isLandscape = orientation == Orientation.landscape;
              final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

              if (isLandscape || isTablet) {
                return _buildOneovaStudioConsole();
              }
              return _buildOneovaMobileWorkstation();
            },
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PORTRAIT WORKSTATION (Oneova Mobile Workstation)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildOneovaMobileWorkstation() {
    return Column(
      children: [
        _buildTopHeader(),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildCanvasViewport(),
              if (_showSafeAreas) _buildSafeAreasOverlay(),
            ],
          ),
        ),
        _buildPlaybackScrubber(),
        if (_activeTool != 'none') _buildActiveToolDrawer(),
        _buildOneovaActionRail(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TABLET / LANDSCAPE CONSOLE (Oneova Studio Console)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildOneovaStudioConsole() {
    return Column(
      children: [
        _buildTopHeader(),
        Expanded(
          child: Row(
            children: [
              // Left: Media Pool & Layers
              SizedBox(
                width: 260,
                child: _buildStudioMediaPool(),
              ),
              VerticalDivider(width: 1, color: context.border),
              // Center: Viewport & Multitrack Timeline
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _buildCanvasViewport(),
                          if (_showScopes) _buildScopeOverlay(),
                          if (_showSafeAreas) _buildSafeAreasOverlay(),
                        ],
                      ),
                    ),
                    _buildPlaybackScrubber(),
                    _buildMultiTrackTimeline(),
                  ],
                ),
              ),
              VerticalDivider(width: 1, color: context.border),
              // Right: Oneova Color Science Deck & Inspector
              SizedBox(
                width: 320,
                child: _buildOneovaInspectorDeck(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Shared Components: Top Bar
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: context.textPrimary),
            tooltip: 'Back to Projects',
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _draft.title,
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.brandPink, width: 0.8),
                      ),
                      child: Text(
                        _draft.isVideo ? '4K 60FPS' : 'RAW PHOTO',
                        style: GoogleFonts.inter(
                          color: AppColors.brandPink,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _hasUnsavedChanges ? 'Editing...' : 'Synced',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Toggle Scopes
          IconButton(
            icon: Icon(
              Icons.graphic_eq,
              color: _showScopes ? AppColors.brandPink : context.textSecondary,
              size: 20,
            ),
            tooltip: 'Waveform Scopes',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => setState(() => _showScopes = !_showScopes),
          ),
          const SizedBox(width: 2),
          // Save to Device Quick Action
          IconButton(
            icon: Icon(Icons.download, color: context.textSecondary, size: 20),
            tooltip: 'Save to Device',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _saveToDevice,
          ),
          const SizedBox(width: 6),
          // Export / Next CTA (Brand Blue)
          ElevatedButton.icon(
            onPressed: _onExportOrPublish,
            icon: const Icon(Icons.arrow_forward, size: 15, color: Colors.white),
            label: Text(
              'Next',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 12.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Interactive Canvas Viewport (9:16 or 16:9 with Color Grading & Text)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCanvasViewport() {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _draft.aspectRatio,
          child: ColorFiltered(
            colorFilter: _buildColorFilter(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Raw Media Feed (Video Player or Static Photo)
                if (_draft.isVideo && _isPlayerInitialized && _videoController != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
                else if (!_draft.isVideo && File(_draft.mediaPath).existsSync())
                  Image.file(
                    File(_draft.mediaPath),
                    fit: BoxFit.cover,
                  )
                else
                  Container(
                    color: context.surfaceMid,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _draft.isVideo ? Icons.videocam : Icons.image,
                            size: 48,
                            color: AppColors.brandBlue,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Oneova Studio Canvas Ready',
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 2. Interactive Draggable Text Layers
                for (final textLayer in _draft.textOverlays)
                  _buildInteractiveTextLayer(textLayer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveTextLayer(OneovaTextOverlay layer) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final left = layer.x * constraints.maxWidth;
        final top = layer.y * constraints.maxHeight;
        final isSelected = _selectedTextOverlayId == layer.id;

        return Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                final newX = ((left + details.delta.dx) / constraints.maxWidth).clamp(0.0, 0.85);
                final newY = ((top + details.delta.dy) / constraints.maxHeight).clamp(0.0, 0.85);
                final updated = _draft.textOverlays.map((t) {
                  return t.id == layer.id ? t.copyWith(x: newX, y: newY) : t;
                }).toList();
                _draft = _draft.copyWith(textOverlays: updated);
              });
              _markChanged();
            },
            onTap: () {
              setState(() {
                _selectedTextOverlayId = layer.id;
                _textInputController.text = layer.text;
                _activeTool = 'text';
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: layer.backgroundColorHex != null
                    ? Color(layer.backgroundColorHex!)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: AppColors.brandPink, width: 2)
                    : null,
              ),
              child: Text(
                layer.text,
                style: GoogleFonts.inter(
                  fontSize: layer.fontSize * layer.scale,
                  fontWeight: layer.isBold ? FontWeight.w900 : FontWeight.w600,
                  color: Color(layer.colorHex),
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 1)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSafeAreasOverlay() {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.brandPink.withValues(alpha: 0.4),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              '90% ACTION SAFE',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScopeOverlay() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RGB WAVEFORM',
              style: GoogleFonts.inter(
                color: AppColors.brandBlue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _scopeBar('R', Colors.redAccent, 0.7),
                  _scopeBar('G', Colors.greenAccent, 0.85),
                  _scopeBar('B', AppColors.brandBlue, 0.9),
                  _scopeBar('L', Colors.white, 0.78),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeBar(String label, Color color, double level) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(width: 8, color: Colors.white10),
              Container(
                width: 8,
                height: 38 * level,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 8),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Playback Scrubber Bar
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildPlaybackScrubber() {
    final curSec = _currentPosition.inMilliseconds / 1000.0;
    final totalSec = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds / 1000.0
        : 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.surface,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: AppColors.brandBlue,
              size: 32,
            ),
            onPressed: () {
              if (_videoController != null && _isPlayerInitialized) {
                if (_isPlaying) {
                  _videoController!.pause();
                } else {
                  _videoController!.play();
                }
              }
            },
          ),
          Text(
            _formatDuration(_currentPosition),
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: AppColors.brandBlue,
                inactiveTrackColor: context.border,
                thumbColor: AppColors.brandPink,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: curSec.clamp(0.0, totalSec),
                min: 0.0,
                max: totalSec,
                onChanged: (val) {
                  final target = Duration(milliseconds: (val * 1000).toInt());
                  _videoController?.seekTo(target);
                },
              ),
            ),
          ),
          Text(
            _formatDuration(_totalDuration),
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _showSafeAreas ? Icons.crop_square : Icons.crop_free,
              color: _showSafeAreas ? AppColors.brandPink : context.textMuted,
              size: 20,
            ),
            tooltip: 'Safe Area Overlay',
            onPressed: () => setState(() => _showSafeAreas = !_showSafeAreas),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Oneova Bottom Tool Rail (Mobile)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildOneovaActionRail() {
    final tools = [
      {'id': 'cut', 'icon': Icons.content_cut, 'label': 'Cut / Trim'},
      {'id': 'text', 'icon': Icons.title, 'label': 'Text'},
      {'id': 'audio', 'icon': Icons.music_note, 'label': 'Audio'},
      {'id': 'color', 'icon': Icons.color_lens, 'label': 'Oneova Color'},
      {'id': 'ai', 'icon': Icons.palette_outlined, 'label': 'Quick Grade'},
    ];

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tools.map((tool) {
          final isSelected = _activeTool == tool['id'];
          return InkWell(
            onTap: () {
              setState(() {
                _activeTool = isSelected ? 'none' : tool['id'] as String;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tool['icon'] as IconData,
                    color: isSelected ? AppColors.brandPink : context.textPrimary,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool['label'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? AppColors.brandPink : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Active Tool Drawer (Sliders, Color Science, Text Input)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildActiveToolDrawer() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _activeTool.toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppColors.brandPink,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.textSecondary, size: 18),
                onPressed: () => setState(() => _activeTool = 'none'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildDrawerContent()),
        ],
      ),
    );
  }

  Widget _buildDrawerContent() {
    switch (_activeTool) {
      case 'cut':
        return _buildCutControls();
      case 'text':
        return _buildTextControls();
      case 'audio':
        return _buildAudioControls();
      case 'color':
        return _buildColorScienceControls();
      case 'ai':
        return _buildAiSuiteControls();
      default:
        return const SizedBox();
    }
  }

  Widget _buildCutControls() {
    final maxDur = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds / 1000.0
        : (_draft.durationSeconds > 0 ? _draft.durationSeconds : 60.0);
    final inSec = _draft.trimStartSeconds.clamp(0.0, maxDur);
    final outSec = (_draft.trimEndSeconds > inSec ? _draft.trimEndSeconds : maxDur).clamp(inSec, maxDur);
    final effectiveSec = (outSec - inSec) / (_draft.speedMultiplier > 0 ? _draft.speedMultiplier : 1.0);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Primary Action: Launch Full Clip Trimmer & Inspector
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            child: ElevatedButton.icon(
              onPressed: () async {
                final file = File(_draft.mediaPath);
                if (!file.existsSync()) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Media file not found on disk: ${_draft.mediaPath}',
                          style: GoogleFonts.inter(),
                        ),
                        backgroundColor: AppColors.brandPink,
                      ),
                    );
                  }
                  return;
                }
                if (!mounted) return;
                final trimmed = await OneovaClipTrimmerSheet.show(
                  context,
                  videoFile: file,
                  clipTitle: _draft.title,
                  actionLabel: 'Apply to Sequence',
                );
                if (trimmed != null && mounted) {
                  setState(() {
                    _draft = _draft.copyWith(
                      trimStartSeconds: trimmed.startSeconds,
                      trimEndSeconds: trimmed.endSeconds,
                      speedMultiplier: trimmed.speed,
                      aspectRatio: trimmed.aspectRatio,
                    );
                    if (trimmed.muteAudio) {
                      _audioMix = _audioMix.copyWith(originalVolume: 0.0);
                      _videoController?.setVolume(0.0);
                    }
                    _videoController?.setPlaybackSpeed(trimmed.speed);
                    _videoController?.seekTo(
                      Duration(milliseconds: (trimmed.startSeconds * 1000).toInt()),
                    );
                  });
                  _markChanged();
                }
              },
              icon: const Icon(Icons.content_cut_rounded, size: 16, color: Colors.white),
              label: Text(
                'Open Advanced Trimmer & Sequence Ingest',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),

          // 2. In / Out Timecode Badges
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IN POINT',
                          style: GoogleFonts.inter(
                              fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.brandBlue)),
                      Text(_formatDuration(Duration(milliseconds: (inSec * 1000).toInt())),
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OUT POINT',
                          style: GoogleFonts.inter(
                              fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.brandPink)),
                      Text(_formatDuration(Duration(milliseconds: (outSec * 1000).toInt())),
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DURATION',
                        style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w800, color: context.textSecondary)),
                    Text('${effectiveSec.toStringAsFixed(1)}s',
                        style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 3. Quick Playhead Cut In/Out Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final cur = _currentPosition.inMilliseconds / 1000.0;
                    setState(() {
                      _draft = _draft.copyWith(trimStartSeconds: cur);
                    });
                    _markChanged();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(color: AppColors.brandBlue),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Set IN at Playhead',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final cur = _currentPosition.inMilliseconds / 1000.0;
                    setState(() {
                      _draft = _draft.copyWith(trimEndSeconds: cur);
                    });
                    _markChanged();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandPink,
                    side: const BorderSide(color: AppColors.brandPink),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Set OUT at Playhead',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.refresh_rounded, size: 20, color: context.textSecondary),
                tooltip: 'Reset In/Out Points',
                onPressed: () {
                  setState(() {
                    _draft = _draft.copyWith(trimStartSeconds: 0.0, trimEndSeconds: 0.0);
                  });
                  _markChanged();
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 4. Interactive In/Out Range Slider
          Text(
            'Trim Sequence Range',
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          RangeSlider(
            values: RangeValues(inSec, outSec),
            min: 0.0,
            max: maxDur > 0 ? maxDur : 1.0,
            activeColor: AppColors.brandBlue,
            inactiveColor: context.border,
            onChanged: (RangeValues vals) {
              setState(() {
                _draft = _draft.copyWith(
                  trimStartSeconds: vals.start,
                  trimEndSeconds: vals.end,
                );
              });
              _videoController?.seekTo(Duration(milliseconds: (vals.start * 1000).toInt()));
            },
            onChangeEnd: (_) => _markChanged(),
          ),

          const SizedBox(height: 8),

          // 5. Speed Multiplier
          Text(
            'Speed Multiplier: ${_draft.speedMultiplier.toStringAsFixed(1)}x',
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [0.5, 1.0, 1.5, 2.0, 3.0].map((s) {
              final isCurrent = _draft.speedMultiplier == s;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${s}x', style: GoogleFonts.inter(color: isCurrent ? Colors.white : AppColors.textSecondary)),
                  selected: isCurrent,
                  selectedColor: AppColors.brandBlue,
                  backgroundColor: context.surfaceMid,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _draft = _draft.copyWith(speedMultiplier: s);
                        _videoController?.setPlaybackSpeed(s);
                      });
                      _markChanged();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextControls() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textInputController,
                  style: GoogleFonts.inter(color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter text overlay...',
                    hintStyle: GoogleFonts.inter(color: context.textSecondary),
                    filled: true,
                    fillColor: context.surfaceMid,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveOrAddTextOverlay,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
                child: Text('Add Text', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quick Font Styles
          Row(
            children: [
              Text('Color: ', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12)),
              _colorCircle(0xFFFFFFFF),
              _colorCircle(0xFF0C4FA8),
              _colorCircle(0xFFFF2D87),
              _colorCircle(0xFFFFD700),
              const Spacer(),
              if (_selectedTextOverlayId != null)
                TextButton.icon(
                  icon: Icon(Icons.delete, color: AppColors.brandPink, size: 16),
                  label: Text('Delete', style: TextStyle(color: AppColors.brandPink, fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      _draft = _draft.copyWith(
                        textOverlays: _draft.textOverlays.where((t) => t.id != _selectedTextOverlayId).toList(),
                      );
                      _selectedTextOverlayId = null;
                      _textInputController.clear();
                    });
                    _markChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorCircle(int hex) {
    return GestureDetector(
      onTap: () {
        if (_selectedTextOverlayId != null) {
          setState(() {
            _draft = _draft.copyWith(
              textOverlays: _draft.textOverlays.map((t) {
                return t.id == _selectedTextOverlayId ? t.copyWith(colorHex: hex) : t;
              }).toList(),
            );
          });
          _markChanged();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Color(hex),
          shape: BoxShape.circle,
          border: Border.all(color: context.border, width: 1.5),
        ),
      ),
    );
  }

  void _saveOrAddTextOverlay() {
    final text = _textInputController.text.trim();
    if (text.isEmpty) return;

    if (_selectedTextOverlayId != null) {
      // Update existing
      setState(() {
        _draft = _draft.copyWith(
          textOverlays: _draft.textOverlays.map((t) {
            return t.id == _selectedTextOverlayId ? t.copyWith(text: text) : t;
          }).toList(),
        );
      });
    } else {
      // Add new
      final newLayer = OneovaTextOverlay(
        id: const Uuid().v4(),
        text: text,
        x: 0.35,
        y: 0.45,
        colorHex: 0xFFFFFFFF,
        backgroundColorHex: 0x990C4FA8, // Brand Blue semi-transparent pill
      );
      setState(() {
        _draft = _draft.copyWith(textOverlays: [..._draft.textOverlays, newLayer]);
        _selectedTextOverlayId = newLayer.id;
      });
    }
    _textInputController.clear();
    _markChanged();
  }

  Widget _buildAudioControls() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.mic, color: context.textSecondary, size: 18),
              const SizedBox(width: 8),
              Text('Original Microphone: ', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _audioMix.originalVolume,
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppColors.brandBlue,
                  onChanged: (val) {
                    setState(() {
                      _audioMix = _audioMix.copyWith(originalVolume: val);
                      _videoController?.setVolume(val);
                    });
                    _markChanged();
                  },
                ),
              ),
              Text('${(_audioMix.originalVolume * 100).toInt()}%', style: TextStyle(color: context.textSecondary, fontSize: 12)),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.music_note, color: AppColors.brandPink, size: 18),
              const SizedBox(width: 8),
              Text('Background Music: ', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _audioMix.musicVolume,
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppColors.brandPink,
                  onChanged: (val) {
                    setState(() {
                      _audioMix = _audioMix.copyWith(musicVolume: val);
                    });
                    _markChanged();
                  },
                ),
              ),
              Text('${(_audioMix.musicVolume * 100).toInt()}%', style: TextStyle(color: context.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorScienceControls() {
    final presets = [
      {'id': 'default', 'label': 'Rec.709 Standard'},
      {'id': 'cinematic', 'label': 'Oneova Film Teal'},
      {'id': 'warm_gold', 'label': 'Sunset Glow'},
      {'id': 'cyber_pink', 'label': 'Oneova Cyber'},
      {'id': 'noir', 'label': 'BMD Noir Film'},
      {'id': 'vibrant', 'label': 'Vibrant Boost'},
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Film LUT Presets',
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((p) {
                final isSelected = _colorGrade.lutPreset == p['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(p['label']!, style: GoogleFonts.inter(color: isSelected ? Colors.white : AppColors.textSecondary, fontSize: 11)),
                    selected: isSelected,
                    selectedColor: AppColors.brandBlue,
                    backgroundColor: context.surfaceMid,
                    onSelected: (val) {
                      setState(() {
                        _colorGrade = _colorGrade.copyWith(lutPreset: p['id']);
                      });
                      _markChanged();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _sliderRow('Exposure', _colorGrade.exposure, -1.0, 1.0, (v) {
            setState(() => _colorGrade = _colorGrade.copyWith(exposure: v));
            _markChanged();
          }),
          _sliderRow('Contrast', _colorGrade.contrast, 0.5, 1.5, (v) {
            setState(() => _colorGrade = _colorGrade.copyWith(contrast: v));
            _markChanged();
          }),
          _sliderRow('Saturation', _colorGrade.saturation, 0.0, 2.0, (v) {
            setState(() => _colorGrade = _colorGrade.copyWith(saturation: v));
            _markChanged();
          }),
          _sliderRow('Warmth', _colorGrade.temperature, -1.0, 1.0, (v) {
            setState(() => _colorGrade = _colorGrade.copyWith(temperature: v));
            _markChanged();
          }),
          _sliderRow('Tint', _colorGrade.tint, -1.0, 1.0, (v) {
            setState(() => _colorGrade = _colorGrade.copyWith(tint: v));
            _markChanged();
          }),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _runAiColorNormalize,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 15, color: AppColors.brandPink),
                label: Text('AI Auto Balance', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _colorGrade = const OneovaColorGrade(
                      exposure: 0.0,
                      contrast: 1.0,
                      saturation: 1.0,
                      temperature: 0.0,
                      tint: 0.0,
                      lutPreset: 'default',
                    );
                  });
                  _markChanged();
                },
                child: Text('Reset Color', style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.brandBlue,
            onChanged: onChanged,
          ),
        ),
        Text(value.toStringAsFixed(2), style: TextStyle(color: context.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _buildAiSuiteControls() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiActionCard(
            icon: Icons.palette,
            title: 'Cinematic quick grade',
            subtitle: 'Exposure +0.1 · contrast 1.15 · saturation 1.1 · Oneova Film Teal',
            onTap: _runAiColorNormalize,
          ),
          const SizedBox(height: 8),
          _aiActionCard(
            icon: Icons.wb_sunny_rounded,
            title: 'Golden Hour Sunlight',
            subtitle: 'Warmth +0.35 · contrast 1.10 · saturation 1.18 · Sunset Glow LUT',
            onTap: () {
              setState(() {
                _colorGrade = _colorGrade.copyWith(
                  exposure: 0.08,
                  contrast: 1.10,
                  saturation: 1.18,
                  temperature: 0.35,
                  tint: 0.05,
                  lutPreset: 'warm_gold',
                );
              });
              _markChanged();
            },
          ),
          const SizedBox(height: 8),
          _aiActionCard(
            icon: Icons.bolt_rounded,
            title: 'Oneova Cyber Neon',
            subtitle: 'Cool shadows · magenta highlights · contrast 1.22 · Oneova Cyber LUT',
            onTap: () {
              setState(() {
                _colorGrade = _colorGrade.copyWith(
                  exposure: 0.04,
                  contrast: 1.22,
                  saturation: 1.32,
                  temperature: -0.22,
                  tint: 0.28,
                  lutPreset: 'cyber_pink',
                );
              });
              _markChanged();
            },
          ),
          const SizedBox(height: 8),
          _aiActionCard(
            icon: Icons.compare_arrows_rounded,
            title: 'Align & Stretch Clip to Full Duration',
            subtitle: 'Snaps start to 0:00 and extends clip across full timeline',
            onTap: () {
              final fullSec = (_totalDuration.inMilliseconds / 1000.0).clamp(1.0, 600.0);
              setState(() {
                _draft = _draft.copyWith(
                  trimStartSeconds: 0.0,
                  trimEndSeconds: fullSec,
                  durationSeconds: fullSec,
                );
              });
              _markChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _aiActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.brandPink, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(subtitle, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AI Suite Implementations
  // ──────────────────────────────────────────────────────────────────────────

  void _runAiColorNormalize() {
    HapticFeedback.mediumImpact();
    setState(() {
      _colorGrade = _colorGrade.copyWith(
        exposure: 0.1,
        contrast: 1.15,
        saturation: 1.1,
        lutPreset: 'cinematic',
      );
    });
    _markChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cinematic grade applied', style: GoogleFonts.inter()),
        backgroundColor: AppColors.brandPink,
      ),
    );
  }

  Future<void> _importNewClipToSequence() async {
    HapticFeedback.lightImpact();
    final clip = await OneovaFilePicker.pickSingleClip(
      context,
      mode: OneovaFilePickerMode.videos,
      title: 'Import Clip into Sequence',
      actionLabel: 'Add to Sequence',
    );
    if (clip != null && mounted) {
      setState(() {
        _draft = _draft.copyWith(
          mediaPath: clip.file.path,
          isVideo: clip.isVideo,
          trimStartSeconds: clip.startSeconds,
          trimEndSeconds: clip.endSeconds,
          speedMultiplier: clip.speed,
          aspectRatio: clip.aspectRatio,
          durationSeconds: clip.totalDurationSeconds,
        );
      });
      _initVideoPlayer();
      _markChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'New clip imported to sequence (${clip.trimmedDuration.toStringAsFixed(1)}s)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: AppColors.brandBlue,
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Tablet/Landscape Components (Oneova Studio Style)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildStudioMediaPool() {
    return Container(
      color: context.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_special, color: AppColors.brandBlue, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'MEDIA POOL',
                    style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
              InkWell(
                onTap: _importNewClipToSequence,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.brandPink, width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 13, color: AppColors.brandPink),
                      const SizedBox(width: 3),
                      Text(
                        'Import Clip',
                        style: GoogleFonts.inter(color: context.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.brandBlue),
            ),
            child: Row(
              children: [
                Icon(_draft.isVideo ? Icons.movie : Icons.photo, color: context.textSecondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _draft.mediaPath.split('/').last,
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ACTIVE LAYERS',
            style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w700, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _layerTile('V1 Video Track', Icons.videocam, AppColors.brandBlue),
                _layerTile('A1 Mic Audio', Icons.mic, AppColors.brandBlue),
                _layerTile('A2 Soundtrack', Icons.music_note, AppColors.brandPink),
                for (var text in _draft.textOverlays)
                  _layerTile('T: ${text.text}', Icons.title, context.textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerTile(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.surfaceMid.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11), maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiTrackTimeline() {
    return Container(
      height: 140,
      color: context.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TIMELINE', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text('${_draft.speedMultiplier}x Speed | Magnetic Snap: ON', style: GoogleFonts.inter(color: context.textMuted, fontSize: 10)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _importNewClipToSequence,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.brandBlue, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 10, color: context.textPrimary),
                          const SizedBox(width: 2),
                          Text(
                            '+ Clip',
                            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 9.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _timelineTrackBar('V1', AppColors.brandBlue, 'Primary Footage'),
                  _timelineTrackBar('T1', Colors.amberAccent, 'Text Layers'),
                  _timelineTrackBar('A1', AppColors.brandPink, 'Audio Waveform'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineTrackBar(String label, Color color, String desc) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(label, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Container(
            height: 18,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(desc, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 9)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOneovaInspectorDeck() {
    return Container(
      color: context.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONEOVA COLOR & INSPECTOR',
            style: GoogleFonts.inter(color: AppColors.brandPink, fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildColorScienceControls(),
                  Divider(color: context.border, height: 24),
                  _buildAudioControls(),
                  Divider(color: context.border, height: 24),
                  _buildAiSuiteControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Utilities & Export
  // ──────────────────────────────────────────────────────────────────────────
  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$m:$s.$ms';
  }

  Future<void> _saveToDevice() async {
    HapticFeedback.lightImpact();
    final file = File(_draft.mediaPath);
    if (await file.exists()) {
      await SharePlus.instance.share(ShareParams(files: [XFile(_draft.mediaPath)], text: _draft.title));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Media ready to save to camera roll or share.', style: GoogleFonts.inter()),
            backgroundColor: AppColors.brandBlue,
          ),
        );
      }
    }
  }

  void _onExportOrPublish() async {
    await _persistDraft(silent: true);
    if (!mounted) return;

    ExportingProgressSheet.show(
      context: context,
      mediaPath: _draft.mediaPath,
      isVideo: _draft.isVideo,
      title: _draft.title,
      onProceedToPost: () {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MediaPreviewScreen(
              mediaPath: _draft.mediaPath,
              isVideo: _draft.isVideo,
            ),
          ),
        );
      },
    );
  }
}
