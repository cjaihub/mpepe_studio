import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'undo_manager.dart';
import '../theme/app_theme.dart';

class UndoSnackbar {
  static void show(BuildContext context, WidgetRef ref, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.mpepeMaroon,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.mpepeGold,
          onPressed: () {
            ref.read(undoManagerProvider.notifier).undo();
          },
        ),
      ),
    );
  }
}
