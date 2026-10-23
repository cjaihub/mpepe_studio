import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';

class StudioHubScreen extends ConsumerWidget {
  const StudioHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Oneova Studio',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create & Produce',
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildStudioCard(
              context,
              title: 'Pro Video Editor',
              subtitle: 'Advanced multi-track timeline, grading, & VFX',
              icon: Icons.movie_creation_rounded,
              color: AppColors.brandBlue,
              onTap: () => context.push('/video/dashboard'),
            ),
            const SizedBox(height: 12),
            _buildStudioCard(
              context,
              title: 'Photo Studio',
              subtitle: 'Retouch, mask, and enhance photos',
              icon: Icons.camera_enhance_rounded,
              color: const Color(0xFF10B981), // Emerald
              onTap: () => context.push('/photo/studio'),
            ),
            const SizedBox(height: 12),
            _buildStudioCard(
              context,
              title: 'Audio Pipeline',
              subtitle: 'Mix, master, and produce soundtracks',
              icon: Icons.graphic_eq_rounded,
              color: const Color(0xFFF59E0B), // Amber
              onTap: () => context.push('/audio/dashboard'),
            ),
            const SizedBox(height: 32),
            Text(
              'Publishing',
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildStudioCard(
              context,
              title: 'Omnichannel Distributor',
              subtitle: 'Upload everywhere simultaneously (YouTube, TikTok...)',
              icon: Icons.rocket_launch_rounded,
              color: const Color(0xFF8B5CF6), // Purple
              onTap: () => context.push('/upload/global/post'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudioCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.border),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.textMuted),
          ],
        ),
      ),
    );
  }
}
