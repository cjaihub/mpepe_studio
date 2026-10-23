// LIVE STUDIO v2 — live-health advisory banner for host / co-hosts
// (security workstream). One-tap actions; each goes through the studio
// confirmation dialog (studioConfirmFor) before anything runs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/roles/studio_roles_api.dart';
import '../../../../backend/live_studio/security/studio_security_controller.dart';
import '../../../../backend/live_studio/security/studio_security_models.dart';
import '../join/studio_confirm_dialog.dart';
import '../theme/live_studio_tokens.dart';
import 'live_health_sheet.dart';

/// Accent for a severity (tokens only).
Color studioSeverityColor(StudioSeverity s) => switch (s) {
      StudioSeverity.info => LiveStudioAccent.blue,
      StudioSeverity.warn => LiveStudioAccent.pink,
      StudioSeverity.critical => LiveStudioAccent.liveRed,
    };

IconData studioSeverityIcon(StudioSeverity s) => switch (s) {
      StudioSeverity.info => Icons.shield_outlined,
      StudioSeverity.warn => Icons.gpp_maybe_outlined,
      StudioSeverity.critical => Icons.gpp_bad_outlined,
    };

class SecurityAdvisoryBanner extends ConsumerWidget {
  const SecurityAdvisoryBanner({
    super.key,
    required this.streamId,
    required this.role,
    required this.tokens,
    this.confirm,
  });

  final String streamId;

  /// Only host / co-hosts see the banner.
  final StudioRole role;
  final LiveStudioTokens tokens;

  /// Override for tests; defaults to [studioConfirmFor].
  final StudioConfirm? confirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!role.isManager) return const SizedBox.shrink();
    final advisory = ref.watch(studioCurrentAdvisoryProvider(streamId));
    if (advisory == null) return const SizedBox.shrink();
    final view = ref.watch(studioSecurityControllerProvider(streamId));
    final ctl = ref.read(studioSecurityControllerProvider(streamId).notifier);
    final t = tokens;
    final accent = studioSeverityColor(advisory.severity);
    final confirmFn = confirm ?? studioConfirmFor(context, t);

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Live health alert: ${advisory.assessment}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: t.drawerBottom,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
          boxShadow: [BoxShadow(color: t.glassShadow(), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(studioSeverityIcon(advisory.severity), size: 18, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        advisory.fromAi ? 'Live health · AI suggestion' : 'Live health',
                        style: LiveStudioType.s(11, FontWeight.w700, accent, letter: 0.02),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        advisory.assessment,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LiveStudioType.s(12.5, FontWeight.w500, t.textHigh, height: 17),
                      ),
                    ],
                  ),
                ),
                _IconTap(
                  icon: Icons.close_rounded,
                  label: 'Dismiss alert',
                  color: t.textMedium,
                  onTap: () => ctl.dismiss(advisory.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in advisory.actions)
                  _ActionChip(
                    label: a.label,
                    tokens: t,
                    destructive: a.type != StudioAdvisoryActionType.slowMode &&
                        a.type != StudioAdvisoryActionType.followersOnly,
                    busy: ctl.isBusy(advisory, a),
                    done: ctl.isDone(advisory, a),
                    onTap: () => ctl.apply(advisory, a, confirm: confirmFn),
                  ),
                _ActionChip(
                  label: 'Details',
                  tokens: t,
                  ghost: true,
                  onTap: () => showLiveHealthSheet(context, streamId: streamId, tokens: t),
                ),
              ],
            ),
            if (view.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(view.error!, style: LiveStudioType.s(11, FontWeight.w500, LiveStudioAccent.muteIcon)),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 18, color: color)),
        ),
      );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.tokens,
    required this.onTap,
    this.destructive = false,
    this.ghost = false,
    this.busy = false,
    this.done = false,
  });

  final String label;
  final LiveStudioTokens tokens;
  final VoidCallback onTap;
  final bool destructive;
  final bool ghost;
  final bool busy;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final accent = destructive ? LiveStudioAccent.pink : LiveStudioAccent.blue;
    final fill = ghost ? t.ghostFill : accent.withValues(alpha: 0.16);
    final border = ghost ? t.ghostBorder : accent.withValues(alpha: 0.5);
    final fg = ghost ? t.textMedium : t.textHigh;
    final enabled = !busy && !done;
    return Semantics(
      button: true,
      enabled: enabled,
      label: done ? '$label, done' : label,
      excludeSemantics: true,
      child: Material(
        color: LiveStudioAccent.clear,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: fg),
                  )
                else if (done)
                  Icon(Icons.check_rounded, size: 14, color: fg),
                if (busy || done) const SizedBox(width: 6),
                Text(label, style: LiveStudioType.s(12, FontWeight.w600, fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
