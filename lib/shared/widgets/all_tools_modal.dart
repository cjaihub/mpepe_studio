import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';

class AllToolsModal extends StatefulWidget {
  const AllToolsModal({super.key});

  static void show(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background(context),
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => const AllToolsModal(),
    );
  }

  @override
  State<AllToolsModal> createState() => _AllToolsModalState();
}

class _AllToolsModalState extends State<AllToolsModal> {
  String _searchQuery = '';

  void _showToolIntroSheet(
    BuildContext context, {
    required String title,
    required String category,
    required String description,
    required IconData icon,
    required VoidCallback onLaunch,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.0),
                    ),
                    child: Icon(icon, color: AppColors.brandBlue, size: 22),
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
                                fontSize: 16,
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
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
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

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.92;

    final quickActions = [
      _AllToolItem('PiP Studio', Icons.picture_in_picture_alt_rounded, '/create/camera?mode=pip', 'Dual-camera simultaneous reaction and streaming.'),
      _AllToolItem('Go Live', Icons.sensors_rounded, '/live/setup', 'Full-screen LIVE to your followers.'),
      _AllToolItem('Live Studio', Icons.view_quilt_rounded, '/live/setup?mode=studio', 'Guests as video windows on studio walls.'),
      _AllToolItem('Game Live', Icons.sports_esports, '/live/setup?mode=gaming', 'Stream your phone game with your camera in a bubble.'),
      _AllToolItem('Gaming lives', Icons.videogame_asset_rounded, '/live/gaming', 'Watch game lives that are on air right now.'),
      _AllToolItem('Camera', Icons.camera_alt_rounded, '/create/camera', 'Blackmagic color science production camera.'),
      _AllToolItem('Retouch', Icons.auto_awesome_rounded, '/photo/studio', 'Portrait AI skin smoothing and facial sculpting.'),
      _AllToolItem('Auto captions', Icons.subtitles_rounded, '/video/dashboard', 'Neural synchronized kinetic subtitles.'),
      _AllToolItem('Teleprompter', Icons.speed_rounded, '/video/dashboard', 'Voice-scrolling floating teleprompter.'),
      _AllToolItem('Control PC', Icons.desktop_windows_rounded, '/connect', 'Wireless remote keyboard, trackpad, and timeline control.'),
      _AllToolItem('Desktop agent', Icons.computer_rounded, '/desktop_agent', 'Run local automation scripts and hardware monitoring.'),
      _AllToolItem('Photo studio', Icons.image_rounded, '/photo/studio', '3-way color wheels and localized layer masking.'),
      _AllToolItem('Frame capture', Icons.fullscreen_rounded, '/video/dashboard', 'High-res raw frame still extraction.'),
    ];

    final aiTools = [
      _AllToolItem('AutoCut AI', Icons.movie_creation_outlined, '/video/dashboard', 'Automatic beat-matched montage generation.'),
      _AllToolItem('AI Avatars', Icons.face_retouching_natural_rounded, '/ai_studio?mode=avatars', 'Text-to-video realistic presenter avatars.'),
      _AllToolItem('AI Dialogue', Icons.chat_rounded, '/ai_studio?mode=dialogue', 'Multi-speaker script generation and voice actors.'),
      _AllToolItem('AI Image Gen', Icons.brush_rounded, '/ai_studio?mode=image', 'Photorealistic visual asset and background synthesis.'),
      _AllToolItem('AI Effects', Icons.auto_fix_high_rounded, '/ai_studio?mode=effects', 'Neural style transfer and visual FX.'),
      _AllToolItem('AI Video Reel', Icons.videocam_rounded, '/ai_studio?mode=video', 'One-click full reel assembly from prompts.'),
    ];

    final filteredQuick = _searchQuery.isEmpty
        ? quickActions
        : quickActions.where((t) => t.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final filteredAi = _searchQuery.isEmpty
        ? aiTools
        : aiTools.where((t) => t.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
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

          // Header
          _buildHeader(context),

          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border, width: 1.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search Oneova tools...',
                        hintStyle: GoogleFonts.inter(color: context.textSecondary, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _searchQuery = ''),
                      child: Icon(Icons.close, size: 16, color: context.textSecondary),
                    ),
                ],
              ),
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (filteredQuick.isNotEmpty) ...[
                    _buildSectionTitle(context, 'Production & Live Tools'),
                    const SizedBox(height: 12),
                    _buildGrid(context: context, items: filteredQuick, category: 'Production Tool'),
                    const SizedBox(height: 24),
                  ],
                  if (filteredAi.isNotEmpty) ...[
                    _buildSectionTitle(context, 'AI Creative Engines'),
                    const SizedBox(height: 12),
                    _buildGrid(context: context, items: filteredAi, category: 'AI Creative Engine'),
                    const SizedBox(height: 24),
                  ],
                  if (filteredQuick.isEmpty && filteredAi.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No matching studio tools found',
                          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'All Studio Tools',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
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
                  'ONEOVA',
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
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.close_rounded, color: context.textPrimary, size: 22),
            splashRadius: 20,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: context.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildGrid({
    required BuildContext context,
    required List<_AllToolItem> items,
    required String category,
  }) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 8 : 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final router = GoRouter.of(context);
            context.pop();
            router.push(item.route);
          },
          onLongPress: () {
            _showToolIntroSheet(
              context,
              title: item.title,
              category: category,
              description: item.description,
              icon: item.icon,
              onLaunch: () {
                final router = GoRouter.of(context);
                context.pop();
                router.push(item.route);
              },
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(
                  item.icon,
                  color: context.textPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 26,
                child: Text(
                  item.title,
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
        );
      },
    );
  }
}

class _AllToolItem {
  final String title;
  final IconData icon;
  final String route;
  final String description;

  _AllToolItem(this.title, this.icon, this.route, this.description);
}
