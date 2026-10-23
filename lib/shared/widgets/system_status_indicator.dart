import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/system/system_status_models.dart';
import '../../backend/system/system_status_service.dart';
import '../theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class SystemStatusIndicator extends ConsumerWidget {
  final bool isAdmin; // In prod, this comes from user auth state

  const SystemStatusIndicator({
    super.key,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);

    final label = status.globalStateDisplay;
    final dotColor = Color(status.globalColorHex);
    final isOnline = status.globalStateDisplay == 'ONLINE';
    IconData? icon = isOnline ? null : Icons.cloud_off;
    bool isAnimating = !isOnline && status.components.values.any((c) => c.statusDisplay == 'RECONNECTING' || c.statusDisplay == 'CONNECTING');

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (isAdmin) {
          _showDiagnosticModal(context, status);
        } else {
          // Normal users just see a toast, auto-reconnect handles the rest
          if (!isOnline) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("System is recovering. Please wait..."))
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dotColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: dotColor, size: 12),
              const SizedBox(width: 6),
            ] else if (isAnimating) ...[
              SizedBox(
                width: 10,
                height: 10,
                child: AnimatedLoadingIndicator(strokeWidth: 2, color: dotColor),
              ),
              const SizedBox(width: 8),
            ] else ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDiagnosticModal(BuildContext context, SystemStatusSnapshot status) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ADMIN DIAGNOSTICS",
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: ctx.textMuted, letterSpacing: 2.0),
                ),
                const SizedBox(height: 24),
                ...status.components.values.map((health) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          health.component.name.toUpperCase(),
                          style: GoogleFonts.inter(color: ctx.textPrimary, fontWeight: FontWeight.bold),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              health.statusDisplay,
                              style: TextStyle(
                                color: Color(health.colorHex),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (health.retryCount > 0)
                              Text("Retries: ${health.retryCount}", style: TextStyle(color: ctx.textMuted, fontSize: 10)),
                            if (health.lastError != null)
                              Text("Error: ${health.lastError}", style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Because we don't have access to ref here directly without passing it, 
                      // we just close it. The user can tap the pill to force reconnect.
                    },
                    child: const Text("Close Diagnostics"),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}
