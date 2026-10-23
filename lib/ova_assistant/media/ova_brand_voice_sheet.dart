import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import 'ova_media_brain.dart';

/// Natural-language brand kit editor. Ova's caption, post and campaign
/// skills follow what the user writes here.
Future<void> showOvaBrandVoiceEditor(BuildContext context, WidgetRef ref) async {
  final current = ref.read(ovaBrandVoiceProvider).value ?? '';
  final ctrl = TextEditingController(text: current);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.darkSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.diamond_rounded, size: 18, color: AppColors.brandPink),
          const SizedBox(width: 8),
          Text('Your brand voice',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 6),
        Text('Describe it in your own words. Ova follows it for captions, posts and campaigns.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 3,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
          cursorColor: AppColors.brandBlue,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'e.g. Bold, warm and witty. Speaks to young African creators. Short sentences, a little Swahili slang, never salesy.',
            hintStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.darkSurfaceHighlight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.brandBlue),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save brand voice', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      ]),
    ),
  );
  if (saved == true) {
    await saveOvaBrandVoice(ctrl.text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Brand voice saved'),
        backgroundColor: AppColors.brandBlue,
      ));
    }
  }
  ctrl.dispose();
}
