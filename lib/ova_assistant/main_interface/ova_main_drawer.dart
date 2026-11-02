import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/project_repository.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';
import '../services/ova_shared_history_service.dart';

enum OvaMainSection {
  home,
  agents,
  liveVoice,
  explore,
  library,
  history;

  String get label => switch (this) {
        OvaMainSection.home => 'Home',
        OvaMainSection.agents => 'AI Agents',
        OvaMainSection.liveVoice => 'Live Voice',
        OvaMainSection.explore => 'Explore',
        OvaMainSection.library => 'Library',
        OvaMainSection.history => 'History',
      };

  IconData get icon => switch (this) {
        OvaMainSection.home => Icons.home_outlined,
        OvaMainSection.agents => Icons.smart_toy_outlined,
        OvaMainSection.liveVoice => Icons.graphic_eq_rounded,
        OvaMainSection.explore => Icons.explore_outlined,
        OvaMainSection.library => Icons.collections_bookmark_outlined,
        OvaMainSection.history => Icons.history_rounded,
      };

  IconData get activeIcon => switch (this) {
        OvaMainSection.home => Icons.home_rounded,
        OvaMainSection.agents => Icons.smart_toy_rounded,
        OvaMainSection.liveVoice => Icons.graphic_eq_rounded,
        OvaMainSection.explore => Icons.explore_rounded,
        OvaMainSection.library => Icons.collections_bookmark_rounded,
        OvaMainSection.history => Icons.history_rounded,
      };
}

/// Compact, high-density slide-out navigation drawer for the Ova Main Interface.
class OvaMainDrawer extends ConsumerWidget {
  final OvaMainSection activeSection;
  final OvaWorkspaceId activeWorkspace;
  final VoidCallback onNewChat;
  final ValueChanged<OvaMainSection> onSelectSection;
  final ValueChanged<OvaWorkspaceId> onSelectWorkspace;
  final VoidCallback onClose;

  const OvaMainDrawer({
    super.key,
    required this.activeSection,
    required this.activeWorkspace,
    required this.onNewChat,
    required this.onSelectSection,
    required this.onSelectWorkspace,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = Firebase.apps.isNotEmpty;
    final profileAsync = firebaseReady ? ref.watch(currentUserProfileProvider) : null;
    final projectsAsync = firebaseReady ? ref.watch(projectsStreamProvider) : null;
    final sharedHistory = ref.watch(ovaSharedHistoryProvider);

    final authUser = firebaseReady ? FirebaseAuth.instance.currentUser : null;
    final profile = profileAsync?.asData?.value;
    final displayName = (profile?.fullName.trim().isNotEmpty == true)
        ? profile!.fullName.trim()
        : (authUser?.displayName?.trim().isNotEmpty == true
            ? authUser!.displayName!.trim()
            : (authUser?.email?.split('@').first ?? 'Creator'));
    final photoUrl = (profile?.profilePhotoUrl?.trim().isNotEmpty == true)
        ? profile!.profilePhotoUrl
        : authUser?.photoURL;
    final projectCount = projectsAsync?.asData?.value.length ?? 0;
    final historyCount = sharedHistory.threads.length;

    return Drawer(
      width: 276,
      elevation: 0,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.xl)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.xl)),
          border: Border(right: BorderSide(color: context.border, width: 1.0)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Wordmark + Close Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                child: Row(
                  children: [
                    const OvaWordmark(),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close menu',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onClose();
                      },
                      icon: Icon(Icons.close_rounded, size: 20, color: context.textPrimary),
                    ),
                  ],
                ),
              ),

              // 2. Primary "+ New chat" Action Button (40px compact pill)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onNewChat();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: AppColors.brandWhite,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 19, color: AppColors.brandWhite),
                    label: Text(
                      'New chat',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        color: AppColors.brandWhite,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Primary Sections + Workspaces Scrollable Area
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final section in OvaMainSection.values)
                      _DrawerNavItem(
                        icon: activeSection == section ? section.activeIcon : section.icon,
                        label: section.label,
                        selected: activeSection == section,
                        badge: section == OvaMainSection.history && historyCount > 0
                            ? '$historyCount'
                            : (section == OvaMainSection.liveVoice ? 'LIVE' : null),
                        accentBadge: section == OvaMainSection.liveVoice,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelectSection(section);
                        },
                      ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 8, 8),
                      child: Text(
                        'WORKSPACES',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: context.textMuted,
                        ),
                      ),
                    ),
                    for (final ws in OvaWorkspaceId.values)
                      _DrawerWorkspaceTile(
                        workspace: ws,
                        selected: activeWorkspace == ws,
                        countBadge: ws == OvaWorkspaceId.work && projectCount > 0 ? projectCount : null,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelectWorkspace(ws);
                        },
                      ),
                  ],
                ),
              ),

              // 4. Footer: Profile & Settings
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.border, width: 1.0)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DrawerFooterRow(
                      leading: CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.brandBlue.withValues(alpha: 0.14),
                        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandBlue,
                                ),
                              )
                            : null,
                      ),
                      label: displayName,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onClose();
                        context.push('/profile/me');
                      },
                    ),
                    const SizedBox(height: 4),
                    _DrawerFooterRow(
                      leading: Icon(Icons.settings_outlined, size: 19, color: context.textSecondary),
                      label: 'Settings',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onClose();
                        context.push('/settings/ai');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clean geometric OVA wordmark for Oneova's main AI workspace.
class OvaWordmark extends StatelessWidget {
  final double fontSize;
  final bool showSubtag;

  const OvaWordmark({
    super.key,
    this.fontSize = 19.0,
    this.showSubtag = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brandBlue, AppColors.brandPink],
            ),
          ),
          child: const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.brandWhite),
        ),
        const SizedBox(width: 8),
        Text(
          'OVA',
          style: GoogleFonts.spaceGrotesk(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: context.textPrimary,
          ),
        ),
        if (showSubtag) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.28), width: 1.0),
            ),
            child: Text(
              'AI',
              style: GoogleFonts.inter(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.brandBlue,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final String? badge;
  final bool accentBadge;
  final VoidCallback onTap;

  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.badge,
    this.accentBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = context.isDark
        ? const Color(0xFF6366F1).withValues(alpha: 0.18)
        : const Color(0xFFEEF2FF);
    final activeColor = context.isDark
        ? const Color(0xFF818CF8)
        : const Color(0xFF4F46E5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: selected ? activeColor : context.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? (context.isDark ? const Color(0xFFE0E7FF) : const Color(0xFF1E1B4B))
                            : context.textPrimary,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: accentBadge
                            ? AppColors.brandPink.withValues(alpha: 0.14)
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: accentBadge
                              ? AppColors.brandPink.withValues(alpha: 0.4)
                              : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        badge!,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: accentBadge ? AppColors.brandPink : context.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerWorkspaceTile extends StatelessWidget {
  final OvaWorkspaceId workspace;
  final bool selected;
  final int? countBadge;
  final VoidCallback onTap;

  const _DrawerWorkspaceTile({
    required this.workspace,
    required this.selected,
    this.countBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? AppColors.brandBlue.withValues(alpha: context.isDark ? 0.12 : 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    workspace.icon,
                    size: 17,
                    color: selected ? AppColors.brandBlue : context.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workspace.label,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? context.textPrimary : context.textSecondary,
                      ),
                    ),
                  ),
                  if (countBadge != null) ...[
                    Text(
                      '$countBadge',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: context.textMuted,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(Icons.chevron_right_rounded, size: 17, color: context.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerFooterRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  const _DrawerFooterRow({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(width: 26, child: Center(child: leading)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 17, color: context.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

