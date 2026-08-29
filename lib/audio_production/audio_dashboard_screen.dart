import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class AudioDashboardScreen extends StatelessWidget {
  const AudioDashboardScreen({super.key});

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
                          color: AppColors.teal,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Audio Production', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ],
                  ),
                  const Icon(Icons.notifications_none, color: Colors.white, size: 20),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _StatCard(title: 'ACTIVE', value: '6')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'IN REVIEW', value: '3')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'DONE', value: '14', valueColor: AppColors.mint)),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Library',
                      meta: '23 tracks',
                      onTap: () => context.go('/audio/library'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Tile(
                      icon: Icons.group_outlined,
                      title: 'Artists',
                      meta: '2 new requests',
                      onTap: () => context.go('/audio/artists'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active productions', style: AppTheme.h2Style),
                  GestureDetector(
                    onTap: () => context.go('/audio/productions'),
                    child: const Text('See all', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ProductionCard(
                title: '"Late Nights" — Amara J.',
                subtitle: 'Producer: Josiah M.',
                status: 'In production',
                statusColor: AppColors.teal,
              ),
              const SizedBox(height: 10),
              _ProductionCard(
                title: '"Homecoming" — DJ Rue',
                subtitle: 'Producer: Wanjiru K.',
                status: 'In review',
                statusColor: AppColors.orange,
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
                color: AppColors.teal,
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

class _ProductionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;

  const _ProductionCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return MpepeCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: AppColors.dust, fontSize: 12)),
              ],
            ),
          ),
          MpepePill(
            label: status,
            color: statusColor,
            isGhost: true,
          ),
        ],
      ),
    );
  }
}
