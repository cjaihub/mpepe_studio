// LIVE STUDIO v2 — Cancel / Confirm dialog for destructive studio actions
// (workstream #4). Repo rule: confirm before any destructive action.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../backend/live_studio/roles/studio_roles_api.dart';
import '../theme/live_studio_tokens.dart';

/// Shows [prompt]; resolves true only when the user taps the confirm button.
Future<bool> showStudioConfirmDialog(BuildContext context, StudioConfirmPrompt prompt, LiveStudioTokens tokens) async {
  HapticFeedback.lightImpact();
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: LiveStudioTokens.dimTint(0.55),
    builder: (_) => StudioConfirmDialog(prompt: prompt, tokens: tokens),
  );
  return ok ?? false;
}

/// A [StudioConfirm] bound to [context].
StudioConfirm studioConfirmFor(BuildContext context, LiveStudioTokens tokens) =>
    (p) => showStudioConfirmDialog(context, p, tokens);

class StudioConfirmDialog extends StatelessWidget {
  const StudioConfirmDialog({super.key, required this.prompt, required this.tokens});

  final StudioConfirmPrompt prompt;
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final accent = prompt.destructive ? LiveStudioAccent.pink : LiveStudioAccent.blue;
    return Dialog(
      backgroundColor: t.drawerBottom,
      surfaceTintColor: t.drawerBottom.withValues(alpha: 0),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.drawerBorder, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(prompt.title, style: LiveStudioType.s(15, FontWeight.w700, t.textHigh, letter: -0.013)),
              const SizedBox(height: 8),
              Text(prompt.message, style: LiveStudioType.s(13, FontWeight.w400, t.textMedium, height: 18)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    button: true,
                    label: 'Cancel',
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 44),
                        foregroundColor: t.textMedium,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Cancel', style: LiveStudioType.s(13, FontWeight.w600, t.textMedium)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: prompt.confirmLabel,
                    excludeSemantics: true,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(88, 44),
                        backgroundColor: accent,
                        foregroundColor: LiveStudioAccent.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(prompt.confirmLabel, style: LiveStudioType.s(13, FontWeight.w700, LiveStudioAccent.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
