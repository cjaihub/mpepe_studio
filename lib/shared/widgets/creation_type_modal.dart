import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../../backend/projects/models/oneova_draft_model.dart';
import '../../backend/projects/services/oneova_draft_engine.dart';
import '../../create/pro_workstation_editor_screen.dart';
import 'all_tools_modal.dart';

class CreationTypeModal extends ConsumerStatefulWidget {
  const CreationTypeModal({super.key});

  static void show(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background(context),
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => const CreationTypeModal(),
    );
  }

  @override
  ConsumerState<CreationTypeModal> createState() => _CreationTypeModalState();
}

class _CreationTypeModalState extends ConsumerState<CreationTypeModal> {
  int _selectedTabIndex = 0; // 0: Studio, 1: Projects/Drafts, 2: Templates, 3: Library
  String _selectedCategory = 'All';

  final List<String> _categories = const [
    'All',
    'Video & Camera',
    'Photo & AI',
    'Cinema Live',
    'Hardware & PC',
  ];

  late final List<_StudioToolSpec> _allTools = [
    _StudioToolSpec(
      title: 'Studio editor',
      subtitle: 'Edit & Post',
      category: 'Video & Camera',
      icon: Icons.movie_edit,
      route: '/create/studio',
      badge: 'NEW',
      description:
          'Edit videos and photos from your gallery: trim, split, speed, filters, adjust, text, captions, music, then export and post.',
      highlights: const [
        'Multi-clip timeline with undo / redo',
        'Filters, adjust, crop, text, stickers, captions, audio',
        'Export 480p to 4K, then post or share to your story',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Create video',
      subtitle: 'Record & Reel',
      category: 'Video & Camera',
      icon: Icons.videocam_rounded,
      route: '/create/camera?mode=video',
      badge: 'REC',
      description:
          'Record executive-grade videos with real-time film grading, audio waveforms, teleprompter, and pre-import clip trimmer.',
      highlights: const [
        'Studio multi-resolution camera recording',
        'Built-in clip trimmer & aspect framing',
        'Seamless sequence ingestion into Pro Workstation',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Create photo',
      subtitle: 'Snap & Filter',
      category: 'Photo & AI',
      icon: Icons.camera_alt_rounded,
      route: '/create/camera?mode=photo',
      badge: 'CAM',
      description:
          'Capture executive-grade photos with studio optical framing, real-time filters, and pro portrait grading.',
      highlights: const [
        'Ultra-high resolution photo capture',
        'Studio beauty & portrait retouching',
        'Seamless post & story publishing',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Go Live',
      subtitle: 'Full-screen LIVE',
      category: 'Cinema Live',
      icon: Icons.sensors_rounded,
      route: '/live/broadcast',
      badge: 'LIVE',
      description:
          'Go live full-screen to your followers. They get notified the moment you start and can comment, like, send gifts and request to join.',
      highlights: const [
        'Followers notified instantly',
        'Comments, hearts & gifts in real time',
        'Viewers can request to join',
      ],
      accentColor: AppColors.brandPink,
    ),
    _StudioToolSpec(
      title: 'Live Studio',
      subtitle: 'Corporate video windows',
      category: 'Cinema Live',
      icon: Icons.view_quilt_rounded,
      route: '/live/broadcast?mode=studio',
      badge: 'STUDIO',
      description:
          'Host a broadcast studio: you on the center stage, guests as video windows on the studio walls. Built for panels, briefings and business shows.',
      highlights: const [
        'Center stage plus up to 6 wall windows',
        'Executive Suite and other studio scenes',
        'Guests join by request, you approve',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Game Live',
      subtitle: 'Stream your phone game',
      category: 'Cinema Live',
      icon: Icons.sports_esports,
      route: '/live/broadcast?mode=gaming',
      badge: 'GAME',
      description:
          'Go live while you play any game on your phone. Your screen is the main stage, your camera sits in a bubble, and the live keeps going while you are in the game.',
      highlights: const [
        'Your game screen on the center stage',
        'Camera bubble you can drag or hide',
        'Viewers comment, love and share as you play',
      ],
      accentColor: AppColors.brandPink,
    ),
    _StudioToolSpec(
      title: 'AutoCut AI',
      subtitle: 'Smart Montage',
      category: 'PiP & Video',
      icon: Icons.movie_creation_outlined,
      route: '/video/dashboard',
      description:
          'Automatically detect beats, silence, and highlights to slice raw video into rhythmic viral reels in seconds.',
      highlights: const [
        'Beat-matched video transitions',
        'Automatic silence trimming',
        'Smart aspect-ratio reframing',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Captions',
      subtitle: 'Type or import',
      category: 'PiP & Video',
      icon: Icons.subtitles_outlined,
      route: '/create/studio',
      description:
          'Add timed captions in Studio: type them at the playhead, style them with templates, or import an .srt file.',
      highlights: const [
        'Captions burned into the exported video',
        'Caption templates for every caption at once',
        'Import SubRip (.srt) files',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Retouch',
      subtitle: 'Portrait & Beauty',
      category: 'Photo & AI',
      icon: Icons.auto_awesome_rounded,
      route: '/photo/studio',
      badge: 'AI',
      description:
          'AI facial enhancement, dynamic blemish removal, studio skin tone correction, and eye-pop illumination.',
      highlights: const [
        'Neural face sculpting',
        'Natural texture preservation',
        '1-tap executive portrait grading',
      ],
      accentColor: AppColors.brandPink,
    ),
    _StudioToolSpec(
      title: 'AI Brand',
      subtitle: 'Virtual Presenter',
      category: 'Photo & AI',
      icon: Icons.face_retouching_natural_rounded,
      route: '/ai_studio?mode=avatars',
      badge: 'PRO',
      description:
          'Create realistic AI presenter avatars for commercial ads, tutorials, and brand videos directly from text prompts.',
      highlights: const [
        'Hyper-realistic lip sync in 40+ languages',
        'Custom wardrobe & studio lighting',
        'Ova Brain script generation',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Photo Studio',
      subtitle: 'RAW Darkroom',
      category: 'Photo & AI',
      icon: Icons.image_outlined,
      route: '/photo/studio',
      description:
          'Full-fledged RAW digital darkroom with 3-way color wheels, HSL mixer, exposure curves, and localized masking.',
      highlights: const [
        'Non-destructive layer stack',
        'Hollywood 4x5 film color science',
        'Instant before/after comparison',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Control PC',
      subtitle: 'Remote Hardware',
      category: 'Hardware & PC',
      icon: Icons.desktop_windows_rounded,
      route: '/connect',
      badge: 'PRO',
      description:
          'Wirelessly control your desktop computer, send mouse gestures, trigger shortcuts, and monitor stream health from your phone.',
      highlights: const [
        'End-to-end encrypted local pairing',
        'Zero-latency trackpad & keyboard input',
        'Premiere & DaVinci timeline actuation',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Teleprompter',
      subtitle: 'Voice Scrolling',
      category: 'PiP & Video',
      icon: Icons.speed_rounded,
      route: '/video/dashboard',
      description:
          'Floating auto-scroll teleprompter that tracks your speech speed so you never forget lines while looking at the camera.',
      highlights: const [
        'Voice-paced speed tracking',
        'Mirrored glass HUD overlay',
        'Customizable text size & margin',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'Desktop Agent',
      subtitle: 'Computer Brain',
      category: 'Hardware & PC',
      icon: Icons.computer_rounded,
      route: '/desktop_agent',
      badge: 'NEW',
      description:
          'Run native macOS & Windows automation commands, compile assets, and orchestrate exports via Ova Agent.',
      highlights: const [
        'Remote command terminal',
        'Hardware thermal monitoring',
        'Autonomous workflow trigger',
      ],
      accentColor: AppColors.brandPink,
    ),
    _StudioToolSpec(
      title: 'Audio Studio',
      subtitle: 'VU Level & Sound',
      category: 'PiP & Video',
      icon: Icons.mic_none_rounded,
      route: '/create/camera',
      description:
          'Pro audio recorder with dual VU level meters, noise gate, ambient sound suppression, and stereo mix monitoring.',
      highlights: const [
        'Simulated -40 to 0 dBFS stereo VU meter',
        'Dynamic gain limiter',
        'External USB-C mic support',
      ],
      accentColor: AppColors.brandBlue,
    ),
    _StudioToolSpec(
      title: 'All tools',
      subtitle: 'Complete Catalog',
      category: 'All',
      icon: Icons.apps_rounded,
      route: 'modal://all_tools',
      description:
          'Browse the complete catalog of Oneova AI creation engines, production suites, and connected hardware utilities.',
      highlights: const [
        'Over 20+ specialized production modules',
        'Categorized workflow view',
        'Rapid one-tap launch',
      ],
      accentColor: AppColors.brandBlue,
    ),
  ];

  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    HapticFeedback.mediumImpact();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: context.border, width: 1.0),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.logout_rounded, color: AppColors.brandPink, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Exit Oneova Studio?',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            content: Text(
              'Your active project drafts, camera configurations, and captured assets will remain securely stored in your offline draft repository.',
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Keep Creating',
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Exit Studio',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showFeatureIntroductionSheet(
    BuildContext context, {
    required String title,
    required String category,
    required String description,
    required List<String> highlights,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onLaunch,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.0),
                    ),
                    child: Icon(icon, color: accentColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.brandPink, width: 0.8),
                              ),
                              child: Text(
                                'PRO',
                                style: GoogleFonts.inter(
                                  color: AppColors.brandPink,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          category,
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Core Capabilities',
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              ...highlights.map(
                (h) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.brandPink),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          h,
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onLaunch();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Launch Tool',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissAndNavigate(String route) {
    HapticFeedback.mediumImpact();
    final router = GoRouter.of(context);
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      Navigator.of(context).removeRoute(modalRoute);
    }
    router.push(route);
  }

  Future<void> _handleCreateVideo() async {
    _dismissAndNavigate('/create/camera?mode=video');
  }

  Future<void> _handleCreatePhoto() async {
    _dismissAndNavigate('/create/camera?mode=photo');
  }



  void _openDraft(OneovaDraft draft) {
    HapticFeedback.lightImpact();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      Navigator.of(context).removeRoute(modalRoute);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProWorkstationEditorScreen(draft: draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(oneovaDraftEngineProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final modalRoute = ModalRoute.of(context);
        final nav = Navigator.of(context);
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit && mounted && modalRoute != null) {
          nav.removeRoute(modalRoute);
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height,
        color: AppColors.background(context),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar with Close and Confirmation
              _buildTopBar(context).animate().fadeIn(duration: 250.ms),

              // Main Tab Body
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    // Tab 0: Studio Tools & Hero Cards
                    _buildStudioToolsView(context, drafts),

                    // Tab 1: Drafts & Projects
                    _buildProjectsView(context, drafts),

                    // Tab 2: Templates & AutoCut
                    _buildTemplatesView(context),

                    // Tab 3: Media Library
                    _buildLibraryView(context),
                  ],
                ),
              ),

              // Studio Isolated Bottom Navigation
              _buildBottomNavBar(context, drafts.length),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: context.textPrimary,
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () async {
                    final modalRoute = ModalRoute.of(context);
                    final nav = Navigator.of(context);
                    final shouldExit = await _showExitConfirmationDialog(context);
                    if (shouldExit && mounted && modalRoute != null) {
                      nav.removeRoute(modalRoute);
                    }
                  },
              ),
              const SizedBox(width: 6),
              Text(
                'Oneova Studio',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.brandPink, width: 0.8),
                ),
                child: Text(
                  'PRO',
                  style: GoogleFonts.inter(
                    color: AppColors.brandPink,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_done_rounded, size: 13, color: AppColors.brandBlue),
                    const SizedBox(width: 4),
                    Text(
                      'Synced',
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.help_outline_rounded, size: 20),
                color: context.textSecondary,
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  _showFeatureIntroductionSheet(
                    context,
                    title: 'Oneova Studio Suite',
                    category: 'Ecosystem Overview',
                    description:
                        'Professional-grade multi-camera production studio with AI voice integration, hardware remote control, and zero-latency live broadcasting.',
                    highlights: const [
                      'PiP Multi-Cam with Blackmagic color science',
                      'Cinema Stage Live with instant viewer interaction',
                      'Direct wireless remote PC keyboard and mouse control',
                      'Ova Assistant voice and autonomous action execution',
                    ],
                    icon: Icons.auto_awesome,
                    accentColor: AppColors.brandBlue,
                    onLaunch: () {},
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudioToolsView(BuildContext context, List<OneovaDraft> drafts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 600;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 32 : 16,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 3 Main Hero Action Cards (Create video, Create photo, Go Live)
              Row(
                children: [
                  Expanded(
                    child: _MainActionCard(
                      title: 'Create video',
                      subtitle: 'Record & Reel',
                      icon: Icons.videocam_rounded,
                      glowColor: AppColors.brandBlue,
                      delay: 80,
                      onTap: _handleCreateVideo,
                      onInfoTap: () {
                        _showFeatureIntroductionSheet(
                          context,
                          title: 'Create video',
                          category: 'Video Recording & Trimmer',
                          description:
                              'Record high-definition videos with film grading, audio monitoring, teleprompter, and pre-import clip trimmer.',
                          highlights: const [
                            'Studio multi-resolution camera recording',
                            'Built-in clip trimmer & aspect framing',
                            'Seamless sequence ingestion into Pro Workstation',
                          ],
                          icon: Icons.videocam_rounded,
                          accentColor: AppColors.brandBlue,
                          onLaunch: _handleCreateVideo,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MainActionCard(
                      title: 'Create photo',
                      subtitle: 'Snap & Filter',
                      icon: Icons.camera_alt_rounded,
                      glowColor: AppColors.brandBlue,
                      delay: 110,
                      onTap: _handleCreatePhoto,
                      onInfoTap: () {
                        _showFeatureIntroductionSheet(
                          context,
                          title: 'Create photo',
                          category: 'Photo Capture & Darkroom',
                          description:
                              'Snap crystal-clear photos with studio optical framing, real-time filters, and pro portrait grading.',
                          highlights: const [
                            'Ultra-high resolution photo capture',
                            'Studio beauty & portrait retouching',
                            'Seamless post & story publishing',
                          ],
                          icon: Icons.camera_alt_rounded,
                          accentColor: AppColors.brandBlue,
                          onLaunch: _handleCreatePhoto,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MainActionCard(
                      title: 'Go Live',
                      subtitle: 'LIVE · Studio',
                      icon: Icons.sensors_rounded,
                      glowColor: AppColors.brandPink,
                      delay: 140,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.push('/live/broadcast');
                      },
                      onInfoTap: () {
                        _showFeatureIntroductionSheet(
                          context,
                          title: 'Cinema Live Stage',
                          category: 'Multi-Scene Broadcasting',
                          description:
                              'Broadcast live with sub-second latency, multi-guest camera joining, interactive comments, and virtual scene staging.',
                          highlights: const [
                            'Sub-second WebRTC live stream delivery',
                            'Dynamic viewer tipping & custom reactions',
                            'Multi-camera co-host guest invitations',
                          ],
                          icon: Icons.sensors_rounded,
                          accentColor: AppColors.brandPink,
                          onLaunch: () {
                            final router = GoRouter.of(context);
                            Navigator.of(context).pop();
                            router.push('/live/broadcast');
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // Category Filter Tabs
              _buildCategoryChips(context),

              const SizedBox(height: 16),

              // Filtered Quick Tools Grid
              _buildFilteredGrid(context: context, isTablet: isTablet),

              const SizedBox(height: 24),

              // Recent Projects Section Preview
              Row(
                children: [
                  Text(
                    'Recent Projects',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.border, width: 1),
                    ),
                    child: Text(
                      drafts.length.toString(),
                      style: GoogleFonts.inter(
                        color: drafts.isNotEmpty ? AppColors.brandPink : context.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _selectedTabIndex = 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View all',
                          style: GoogleFonts.inter(
                            color: AppColors.brandBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right, size: 16, color: AppColors.brandBlue),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (drafts.isEmpty)
                _buildCompactEmptyProjects(context)
              else
                _buildDraftsGrid(context, drafts.take(2).toList(), isTablet),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = cat);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : context.surfaceMid,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : context.border,
                  width: 1.0,
                ),
              ),
              child: Center(
                child: Text(
                  cat,
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white : context.textSecondary,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilteredGrid({required BuildContext context, required bool isTablet}) {
    final filtered = _selectedCategory == 'All'
        ? _allTools
        : _allTools.where((t) => t.category == _selectedCategory || t.category == 'All').toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 8 : 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final item = filtered[index];
        return _ToolCard(
          spec: item,
          delay: 50 + (index * 30),
          onTap: () {
            if (item.route == 'modal://all_tools') {
              final modalRoute = ModalRoute.of(context);
              if (modalRoute != null) {
                Navigator.of(context).removeRoute(modalRoute);
              }
              AllToolsModal.show(context);
            } else {
              _dismissAndNavigate(item.route);
            }
          },
          onInfoTap: () {
            _showFeatureIntroductionSheet(
              context,
              title: item.title,
              category: item.category,
              description: item.description,
              highlights: item.highlights,
              icon: item.icon,
              accentColor: item.accentColor ?? AppColors.brandBlue,
              onLaunch: () {
                if (item.route == 'modal://all_tools') {
                  final modalRoute = ModalRoute.of(context);
                  if (modalRoute != null) {
                    Navigator.of(context).removeRoute(modalRoute);
                  }
                  AllToolsModal.show(context);
                } else {
                  _dismissAndNavigate(item.route);
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProjectsView(BuildContext context, List<OneovaDraft> drafts) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'All Project Drafts (${drafts.length})',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _selectedTabIndex = 0),
                icon: const Icon(Icons.add, size: 16, color: AppColors.brandBlue),
                label: Text(
                  'New',
                  style: GoogleFonts.inter(
                    color: AppColors.brandBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (drafts.isEmpty)
            _buildEmptyState(context)
          else
            _buildDraftsGrid(context, drafts, isTablet),
        ],
      ),
    );
  }

  Widget _buildTemplatesView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.dashboard_customize_rounded, size: 40, color: AppColors.brandBlue),
            ),
            const SizedBox(height: 16),
            Text(
              'Oneova Viral Video Templates',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select from Hollywood-graded pacing templates, AI text presets, and multi-clip audio synchronizers.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push('/video/dashboard');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(
                'Explore Templates Catalog',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.video_library_rounded, size: 40, color: AppColors.brandPink),
            ),
            const SizedBox(height: 16),
            Text(
              'Local Media Library',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Directly import camera rolls, external microphone recordings, or downloaded clips into your timeline.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push('/create/picker');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(
                'Open Media Picker',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftsGrid(BuildContext context, List<OneovaDraft> drafts, bool isTablet) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: drafts.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        final draft = drafts[index];
        final mediaFile = File(draft.mediaPath);
        final fileExists = mediaFile.existsSync();

        return GestureDetector(
          onTap: () => _openDraft(draft),
          child: Container(
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (fileExists && !draft.isVideo)
                  Image.file(mediaFile, fit: BoxFit.cover)
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          context.surfaceMid,
                          Colors.black87,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        draft.isVideo ? Icons.play_arrow_rounded : Icons.photo,
                        color: AppColors.brandBlue,
                        size: 32,
                      ),
                    ),
                  ),

                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          draft.isVideo ? Icons.videocam : Icons.image,
                          size: 10,
                          color: AppColors.brandPink,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          draft.isVideo ? 'VIDEO' : 'PHOTO',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white70, size: 16),
                    onPressed: () => _showDraftActionsModal(draft),
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          draft.title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDate(draft.updatedAt),
                              style: GoogleFonts.inter(
                                color: Colors.white60,
                                fontSize: 9.5,
                              ),
                            ),
                            if (draft.durationSeconds > 0)
                              Text(
                                '${draft.durationSeconds.toStringAsFixed(1)}s',
                                style: GoogleFonts.inter(
                                  color: AppColors.brandPink,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDraftActionsModal(OneovaDraft draft) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.brandBlue),
              title: Text('Continue Editing', style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _openDraft(draft);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: context.textSecondary),
              title: Text('Duplicate Project', style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(oneovaDraftEngineProvider.notifier).duplicateDraft(draft.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('Delete Project', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    backgroundColor: context.surface,
                    title: const Text('Delete Project?'),
                    content: const Text('This will permanently delete this offline project draft.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && ctx.mounted) {
                  Navigator.pop(ctx);
                  ref.read(oneovaDraftEngineProvider.notifier).deleteDraft(draft.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }

  Widget _buildCompactEmptyProjects(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.videocam_outlined, color: AppColors.brandBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No active drafts',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap PiP Studio or Photo to begin creating.',
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              shape: BoxShape.circle,
              border: Border.all(color: context.border),
            ),
            child: const Icon(Icons.video_library_outlined, size: 36, color: AppColors.brandBlue),
          ),
          const SizedBox(height: 16),
          Text(
            'Your projects will appear here',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Record or import footage to begin editing your reels.',
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context, int draftsCount) {
    return Container(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom
            : 8,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context: context,
            icon: Icons.dashboard_rounded,
            label: 'Studio',
            isActive: _selectedTabIndex == 0,
            onTap: () => setState(() => _selectedTabIndex = 0),
          ),
          _buildNavItem(
            context: context,
            icon: Icons.folder_copy_rounded,
            label: 'Drafts',
            badgeText: draftsCount > 0 ? draftsCount.toString() : null,
            isActive: _selectedTabIndex == 1,
            onTap: () => setState(() => _selectedTabIndex = 1),
          ),
          _buildNavItem(
            context: context,
            icon: Icons.auto_awesome_motion_rounded,
            label: 'Templates',
            isActive: _selectedTabIndex == 2,
            onTap: () => setState(() => _selectedTabIndex = 2),
          ),
          _buildNavItem(
            context: context,
            icon: Icons.perm_media_rounded,
            label: 'Library',
            isActive: _selectedTabIndex == 3,
            onTap: () => setState(() => _selectedTabIndex = 3),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isActive,
    String? badgeText,
    VoidCallback? onTap,
  }) {
    final color = isActive ? AppColors.brandBlue : context.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 20),
                if (badgeText != null)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioToolSpec {
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final String route;
  final String badge;
  final String description;
  final List<String> highlights;
  final Color? accentColor;

  const _StudioToolSpec({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.route,
    this.badge = '',
    required this.description,
    required this.highlights,
    this.accentColor,
  });
}

class _MainActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color glowColor;
  final int delay;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _MainActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.glowColor,
    required this.delay,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  State<_MainActionCard> createState() => _MainActionCardState();
}

class _MainActionCardState extends State<_MainActionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeInOut,
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: context.surfaceMid,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      widget.glowColor.withValues(alpha: 0.18),
                      context.surface,
                    ]
                  : [
                      widget.glowColor.withValues(alpha: 0.08),
                      context.surface,
                    ],
            ),
            border: Border.all(
              color: widget.glowColor.withValues(alpha: isDark ? 0.40 : 0.28),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: isDark ? 0.12 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top-right micro info icon
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: widget.onInfoTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 11.5,
                      color: widget.glowColor.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 29,
                      height: 29,
                      decoration: BoxDecoration(
                        color: widget.glowColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.glowColor.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 16.5,
                        color: widget.glowColor,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.08, end: 0);
  }
}

class _ToolCard extends StatefulWidget {
  final _StudioToolSpec spec;
  final int delay;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _ToolCard({
    required this.spec,
    required this.delay,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onLongPress: widget.onInfoTap,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Fixed square icon container (prevents horizontal pill distortion)
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      widget.spec.icon,
                      color: widget.spec.accentColor ?? context.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
                if (widget.spec.badge.isNotEmpty)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: widget.spec.badge == 'LIVE' || widget.spec.badge == 'PiP'
                            ? AppColors.brandPink
                            : AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.bg, width: 1.0),
                      ),
                      child: Text(
                        widget.spec.badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: Text(
                widget.spec.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ).animate().scale(
            delay: widget.delay.ms,
            duration: 300.ms,
            curve: Curves.easeOutBack,
          ).fadeIn(delay: widget.delay.ms),
    );
  }
}
