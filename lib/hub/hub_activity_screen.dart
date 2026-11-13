import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../backend/notification_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/studio_background.dart';

class HubActivityScreen extends ConsumerWidget {
  const HubActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.people_outline, Icons.dashboard_outlined],
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          children: [
            Text('Activity', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: context.textPrimary)),
            const SizedBox(height: 6),
            Text('Across every module in your studio', style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 18),
            notificationsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No studio activity yet.',
                        style: TextStyle(color: context.textMuted, fontSize: 13),
                      ),
                    ),
                  );
                }
                return Column(
                  children: items.map((n) {
                    final isAi = n.type == 'ai' || n.title.toLowerCase().contains('ova');
                    return _buildActivityRow(
                      context: context,
                      title: n.title.isNotEmpty ? n.title : n.message,
                      meta: '${n.type.toUpperCase()} · ${timeago.format(n.createdAt)}',
                      icon: isAi ? Icons.auto_awesome : Icons.notifications_outlined,
                      iconColor: AppColors.brandBlue,
                      isAi: isAi,
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.brandBlue))),
              error: (e, _) => Center(child: Text('Error loading activity: $e', style: TextStyle(color: context.textSecondary))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow({
    required BuildContext context,
    required String title,
    required String meta,
    required IconData icon,
    Color? iconColor,
    Color? iconWidgetColor,
    bool isAi = false,
  }) {
    final effectiveIconWidgetColor = iconWidgetColor ?? Theme.of(context).colorScheme.onPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isAi ? null : iconColor,
              gradient: isAi ? AppColors.aiGradient : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: effectiveIconWidgetColor, size: 16),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(meta, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
