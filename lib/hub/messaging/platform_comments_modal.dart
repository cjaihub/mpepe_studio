import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';
import 'platform_inbox_view.dart';

/// Comments on one linked platform, as a bottom sheet over the inbox. Same
/// rows as the inbox's platform view ([PlatformInboxView]), filtered to
/// comments: real data only, no placeholder threads.
class PlatformCommentsModal extends StatelessWidget {
  final String platform;

  const PlatformCommentsModal({super.key, required this.platform});

  static void show(BuildContext context, {required String platform}) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => PlatformCommentsModal(platform: platform),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PlatformInboxView(
              platformId: platform,
              initialFilter: PlatformInboxFilter.comments,
              onShowAll: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
