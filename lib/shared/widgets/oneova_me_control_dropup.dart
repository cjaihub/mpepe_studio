import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../backend/remote_connect_service.dart';
import '../../shared/theme/app_theme.dart';
import 'oneova_profile_sidebar_drawer.dart';

final currentUserProfileProvider = StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data());
});

/// Drop-up sidebar menu shown when tapping "Me" on the OneOva bottom navigation bar.
/// Provides direct profile controls, computer windows remote control, studio news, and quick settings.
/// Fully wired for global Light and Dark mode with a compact, executive aesthetic.
class OneOvaMeControlDropUp extends ConsumerWidget {
  const OneOvaMeControlDropUp({super.key});

  static void show(BuildContext context) {
    OneovaProfileSidebarDrawer.show(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final userAsync = ref.watch(currentUserProfileProvider);
    final remoteState = ref.watch(remoteConnectProvider);
    final hasActiveComputer = remoteState.activeComputerId != null;

    final displayName = userAsync.maybeWhen(
      data: (user) => (user?['displayName'] ?? user?['name'] ?? currentUser?.displayName ?? 'OneOva Creator').toString(),
      orElse: () => currentUser?.displayName ?? 'OneOva Creator',
    );
    final handle = userAsync.maybeWhen(
      data: (user) => '@${user?['username'] ?? user?['handle'] ?? 'creator'}',
      orElse: () => '@creator',
    );
    final avatarUrl = userAsync.maybeWhen(
      data: (user) => user?['photoUrl'] ?? user?['avatarUrl'] ?? currentUser?.photoURL,
      orElse: () => currentUser?.photoURL,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(
          color: context.border,
          width: 1.0,
        ),
        boxShadow: context.isDark
            ? AppShadows.glow(AppColors.brandBlue, radius: 24, spread: 1)
            : AppShadows.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle Bar
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Header Row: OneOva Creator Hub label & close icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.brandPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'ONEOVA CREATOR HUB',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.textPrimary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Scrollable Menu Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. User Profile Control Card
                    _buildUserProfileCard(
                      context: context,
                      displayName: displayName,
                      handle: handle,
                      avatarUrl: avatarUrl,
                    ),

                    const SizedBox(height: 12),

                    // 2. Computer Windows Remote Control Card
                    _buildWorkstationControlCard(
                      context: context,
                      hasActiveComputer: hasActiveComputer,
                      activeComputerName: remoteState.linkedComputers.isNotEmpty
                          ? remoteState.linkedComputers.first.name
                          : 'Desktop Studio',
                    ),

                    const SizedBox(height: 16),

                    // 3. Drop-up Sidebar News & Updates
                    _buildSidebarNewsSection(context),

                    const SizedBox(height: 16),

                    // 4. Quick Studio Controls Grid
                    _buildQuickStudioControls(context),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// User profile card with direct link to user profile controls.
  Widget _buildUserProfileCard({
    required BuildContext context,
    required String displayName,
    required String handle,
    required String? avatarUrl,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar with glowing border
              Container(
                padding: const EdgeInsets.all(2.0),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.brandPink, AppColors.brandBlue],
                  ),
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: context.surface,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),

              // Name & Handle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.verified, size: 15, color: AppColors.brandBlue),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      handle,
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Direct Button: Takes user directly to their user profile control
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/profile/me');
              },
              icon: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
              label: Text(
                'User Profile & Controls',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Workstation & Computer Windows Remote Control card.
  Widget _buildWorkstationControlCard({
    required BuildContext context,
    required bool hasActiveComputer,
    required String activeComputerName,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: hasActiveComputer
              ? AppColors.brandBlue.withValues(alpha: 0.5)
              : context.border,
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () {
            Navigator.of(context).pop();
            context.push('/remote_control');
          },
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasActiveComputer
                            ? AppColors.brandBlue.withValues(alpha: 0.15)
                            : (context.isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        Icons.desktop_mac_rounded,
                        color: hasActiveComputer ? AppColors.brandBlue : context.textSecondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Computer Windows Control',
                                style: GoogleFonts.inter(
                                  color: context.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: hasActiveComputer
                                      ? Colors.green.withValues(alpha: 0.18)
                                      : Colors.amber.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  border: Border.all(
                                    color: hasActiveComputer
                                        ? Colors.greenAccent.withValues(alpha: 0.4)
                                        : Colors.amber.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  hasActiveComputer ? 'PAIRED' : 'STANDBY',
                                  style: GoogleFonts.inter(
                                    color: hasActiveComputer ? (context.isDark ? Colors.greenAccent : Colors.green[800]) : (context.isDark ? Colors.amberAccent : Colors.amber[900]),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Remote control OneOva Studio Engine & desktop workstation windows.',
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: context.textMuted, size: 14),
                  ],
                ),
                const SizedBox(height: 10),
                // Feature chips row
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _buildFeatureChip(context, Icons.play_circle_outline, 'NLE Timeline'),
                    _buildFeatureChip(context, Icons.video_library_outlined, '4K Stream'),
                    _buildFeatureChip(context, Icons.mouse_outlined, 'Mouse & Macros'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: context.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.brandBlue),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Drop-up sidebar news & updates.
  Widget _buildSidebarNewsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.newspaper_rounded, size: 14, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Text(
                  'STUDIO NEWS & UPDATES',
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            Text(
              'LIVE BULLETIN',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // News item 1
        _buildNewsCard(
          context: context,
          tag: 'SYSTEM UPDATE',
          tagColor: AppColors.brandBlue,
          title: 'OneOva Studio v2.0 Released',
          description: 'Ultra-low latency desktop bridge enabled with native OneOva Studio connectors.',
          timeAgo: 'Just now',
        ),
        const SizedBox(height: 8),

        // News item 2
        _buildNewsCard(
          context: context,
          tag: 'TRENDING AUDIO',
          tagColor: AppColors.brandPink,
          title: 'New Creator Soundboard Added',
          description: 'Obsidian Cine Pro LUT and viral audio tracks now available in the Camera & Story Studio.',
          timeAgo: '2h ago',
        ),
      ],
    );
  }

  Widget _buildNewsCard({
    required BuildContext context,
    required String tag,
    required Color tagColor,
    required String title,
    required String description,
    required String timeAgo,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.inter(
                    color: tagColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                timeAgo,
                style: GoogleFonts.inter(
                  color: context.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2.5),
          Text(
            description,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 11.0,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Quick Studio controls grid: Linked Devices, QR Scanner, Analytics, Settings.
  Widget _buildQuickStudioControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STUDIO CONTROLS',
          style: GoogleFonts.inter(
            color: context.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildControlTile(
              context: context,
              icon: Icons.devices_rounded,
              label: 'Linked Devices',
              route: '/auth/linked_devices',
            ),
            const SizedBox(width: 8),
            _buildControlTile(
              context: context,
              icon: Icons.qr_code_scanner_rounded,
              label: 'Pair Station',
              route: '/hub/qr_scanner',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildControlTile(
              context: context,
              icon: Icons.insights_rounded,
              label: 'Analytics',
              route: '/social_hub/analytics',
            ),
            const SizedBox(width: 8),
            _buildControlTile(
              context: context,
              icon: Icons.settings_rounded,
              label: 'Settings',
              route: '/settings',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String route,
  }) {
    return Expanded(
      child: Material(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            Navigator.of(context).pop();
            context.push(route);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.brandBlue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
