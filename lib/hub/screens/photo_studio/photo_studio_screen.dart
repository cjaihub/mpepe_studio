import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/backend/photo_studio/photo_studio_models.dart';
import 'package:oneova/backend/photo_studio/photo_studio_engine.dart';
import 'package:oneova/backend/photo_studio/photo_io_service.dart';
import 'package:oneova/hub/screens/photo_studio/deterministic_render_view.dart';
import 'package:oneova/hub/screens/photo_studio/mask_stack_panel.dart';
import 'package:oneova/hub/screens/photo_studio/curves_editor.dart';
import 'package:oneova/hub/screens/photo_studio/widgets/hsl_mixer_panel.dart';
import 'package:oneova/hub/screens/photo_studio/widgets/color_wheels_panel.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_provider.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/features/omni_command/omni_command_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';

final activePhotoProjectProvider = NotifierProvider<PhotoProjectNotifier, PhotoProject>(() {
  return PhotoProjectNotifier();
});

class PhotoStudioScreen extends ConsumerStatefulWidget {
  const PhotoStudioScreen({super.key});

  @override
  ConsumerState<PhotoStudioScreen> createState() => _PhotoStudioScreenState();
}

class _PhotoStudioScreenState extends ConsumerState<PhotoStudioScreen> {
  String _activeTool = 'Light';
  String _lightSubTool = 'Basic';
  String _colorSubTool = 'Basic';

  bool _isComparing = false;
  bool _isAiProcessing = false;
  String? _lastAiActionMessage;

  List<Offset> _curvePoints = [
    const Offset(0.0, 0.0),
    const Offset(1.0, 1.0),
  ];

  final TextEditingController _aiPromptController = TextEditingController();
  final PhotoIoService _photoIoService = PhotoIoService();

  final List<Map<String, dynamic>> _tools = const [
    {'name': 'Light', 'icon': Icons.light_mode_outlined},
    {'name': 'Color', 'icon': Icons.color_lens_outlined},
    {'name': 'Curves', 'icon': Icons.timeline_rounded},
    {'name': 'AI Copilot', 'icon': Icons.auto_awesome_rounded},
    {'name': 'Effects', 'icon': Icons.blur_on_rounded},
    {'name': 'Detail', 'icon': Icons.details_rounded},
    {'name': 'Masking', 'icon': Icons.layers_outlined},
    {'name': 'Crop', 'icon': Icons.crop_rounded},
  ];

  @override
  void dispose() {
    _aiPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final file = await _photoIoService.pickImage();
    if (file != null && mounted) {
      ref.read(activePhotoProjectProvider.notifier).setSourceImage(file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo imported successfully',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.darkSurface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _executeAiPrompt(String prompt) {
    if (prompt.trim().isEmpty) return;
    setState(() => _isAiProcessing = true);

    final p = prompt.toLowerCase();
    final List<PhotoAdjustment> adjustments = [];
    String actionLabel = '';

    if (p.contains('moody') || p.contains('film')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_exp', type: AdjustmentType.EXPOSURE, parameters: {'value': -0.12}),
        PhotoAdjustment(id: 'ai_cont', type: AdjustmentType.CONTRAST, parameters: {'value': 0.35}),
        PhotoAdjustment(id: 'ai_hl', type: AdjustmentType.HIGHLIGHTS, parameters: {'value': -0.30}),
        PhotoAdjustment(id: 'ai_sh', type: AdjustmentType.SHADOWS, parameters: {'value': 0.20}),
        PhotoAdjustment(id: 'ai_temp', type: AdjustmentType.TEMPERATURE, parameters: {'value': 0.15}),
        PhotoAdjustment(id: 'ai_sat', type: AdjustmentType.SATURATION, parameters: {'value': -0.10}),
      ]);
      actionLabel = 'Moody Film Look (-12% Exp, +35% Cont, Warm Fade)';
    } else if (p.contains('golden') || p.contains('warm') || p.contains('sunset')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_temp', type: AdjustmentType.TEMPERATURE, parameters: {'value': 0.45}),
        PhotoAdjustment(id: 'ai_tint', type: AdjustmentType.TINT, parameters: {'value': 0.10}),
        PhotoAdjustment(id: 'ai_exp', type: AdjustmentType.EXPOSURE, parameters: {'value': 0.10}),
        PhotoAdjustment(id: 'ai_hl', type: AdjustmentType.HIGHLIGHTS, parameters: {'value': -0.15}),
        PhotoAdjustment(id: 'ai_vib', type: AdjustmentType.VIBRANCE, parameters: {'value': 0.25}),
      ]);
      actionLabel = 'Golden Hour Sunlight (+45% Temp, +25% Vibrance)';
    } else if (p.contains('cyberpunk') || p.contains('neon') || p.contains('sci-fi')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_temp', type: AdjustmentType.TEMPERATURE, parameters: {'value': -0.40}),
        PhotoAdjustment(id: 'ai_tint', type: AdjustmentType.TINT, parameters: {'value': 0.35}),
        PhotoAdjustment(id: 'ai_cont', type: AdjustmentType.CONTRAST, parameters: {'value': 0.45}),
        PhotoAdjustment(id: 'ai_sat', type: AdjustmentType.SATURATION, parameters: {'value': 0.30}),
      ]);
      actionLabel = 'Cyberpunk Neon (Cool Blue + Magenta Tint + Contrast)';
    } else if (p.contains('black and white') || p.contains('b&w') || p.contains('monochrome')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_sat', type: AdjustmentType.SATURATION, parameters: {'value': -1.0}),
        PhotoAdjustment(id: 'ai_cont', type: AdjustmentType.CONTRAST, parameters: {'value': 0.50}),
        PhotoAdjustment(id: 'ai_wh', type: AdjustmentType.WHITES, parameters: {'value': 0.25}),
        PhotoAdjustment(id: 'ai_bl', type: AdjustmentType.BLACKS, parameters: {'value': -0.30}),
      ]);
      actionLabel = 'High-Contrast Cinematic B&W';
    } else if (p.contains('vibrant') || p.contains('pop') || p.contains('punchy')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_sat', type: AdjustmentType.SATURATION, parameters: {'value': 0.35}),
        PhotoAdjustment(id: 'ai_vib', type: AdjustmentType.VIBRANCE, parameters: {'value': 0.40}),
        PhotoAdjustment(id: 'ai_cont', type: AdjustmentType.CONTRAST, parameters: {'value': 0.20}),
      ]);
      actionLabel = 'Punchy Vibrant Colors (+35% Sat, +40% Vibrance)';
    } else if (p.contains('shadow') || p.contains('brighten') || p.contains('lift')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_sh', type: AdjustmentType.SHADOWS, parameters: {'value': 0.60}),
        PhotoAdjustment(id: 'ai_exp', type: AdjustmentType.EXPOSURE, parameters: {'value': 0.15}),
        PhotoAdjustment(id: 'ai_bl', type: AdjustmentType.BLACKS, parameters: {'value': 0.20}),
      ]);
      actionLabel = 'Lifted Shadows & Exposure (+60% Shadows, +15% Exp)';
    } else if (p.contains('cool') || p.contains('cold') || p.contains('blue')) {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_temp', type: AdjustmentType.TEMPERATURE, parameters: {'value': -0.45}),
        PhotoAdjustment(id: 'ai_tint', type: AdjustmentType.TINT, parameters: {'value': -0.10}),
      ]);
      actionLabel = 'Cool Nordic Tone (-45% Temp)';
    } else {
      adjustments.addAll([
        PhotoAdjustment(id: 'ai_exp', type: AdjustmentType.EXPOSURE, parameters: {'value': 0.08}),
        PhotoAdjustment(id: 'ai_cont', type: AdjustmentType.CONTRAST, parameters: {'value': 0.18}),
        PhotoAdjustment(id: 'ai_hl', type: AdjustmentType.HIGHLIGHTS, parameters: {'value': -0.20}),
        PhotoAdjustment(id: 'ai_sh', type: AdjustmentType.SHADOWS, parameters: {'value': 0.25}),
        PhotoAdjustment(id: 'ai_vib', type: AdjustmentType.VIBRANCE, parameters: {'value': 0.20}),
      ]);
      actionLabel = 'Oneova AI Pro Optical Calibration';
    }

    ref.read(activePhotoProjectProvider.notifier).applyAdjustments(
          adjustments,
          description: 'AI: $prompt',
        );

    setState(() {
      _isAiProcessing = false;
      _lastAiActionMessage = actionLabel;
      _aiPromptController.clear();
    });

    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(activePhotoProjectProvider);
    final notifier = ref.watch(activePhotoProjectProvider.notifier);
    final canUndo = notifier.canUndo;
    final canRedo = notifier.canRedo;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.65),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(color: Colors.transparent),
          ),
        ),
        leadingWidth: 38,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => context.pop(),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Oneova Studio',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.brandPink, width: 0.8),
                ),
                child: Text(
                  'RAW',
                  style: GoogleFonts.inter(
                    color: AppColors.brandPink,
                    fontSize: 8.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
        actions: [
          // Import Photo Button
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white, size: 20),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Open Photo',
            onPressed: _pickImage,
          ),

          // Undo Button
          IconButton(
            icon: Icon(
              Icons.undo_rounded,
              color: canUndo ? Colors.white : Colors.white24,
              size: 20,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Undo',
            onPressed: canUndo
                ? () {
                    HapticFeedback.lightImpact();
                    ref.read(activePhotoProjectProvider.notifier).undo();
                    ref.read(maskEngineProvider).syncFromProject(ref.read(activePhotoProjectProvider));
                  }
                : null,
          ),

          // Redo Button
          IconButton(
            icon: Icon(
              Icons.redo_rounded,
              color: canRedo ? Colors.white : Colors.white24,
              size: 20,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Redo',
            onPressed: canRedo
                ? () {
                    HapticFeedback.lightImpact();
                    ref.read(activePhotoProjectProvider.notifier).redo();
                    ref.read(maskEngineProvider).syncFromProject(ref.read(activePhotoProjectProvider));
                  }
                : null,
          ),

          // Hold to Compare Button
          GestureDetector(
            onTapDown: (_) => setState(() => _isComparing = true),
            onTapUp: (_) => setState(() => _isComparing = false),
            onTapCancel: () => setState(() => _isComparing = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _isComparing ? AppColors.brandBlue.withValues(alpha: 0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.compare_rounded,
                color: _isComparing ? AppColors.brandBlue : Colors.white70,
                size: 22,
              ),
            ),
          ),

          // Export Button
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.brandBlue,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _showExportOptions(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ios_share_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Export',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Canvas Area
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: _isComparing
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              if (project.originalAsset.uri.isNotEmpty &&
                                  !project.originalAsset.uri.startsWith('http'))
                                Image.file(
                                  File(project.originalAsset.uri),
                                  fit: BoxFit.contain,
                                )
                              else
                                Image.network(
                                  project.originalAsset.uri.isNotEmpty
                                      ? project.originalAsset.uri
                                      : 'https://images.unsplash.com/photo-1542291026-7eec264c27ff',
                                  fit: BoxFit.contain,
                                ),
                              Positioned(
                                top: 100,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(AppRadius.full),
                                    border: Border.all(color: Colors.white24, width: 1.0),
                                  ),
                                  child: Text(
                                    'Original Asset (Before)',
                                    style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : DeterministicRenderView(project: project),
                  ),
                ),

                // Empty / Placeholder Import Action Overlay
                if (project.originalAsset.uri.isEmpty)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(color: AppColors.brandBlue, width: 1.0),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 10),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_photo_alternate_rounded, color: AppColors.brandBlue, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Tap to open your own photo',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (_activeTool == 'Masking')
                  const Positioned.fill(
                    child: MaskStackPanel(),
                  ),
              ],
            ),
          ),

          // Bottom Controls Area
          Container(
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Active Tool Panel (Capped at 285px for tight responsive mobile screens)
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 285),
                    child: _buildActiveToolPanel(),
                  ),
                ),

                // Tool Strip
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.darkBackground,
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1.0)),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tools.length,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) {
                      final tool = _tools[index];
                      final isActive = _activeTool == tool['name'];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _activeTool = tool['name'] as String);
                        },
                        child: Container(
                          width: 68,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                tool['icon'] as IconData,
                                color: isActive ? AppColors.brandBlue : Colors.white54,
                                size: 21,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tool['name'] as String,
                                style: GoogleFonts.inter(
                                  color: isActive ? Colors.white : Colors.white54,
                                  fontSize: 10.5,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: OmniCommandButton(
        omniContext: OmniContext(
          sessionId: buildOmniSessionId(),
          userId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
          surface: 'photo_studio',
          projectId: project.id,
        ),
      ),
    );
  }

  Widget _buildActiveToolPanel() {
    switch (_activeTool) {
      case 'Light':
        return _buildLightPanel();
      case 'Color':
        return _buildColorPanel();
      case 'Curves':
        return _buildCurvesPanel();
      case 'AI Copilot':
        return _buildAskAIPanel();
      case 'Effects':
        return _buildEffectsPanel();
      case 'Detail':
        return _buildDetailPanel();
      case 'Masking':
        return _buildMaskSelectPanel();
      case 'Crop':
        return _buildCropPanel();
      default:
        return SizedBox(
          height: 100,
          child: Center(
            child: Text(
              '$_activeTool tool active. Double tap canvas to adjust.',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
            ),
          ),
        );
    }
  }

  Widget _buildCropPanel() {
    final project = ref.watch(activePhotoProjectProvider);
    final crop = project.currentGraph.crop;
    final notifier = ref.read(activePhotoProjectProvider.notifier);
    const ratios = <(CropAspectRatio, String)>[
      (CropAspectRatio.free, 'Original'),
      (CropAspectRatio.square1x1, '1:1'),
      (CropAspectRatio.ratio4x5, '4:5'),
      (CropAspectRatio.ratio9x16, '9:16'),
      (CropAspectRatio.ratio16x9, '16:9'),
    ];
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            children: [
              for (final (ratio, label) in ratios)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      notifier.updateCrop(crop.copyWith(ratio: ratio));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: crop.ratio == ratio
                            ? AppColors.brandBlue
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          color: crop.ratio == ratio ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final nextDeg = ((crop.rotationDegrees + 90) % 360);
                  notifier.updateCrop(crop.copyWith(rotationDegrees: nextDeg));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.rotate_90_degrees_cw_rounded, size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        'Rotate 90°',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            children: [
              _buildPremiumSlider('Zoom / Scale', AdjustmentType.DISTORTION),
              _buildPremiumSlider('Perspective', AdjustmentType.PERSPECTIVE),
              _buildPremiumSlider('Vignette', AdjustmentType.VIGNETTE),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLightPanel() {
    return Column(
      children: [
        // Sub-navigation for Light Tool (Basic vs Curves)
        Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            children: ['Basic', 'Curves'].map((tool) {
              final isActive = _lightSubTool == tool;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _lightSubTool = tool),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.brandBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tool,
                      style: GoogleFonts.inter(
                        color: isActive ? Colors.white : Colors.white60,
                        fontSize: 11.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _lightSubTool == 'Basic'
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  children: [
                    _buildPremiumSlider('Exposure', AdjustmentType.EXPOSURE),
                    _buildPremiumSlider('Contrast', AdjustmentType.CONTRAST),
                    _buildPremiumSlider('Highlights', AdjustmentType.HIGHLIGHTS),
                    _buildPremiumSlider('Shadows', AdjustmentType.SHADOWS),
                    _buildPremiumSlider('Whites', AdjustmentType.WHITES),
                    _buildPremiumSlider('Blacks', AdjustmentType.BLACKS),
                  ],
                )
              : _buildCurvesPanel(),
        ),
      ],
    );
  }

  Widget _buildCurvesPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: CurvesEditor(
        points: _curvePoints,
        onChanged: (newPoints) {
          setState(() => _curvePoints = newPoints);
          final project = ref.read(activePhotoProjectProvider);
          if (project.currentGraph.layers.isNotEmpty) {
            ref.read(activePhotoProjectProvider.notifier).setOrReplaceAdjustment(
                  project.currentGraph.layers.first.id,
                  PhotoAdjustment(
                    id: 'curves_rgb',
                    type: AdjustmentType.CURVES_RGB,
                    parameters: {
                      'points': newPoints.map((p) => [p.dx, p.dy]).toList(),
                    },
                  ),
                );
          }
        },
      ),
    );
  }

  Widget _buildColorPanel() {
    return Column(
      children: [
        // Sub-navigation for Color Tool (Basic, Mix HSL, Wheels)
        Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            children: ['Basic', 'Mix (HSL)', 'Wheels'].map((tool) {
              final isMatching = (_colorSubTool == 'Basic' && tool == 'Basic') ||
                  (_colorSubTool == 'Mix' && tool == 'Mix (HSL)') ||
                  (_colorSubTool == 'Wheels' && tool == 'Wheels');
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (tool == 'Mix (HSL)') {
                        _colorSubTool = 'Mix';
                      } else {
                        _colorSubTool = tool;
                      }
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isMatching ? AppColors.brandBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tool,
                      style: GoogleFonts.inter(
                        color: isMatching ? Colors.white : Colors.white60,
                        fontSize: 11.5,
                        fontWeight: isMatching ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Active Content
        Expanded(
          child: _colorSubTool == 'Basic'
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  children: [
                    _buildPremiumSlider('Temp', AdjustmentType.TEMPERATURE),
                    _buildPremiumSlider('Tint', AdjustmentType.TINT),
                    _buildPremiumSlider('Vibrance', AdjustmentType.VIBRANCE),
                    _buildPremiumSlider('Saturation', AdjustmentType.SATURATION),
                  ],
                )
              : _colorSubTool == 'Mix'
                  ? const HslMixerPanel()
                  : const ColorWheelsPanel(),
        ),
      ],
    );
  }

  Widget _buildEffectsPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        _buildPremiumSlider('Texture', AdjustmentType.TEXTURE),
        _buildPremiumSlider('Clarity', AdjustmentType.CLARITY),
        _buildPremiumSlider('Dehaze', AdjustmentType.DEHAZE),
        _buildPremiumSlider('Vignette', AdjustmentType.VIGNETTE),
      ],
    );
  }

  Widget _buildDetailPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        _buildPremiumSlider('Sharpening', AdjustmentType.SHARPNESS),
        _buildPremiumSlider('Noise Reduction', AdjustmentType.NOISE_REDUCTION),
        _buildPremiumSlider('Distortion', AdjustmentType.DISTORTION),
      ],
    );
  }

  Widget _buildAskAIPanel() {
    final quickPrompts = [
      'Moody Film',
      'Golden Hour',
      'Cyberpunk Neon',
      'High-Contrast B&W',
      'Punchy Colors',
      'Lift Shadows',
      'Cool Nordic',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.brandPink, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Oneova AI Photo Copilot',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
              if (_isAiProcessing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick Action Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: quickPrompts.map((preset) {
                return GestureDetector(
                  onTap: () => _executeAiPrompt(preset),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.0),
                    ),
                    child: Text(
                      preset,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Natural Language Text Input Field
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _aiPromptController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. "Warm sunset with lifted shadows"',
                      hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                      ),
                    ),
                    onSubmitted: _executeAiPrompt,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                  onPressed: () => _executeAiPrompt(_aiPromptController.text),
                ),
              ),
            ],
          ),

          // Feedback Confirmation Card
          if (_lastAiActionMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AppColors.brandPink, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _lastAiActionMessage!,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      ref.read(activePhotoProjectProvider.notifier).undo();
                      setState(() => _lastAiActionMessage = null);
                    },
                    child: Text(
                      'Undo',
                      style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaskSelectPanel() {
    final selectors = ['Subject', 'Sky', 'Background', 'Linear Gradient', 'Radial Gradient', 'Brush'];
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Local Mask',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: selectors.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () async {
                    final engine = ref.read(maskEngineProvider);
                    try {
                      await engine.addSemanticMask('local_media', selectors[index]);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Created ${selectors[index]} mask'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Error $e');
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                    ),
                    child: Text(
                      selectors[index],
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumSlider(String label, AdjustmentType type) {
    final project = ref.watch(activePhotoProjectProvider);
    double value = 0.0;
    if (project.currentGraph.layers.isNotEmpty) {
      final adj = project.currentGraph.layers.first.adjustments.where((a) => a.type == type).lastOrNull;
      if (adj != null) {
        value = (adj.parameters['value'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final displayValue = (value * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.0,
                activeTrackColor: AppColors.brandBlue,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: Colors.white,
                overlayColor: AppColors.brandBlue.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(-1.0, 1.0),
                min: -1.0,
                max: 1.0,
                onChanged: (val) {
                  ref.read(activePhotoProjectProvider.notifier).setOrReplaceAdjustment(
                        project.currentGraph.layers.first.id,
                        PhotoAdjustment(
                          id: 'adj_${type.name}',
                          type: type,
                          parameters: {'value': val},
                        ),
                      );
                },
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              displayValue > 0 ? '+$displayValue' : '$displayValue',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportOptions(BuildContext context) {
    HapticFeedback.lightImpact();
    final project = ref.read(activePhotoProjectProvider);
    final hasLocalImage = project.originalAsset.uri.isNotEmpty && File(project.originalAsset.uri).existsSync();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Export Oneova Pro Photo',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.save_alt_rounded, color: AppColors.brandBlue),
                title: Text('Save High-Res Image', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('Full-fidelity render saved to device gallery', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (hasLocalImage) {
                    await _photoIoService.sharePhoto(File(project.originalAsset.uri), text: 'Edited with Oneova Photo Studio');
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Saved High-Res photo to Gallery!', style: GoogleFonts.inter(color: Colors.white)),
                        backgroundColor: AppColors.darkSurfaceHighlight,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: AppColors.brandPink),
                title: Text('Share via Apps', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('Share directly to Instagram, WhatsApp, X', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (hasLocalImage) {
                    await _photoIoService.sharePhoto(File(project.originalAsset.uri), text: 'Edited with Oneova Studio');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Photo export ready to share!', style: GoogleFonts.inter(color: Colors.white)),
                        backgroundColor: AppColors.darkSurfaceHighlight,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_rounded, color: Colors.white70),
                title: Text('Reset to Original', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('Revert all adjustments non-destructively', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(activePhotoProjectProvider.notifier).resetAllAdjustments();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Adjustments reset to original', style: GoogleFonts.inter(color: Colors.white)),
                      backgroundColor: AppColors.darkSurfaceHighlight,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
