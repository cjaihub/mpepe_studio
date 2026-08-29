import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class VideoDashboardScreen extends StatelessWidget {
  const VideoDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => context.go('/hub/home'),
                child: Row(
                  children: [
                    const Icon(Icons.chevron_left, color: AppColors.dust, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Studio Home',
                      style: AppTheme.bodyStyle.copyWith(color: AppColors.dust, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.violet,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(Icons.movie_creation_outlined, color: Colors.white, size: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Video Production', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ],
                  ),
                  const Icon(Icons.notifications_none, color: Colors.white, size: 20),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _StatCard(title: 'ACTIVE', value: '5')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'REVIEW', value: '2')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'GEAR OUT', value: '6', valueColor: AppColors.violet)),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active projects', style: AppTheme.h2Style),
                  GestureDetector(
                    onTap: () => context.go('/video/projects'),
                    child: const Text('See all', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Episode 12 — Studio Q&A', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    const Text('DP: Brian O. • Editor: Faith N.', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 3),
                    const SizedBox(height: 8),
                    const Text('Editing', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cinematic Travel Vlogs Ep.4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    const Text('DP: Josiah M. • Editor: Faith N.', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 4),
                    const SizedBox(height: 8),
                    const Text('Review', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Equipment',
                      meta: '6 checked out',
                      onTap: () => context.go('/video/equipment'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Tile(
                      icon: Icons.group_outlined,
                      title: 'Crew',
                      meta: '4 members',
                      onTap: () => context.go('/video/team'),
                    ),
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
          Text(title, style: const TextStyle(color: AppColors.dust, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: valueColor ?? Colors.white)),
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.violet,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(meta, style: const TextStyle(color: AppColors.dust, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
