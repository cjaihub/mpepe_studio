import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

/// Floating indicator displayed when an AR trigger event (gesture/expression) fires.
class ArTriggerBadge extends StatelessWidget {
  final String label;

  const ArTriggerBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandPink, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 14, color: AppColors.brandPink),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
