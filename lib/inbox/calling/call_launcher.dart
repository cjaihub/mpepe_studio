import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/calling/providers/active_call_controller.dart';
import '../../shared/theme/app_theme.dart';

/// The one way to place a call from anywhere in the app: starts the call
/// through [ActiveCallController] and opens `/call/active`.
Future<void> startOneovaCall(
  BuildContext context,
  WidgetRef ref, {
  required List<String> targetUserIds,
  required bool isVideo,
  String? chatId,
  String? title,
}) async {
  HapticFeedback.lightImpact();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  try {
    await ref.read(activeCallControllerProvider.notifier).startCall(
          targetUserIds: targetUserIds,
          isVideo: isVideo,
          chatId: chatId,
          title: title,
        );
    router.push('/call/active');
  } catch (e) {
    final text = e is StateError ? e.message : 'Could not start the call. Check your connection.';
    messenger?.showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.inter(fontSize: 12.5)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandBlue,
    ));
  }
}
