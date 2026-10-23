import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/undo/undo_manager.dart';
import '../commands/update_setting_command.dart';

/// Compact, auto-saving building blocks shared by every settings screen.
///
/// Every control writes straight to `user_settings/{uid}` through
/// [settingsWrite] (undoable, optimistic), and [SettingsSaveIndicator]
/// reflects the real state of that write.

/// Persists one setting instantly and registers it with the undo stack.
void settingsWrite(
  WidgetRef ref, {
  required String category,
  required Map<String, dynamic> current,
  required String key,
  required dynamic value,
  required String label,
}) {
  HapticFeedback.selectionClick();
  final next = Map<String, dynamic>.from(current)..[key] = value;
  ref.read(undoManagerProvider.notifier).executeAndRegister(
        UpdateSettingCommand(
          ref: ref,
          category: category,
          undoData: current,
          data: next,
          name: 'Update $label',
        ),
      );
}

/// Reads a category map out of the merged settings document.
Map<String, dynamic> settingsCategory(Map<String, dynamic> settings, String category) {
  final raw = settings[category];
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

/// Live auto-save pill: Auto-save on → Saving… → Saved / Saved on device.
class SettingsSaveIndicator extends ConsumerWidget {
  /// True when drawn on the brand-blue top bar.
  final bool onBrand;
  const SettingsSaveIndicator({super.key, this.onBrand = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(settingsSaveStatusProvider);
    final fg = onBrand ? context.topBarFg : context.textSecondary;

    late final String label;
    Color dot = const Color(0xFF10B981);
    switch (status.phase) {
      case SettingsSavePhase.idle:
        label = 'Auto-save on';
      case SettingsSavePhase.saving:
        label = 'Saving…';
      case SettingsSavePhase.saved:
        label = 'Saved';
      case SettingsSavePhase.pendingSync:
        label = 'Saved on device';
        dot = AppColors.brandPink;
      case SettingsSavePhase.error:
        label = 'Not saved';
        dot = AppColors.brandPink;
    }
    final Widget lead = status.phase == SettingsSavePhase.saving
        ? SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.4, color: fg))
        : Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(status.phase),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: onBrand ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: fg.withValues(alpha: onBrand ? 0.32 : 0.18), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            lead,
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand top bar + scrolling body used by all compact settings screens.
class CompactSettingsScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  const CompactSettingsScaffold({super.key, required this.title, required this.children, this.actions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: context.topBarBg,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.topBarFg, size: 17),
          onPressed: () => context.canPop() ? context.pop() : context.push('/settings/main'),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: context.topBarFg,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const SettingsSaveIndicator(),
          ],
        ),
        actions: actions,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
        children: children,
      ),
    );
  }
}

/// Micro-label + hairline grouped container with inset dividers.
class SettingsSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final String? footer;
  const SettingsSection({super.key, required this.label, required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: context.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, thickness: 1, indent: 48, color: context.border),
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                footer!,
                style: GoogleFonts.inter(fontSize: 10.5, height: 1.35, color: context.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// 28px tinted icon chip used at the start of every row.
class SettingsIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const SettingsIconChip({super.key, required this.icon, this.color = AppColors.brandBlue, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1.0),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

class _RowShell extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _RowShell({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              SettingsIconChip(icon: icon, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        color: context.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 10.5, height: 1.3, color: context.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact switch row; the whole row is tappable.
class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.brandBlue,
  });

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      icon: icon,
      accent: accent,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Transform.scale(
        scale: 0.78,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.brandBlue,
          activeThumbColor: Colors.white,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Row that pushes another screen.
class SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;
  final Color accent;
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
    this.accent = AppColors.brandBlue,
  });

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      icon: icon,
      accent: accent,
      title: title,
      subtitle: subtitle,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textMuted)),
          Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
        ],
      ),
    );
  }
}

/// Row with a compact segmented chip picker underneath the title.
class SettingsChoiceTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color accent;
  const SettingsChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.options,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.brandBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SettingsIconChip(icon: icon, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                for (final entry in options.entries)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (entry.key != value) onChanged(entry.key);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: entry.key == value ? AppColors.brandBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: entry.key == value ? FontWeight.w700 : FontWeight.w600,
                            color: entry.key == value ? Colors.white : context.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small square toggle used in the "Quick controls" grid.
class SettingsQuickToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const SettingsQuickToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: active ? AppColors.brandBlue : context.border, width: 1.0),
          boxShadow: active
              ? [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : context.textSecondary),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a body that depends on the settings document with loading/error UI.
class SettingsAsyncBody extends ConsumerWidget {
  final Widget Function(Map<String, dynamic> settings) builder;
  const SettingsAsyncBody({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(settingsProvider).when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Text(
                'Could not load settings',
                style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
              ),
            ),
          ),
          data: builder,
        );
  }
}
