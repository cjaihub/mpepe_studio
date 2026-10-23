import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'undo_manager.dart';
import '../theme/app_theme.dart';

class UndoSnackbar {
  static void show(BuildContext context, WidgetRef ref, String message) {
    if (!context.mounted) return;
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
          backgroundColor: context.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 24, right: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: const BorderSide(color: AppColors.brandBlue, width: 1.5),
          ),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.brandPink,
            onPressed: () {
              ref.read(undoManagerProvider.notifier).undo();
            },
          ),
        ),
      );
    } catch (_) {}
  }
}
