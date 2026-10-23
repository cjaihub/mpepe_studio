import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../models/omnichannel_upload_task.dart';
import '../models/connected_destination.dart';

class PreviewMatrixScreen extends ConsumerStatefulWidget {
  final OmnichannelUploadTask task;

  const PreviewMatrixScreen({super.key, required this.task});

  @override
  ConsumerState<PreviewMatrixScreen> createState() => _PreviewMatrixScreenState();
}

class _PreviewMatrixScreenState extends ConsumerState<PreviewMatrixScreen> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  late TabController _tabController;
  
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    _controller = VideoPlayerController.file(widget.task.file)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          _controller.setLooping(true);
          _controller.play();
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Preview Matrix',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: AppColors.brandBlue,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.brandBlue),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.brandBlue,
            labelColor: AppColors.brandBlue,
            unselectedLabelColor: context.textMuted,
            tabs: const [
              Tab(text: 'TikTok'),
              Tab(text: 'Shorts'),
              Tab(text: 'Reels'),
              Tab(text: 'Facebook'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPlatformPreview(PlatformType.tiktok),
                _buildPlatformPreview(PlatformType.youtube),
                _buildPlatformPreview(PlatformType.instagram),
                _buildPlatformPreview(PlatformType.facebook), // Feed
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformPreview(PlatformType platform) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
    }

    final double aspectRatio = (platform == PlatformType.facebook) ? 4 / 5 : 9 / 16;
    final bool isWarning = _controller.value.size.aspectRatio > 1.0 && platform != PlatformType.facebook;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isWarning)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Warning: Your video is horizontal. It will be letterboxed on vertical platforms.',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  )
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandBlue.withValues(alpha: 0.1),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video Layer (Scaled to fill)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller.value.size.width,
                          height: _controller.value.size.height,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                      
                      // Glassmorphic Platform Overlay
                      _buildPlatformOverlay(platform),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPlatformOverlay(PlatformType platform) {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOverlayButton(Icons.favorite, '12.4K'),
          const SizedBox(height: 16),
          _buildOverlayButton(Icons.comment, '842'),
          const SizedBox(height: 16),
          _buildOverlayButton(Icons.share, 'Share'),
        ],
      ),
    );
  }

  Widget _buildOverlayButton(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
