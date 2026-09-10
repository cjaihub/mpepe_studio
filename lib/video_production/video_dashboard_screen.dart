import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class VideoDashboardScreen extends StatelessWidget {
  const VideoDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.videocam_outlined, Icons.movie_creation_outlined, Icons.camera_alt_outlined],
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/hub/home');
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.chevron_left, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Studio Home',
                      style: AppTheme.bodyStyle.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 14),
              _buildFriendlyHeader(context).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _StatCard(title: 'ACTIVE', value: '5').animate().fadeIn(duration: 400.ms).slideY(begin: 0.1)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'REVIEW', value: '2').animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.1)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'GEAR OUT', value: '6', valueColor: Theme.of(context).colorScheme.primary).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1)),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Active projects', style: AppTheme.h2Style),
                  GestureDetector(
                    onTap: () => context.push('/video/projects'),
                    child: Text('See all', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Episode 12 — Studio Q&A', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('DP: Brian O. • Editor: Faith N.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 3),
                    const SizedBox(height: 8),
                    Text('Editing', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1),
              const SizedBox(height: 12),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cinematic Travel Vlogs Ep.4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('DP: Josiah M. • Editor: Faith N.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 4),
                    const SizedBox(height: 8),
                    Text('Review', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms).slideX(begin: 0.1),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Equipment',
                      meta: '6 checked out',
                      onTap: () => context.push('/video/equipment'),
                    ).animate().fadeIn(delay: 500.ms).scaleXY(begin: 0.95),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Tile(
                      icon: Icons.group_outlined,
                      title: 'Crew',
                      meta: '4 members',
                      onTap: () => context.push('/video/team'),
                    ).animate().fadeIn(delay: 600.ms).scaleXY(begin: 0.95),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendlyHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Video Production Studio',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage your shoots, edit timelines, and coordinate your crew.',
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const _StatCard({required this.title, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return MpepeCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: valueColor ?? Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.title, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(meta, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
