import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shared/design_system/app_colors.dart';
import '../backend/project_repository.dart';
import 'package:go_router/go_router.dart';

class ExportSettingsScreen extends StatefulWidget {
  final StudioProject project;
  const ExportSettingsScreen({super.key, required this.project});

  @override
  State<ExportSettingsScreen> createState() => _ExportSettingsScreenState();
}

class _ExportSettingsScreenState extends State<ExportSettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _aiUltraHd = true;
  bool _opticalFlow = false;
  double _resolutionValue = 2; // 0=480p, 1=720p, 2=1080p, 3=2K/4K
  double _frameRateValue = 2; // 0=24, 1=25, 2=30, 3=50, 4=60
  double _bitrateValue = 1; // 0=5, 1=10, 2=20, 3=50, 4=100

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // Video, GIF
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground, // #0A0A0A
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAiUltraHdToggle(),
                    const SizedBox(height: 32),
                    _buildResolutionSlider(),
                    const SizedBox(height: 32),
                    _buildFrameRateSlider(),
                    const SizedBox(height: 32),
                    _buildOpticalFlowToggle(),
                    const SizedBox(height: 32),
                    _buildBitrateSlider(),
                    const SizedBox(height: 32),
                    _buildWatermarkRow(),
                    const SizedBox(height: 48),
                    Center(
                      child: Text(
                        'Estimated file size: 30 MB',
                        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildEditorToolbar(),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 8),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.brandBlue,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Video'),
                  Tab(text: 'GIF'),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.darkSurfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text('AI UHD', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 4),
                    const Icon(Icons.diamond, color: Colors.blueAccent, size: 14),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 14),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  // Export action
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue, // Changed from Cyan to Brand Red
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Export',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiUltraHdToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('AI ultra HD', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 4),
                  const Icon(Icons.diamond, color: Colors.blueAccent, size: 16),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Make your video clearer and smoother with AI enhancement and frame interpolation.',
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 12, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  const Icon(Icons.slideshow_rounded, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text('Example', style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        Switch(
          value: _aiUltraHd,
          onChanged: (v) => setState(() => _aiUltraHd = v),
          activeThumbColor: AppColors.brandBlue,
          activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.4),
          inactiveThumbColor: AppColors.textSecondary,
          inactiveTrackColor: AppColors.darkSurface,
        ),
      ],
    );
  }

  Widget _buildResolutionSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('Resolution', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 4),
                const Icon(Icons.help_outline_rounded, color: AppColors.textSecondary, size: 14),
              ],
            ),
            Text('High definition - the ultimate viewing experience', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        _buildCustomSlider(
          value: _resolutionValue,
          divisions: 3,
          labels: ['480p', '720p', '1080p', '2K/4K'],
          onChanged: (v) => setState(() => _resolutionValue = v),
          showDiamondOnLast: true,
          showBadgeOnIndex: 2,
        ),
      ],
    );
  }

  Widget _buildFrameRateSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Frame rate', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Smoother playback', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        _buildCustomSlider(
          value: _frameRateValue,
          divisions: 4,
          labels: ['24', '25', '30', '50', '60'],
          onChanged: (v) => setState(() => _frameRateValue = v),
        ),
      ],
    );
  }

  Widget _buildOpticalFlowToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Optical flow', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 4),
                const Icon(Icons.diamond, color: Colors.blueAccent, size: 16),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Make video playback smoother.', style: GoogleFonts.inter(color: AppColors.brandBlue, fontSize: 12)),
                const SizedBox(width: 8),
                Container(width: 1, height: 12, color: AppColors.textMuted),
                const SizedBox(width: 8),
                const Icon(Icons.slideshow_rounded, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text('Example', style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
              ],
            ),
          ],
        ),
        Switch(
          value: _opticalFlow,
          onChanged: (v) => setState(() => _opticalFlow = v),
          activeThumbColor: AppColors.brandBlue,
          activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.4),
          inactiveThumbColor: AppColors.textSecondary,
          inactiveTrackColor: AppColors.darkSurface,
        ),
      ],
    );
  }

  Widget _buildBitrateSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Bitrate (Mbps)', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Recommended for this video(12)', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        _buildCustomSlider(
          value: _bitrateValue,
          divisions: 4,
          labels: ['5', '10', '20', '50', '100'],
          onChanged: (v) => setState(() => _bitrateValue = v),
        ),
      ],
    );
  }

  Widget _buildWatermarkRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Watermark', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Row(
          children: [
            Text('Oneova Studio', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomSlider({
    required double value,
    required int divisions,
    required List<String> labels,
    required Function(double) onChanged,
    bool showDiamondOnLast = false,
    int? showBadgeOnIndex,
  }) {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: AppColors.brandBlue, // Changed from Cyan
            inactiveTrackColor: AppColors.darkSurfaceHighlight,
            thumbColor: Colors.white,
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
            activeTickMarkColor: AppColors.brandBlue,
            inactiveTickMarkColor: AppColors.darkSurfaceHighlight,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: divisions.toDouble(),
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(labels.length, (index) {
            final isLast = index == labels.length - 1;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[index],
                      style: GoogleFonts.inter(
                        color: value == index ? Colors.white : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: value == index ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (isLast && showDiamondOnLast) ...[
                      const SizedBox(width: 2),
                      const Icon(Icons.diamond, color: Colors.blueAccent, size: 10),
                    ]
                  ],
                ),
                if (showBadgeOnIndex == index)
                  Positioned(
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue, // Cyan -> Red
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('1 use', style: GoogleFonts.inter(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildEditorToolbar() {
    final tools = [
      {'icon': Icons.content_cut, 'label': 'Edit'},
      {'icon': Icons.music_note_rounded, 'label': 'Audio'},
      {'icon': Icons.title_rounded, 'label': 'Text'},
      {'icon': Icons.auto_awesome, 'label': 'Effects'},
      {'icon': Icons.layers, 'label': 'Overlay'},
      {'icon': Icons.subtitles_rounded, 'label': 'Captions'},
    ];

    return Container(
      color: AppColors.darkBackground,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tools.map((t) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(t['icon'] as IconData, color: AppColors.textSecondary, size: 24),
              const SizedBox(height: 4),
              Text(
                t['label'] as String,
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 48,
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Icon(Icons.menu, color: AppColors.textSecondary, size: 24),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.textSecondary, width: 2),
            ),
          ),
          const Icon(Icons.undo_rounded, color: AppColors.textSecondary, size: 24),
        ],
      ),
    );
  }
}
