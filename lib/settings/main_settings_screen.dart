import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/theme_provider.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/widgets/components.dart';
import '../providers/settings_provider.dart';
import '../auth/services/secure_logout_service.dart';
import 'services/platform_docs_cms_service.dart';
import 'services/settings_diagnostic_service.dart';
import 'services/settings_search_engine.dart';
import 'widgets/settings_kit.dart';

/// Main settings screen for Oneova.
/// Features:
/// - Executive high-density compact scale (38-42px tiles, Inter typography)
/// - Universal Dual-Mode (Light & Dark) theming
/// - Continuous Cloud & Device Auto-Save with real-time status pill
/// - Top Command-K Similarity & Fuzzy Search across all platform settings
/// - Autonomous Account Health & Diagnostics with 1-Tap AI Auto-Fix
/// - Visual error/warning highlights on affected settings tiles
class MainSettingsScreen extends ConsumerStatefulWidget {
  const MainSettingsScreen({super.key});

  @override
  ConsumerState<MainSettingsScreen> createState() => _MainSettingsScreenState();
}

class _MainSettingsScreenState extends ConsumerState<MainSettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<SettingsSearchResult> _searchResults = [];
  bool _isAutoFixing = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchInputChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchInputChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchInputChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
        _searchResults = query.isEmpty ? [] : SettingsSearchEngine.search(query);
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchResults = [];
    });
  }

  Future<void> _handleAutoFixAll() async {
    setState(() => _isAutoFixing = true);
    try {
      await SettingsDiagnosticService.autoFixAll(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'AI Auto-Fix applied! All platform issues resolved.',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAutoFixing = false);
      }
    }
  }

  Future<void> _handleAutoFixSingle(String issueId, String issueTitle) async {
    await SettingsDiagnosticService.autoFixIssue(ref, issueId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.brandBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          content: Text(
            'Resolved: $issueTitle',
            style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogCtx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: dialogCtx.border, width: 1.0),
        ),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: AppColors.brandPink, size: 22),
            const SizedBox(width: 10),
            Text(
              'Sign Out of Oneova?',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: dialogCtx.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Your active studio sessions and cloud preferences are safely saved. You will need to sign in again to access creator tools.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: dialogCtx.textSecondary,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dialogCtx.border, width: 1.0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: dialogCtx.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Sign Out',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(secureLogoutServiceProvider).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final healthReport = ref.watch(accountHealthProvider);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: StudioBackground(
        backgroundIcons: const [Icons.settings, Icons.tune, Icons.security_rounded],
        appBar: AppBar(
          title: Row(
            children: [
              Text(
                'Settings',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.topBarFg,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 10),
              // Live auto-save status (saving / saved / saved on device)
              const SettingsSaveIndicator(),
            ],
          ),
          centerTitle: false,
          backgroundColor: AppColors.brandBlue,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.push('/hub/home');
              }
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: context.topBarFg,
                size: 20,
              ),
              tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ],
        ),
        child: settingsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.brandBlue),
          ),
          error: (err, stack) => Center(
            child: Text(
              'Error loading settings: $err',
              style: TextStyle(color: AppColors.brandPink),
            ),
          ),
          data: (settings) {
            final profile = settings['profile'] as Map<String, dynamic>? ?? {};
            final displayName = profile['displayName']?.toString().isNotEmpty == true
                ? profile['displayName']
                : (user?.displayName ?? 'Studio Creator');

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Top Command-K Fuzzy & Similarity Search Bar
                _buildSearchBar(context),
                const SizedBox(height: 14),

                // If searching, render live search results
                if (_searchQuery.isNotEmpty) ...[
                  _buildSearchResultsSection(context, healthReport),
                  const SizedBox(height: 32),
                ] else ...[
                  // 2. Autonomous Account Health & Diagnostics Card
                  _buildAccountHealthCard(context, healthReport),
                  const SizedBox(height: 16),

                  // 3. Compact User Profile Summary
                  _buildUserProfileCard(context, displayName, user?.email, user?.photoURL),
                  const SizedBox(height: 14),

                  // 3b. Quick controls — one-tap, auto-saved toggles
                  _buildQuickControls(context, settings, isDark),
                  const SizedBox(height: 16),

                  // 4. Preferences Group
                  _buildSettingsGroup(
                    context,
                    'Preferences',
                    [
                      _buildSettingsTile(
                        context,
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Chat & Messaging',
                        subtitle: 'Bubble density, swipe-to-reply & tone',
                        route: '/settings/chat',
                        categoryKey: 'chat',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.phone_android_rounded,
                        title: 'App Settings',
                        subtitle: 'Calls, messaging, persistent chat history',
                        route: '/settings/app',
                        categoryKey: 'app',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.notifications_none_rounded,
                        title: 'Notifications',
                        subtitle: 'Push banners, badges & signature chimes',
                        route: '/settings/notifications',
                        categoryKey: 'notifications',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.auto_awesome_rounded,
                        title: 'AI Assistant',
                        subtitle: 'Ova\'s voice, tone and smart features',
                        route: '/settings/ai',
                        categoryKey: 'ai',
                        showDivider: false,
                        healthReport: healthReport,
                      ),
                    ],
                  ).animate().fadeIn(duration: 250.ms),

                  const SizedBox(height: 18),

                  // 4b. Display & Playback Group
                  _buildSettingsGroup(
                    context,
                    'Display & Playback',
                    [
                      _buildSettingsTile(
                        context,
                        icon: Icons.palette_rounded,
                        title: 'Appearance',
                        subtitle: 'Light / Dark, text size & motion',
                        route: '/settings/appearance',
                        categoryKey: 'appearance',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.smart_display_rounded,
                        title: 'Reels & Playback',
                        subtitle: 'Reels theme, auto-scroll, loop & haptics',
                        route: '/settings/reels',
                        categoryKey: 'playback',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.accessibility_new_rounded,
                        title: 'Accessibility',
                        subtitle: 'Contrast, large text & focus',
                        route: '/settings/accessibility',
                        categoryKey: 'accessibility',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.call_rounded,
                        title: 'Calls',
                        subtitle: 'Camera, mic & noise cancellation defaults',
                        route: '/settings/calls',
                        categoryKey: 'calls',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.sd_storage_rounded,
                        title: 'Storage & Data',
                        subtitle: 'Media auto-download & gallery saving',
                        route: '/settings/storage',
                        categoryKey: 'storage',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.videocam_rounded,
                        title: 'Camera & Live',
                        subtitle: 'Device Advisor, ceilings & Pro override',
                        route: '/settings/camera_and_live',
                        categoryKey: 'camera_and_live',
                        showDivider: false,
                        healthReport: healthReport,
                      ),
                    ],
                  ).animate().fadeIn(delay: 25.ms, duration: 250.ms),

                  const SizedBox(height: 18),

                  // 5. Integrations Group
                  _buildSettingsGroup(
                    context,
                    'Integrations',
                    [
                      _buildSettingsTile(
                        context,
                        icon: Icons.video_library_rounded,
                        title: 'YouTube Settings',
                        subtitle: 'Upload defaults, channel sync & comments',
                        route: '/yt/settings',
                        categoryKey: 'integrations',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.hub_rounded,
                        title: 'Social Accounts',
                        subtitle: 'Meta, Instagram, TikTok omnichannel sync',
                        route: '/social_hub',
                        categoryKey: 'integrations',
                        showDivider: false,
                        healthReport: healthReport,
                      ),
                    ],
                  ).animate().fadeIn(delay: 50.ms, duration: 250.ms),

                  const SizedBox(height: 18),

                  // 6. Security & Privacy Group
                  _buildSettingsGroup(
                    context,
                    'Security & Privacy',
                    [
                      _buildSettingsTile(
                        context,
                        icon: Icons.lock_outline_rounded,
                        title: 'Privacy & Security',
                        subtitle: 'App PIN, biometric protection, 2FA & data',
                        route: '/settings/privacy',
                        categoryKey: 'privacy',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.gavel_rounded,
                        title: 'Rules, Docs & Legal',
                        subtitle: 'Features, Community rules, Terms, Privacy & African laws',
                        route: '/legal',
                        categoryKey: 'legal',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      if (ref.watch(isPlatformDocsAdminProvider).value == true)
                        _buildSettingsTile(
                          context,
                          icon: Icons.edit_note_rounded,
                          title: 'Live Docs & Rules Admin CMS',
                          subtitle: 'Real-time App + Website editor & revision rollback',
                          route: '/settings/admin-cms',
                          categoryKey: 'legal',
                          showDivider: true,
                          healthReport: healthReport,
                        ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.rate_review_outlined,
                        title: 'Feedback',
                        subtitle: 'Tell us what you wish Oneova had',
                        route: '/feedback',
                        categoryKey: 'feedback',
                        showDivider: true,
                        healthReport: healthReport,
                      ),
                      _buildSettingsTile(
                        context,
                        icon: Icons.info_outline_rounded,
                        title: 'About Oneova',
                        subtitle: 'Version, promises & policy shortcuts',
                        route: '/settings/about',
                        categoryKey: 'about',
                        showDivider: false,
                        healthReport: healthReport,
                      ),
                    ],
                  ).animate().fadeIn(delay: 100.ms, duration: 250.ms),

                  const SizedBox(height: 24),

                  // 7. Destructive Sign Out Tile with Confirmation Safeguard
                  _buildSignOutTile(context),
                  const SizedBox(height: 40),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Compact Command-K Search Bar
  Widget _buildSearchBar(BuildContext context) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    final shortcutLabel = isMac ? '⌘K' : 'Ctrl+K';

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: _searchFocusNode.hasFocus ? AppColors.brandBlue : context.border,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 19, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search all settings, privacy, AI, audio...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 12.0,
                  color: context.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: _clearSearch,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Text(
                shortcutLabel,
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: context.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Render similarity & fuzzy search results
  Widget _buildSearchResultsSection(BuildContext context, AccountHealthReport healthReport) {
    if (_searchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 36, color: context.textMuted),
            const SizedBox(height: 10),
            Text(
              'No settings matching "$_searchQuery"',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try searching: notifications, passkey, tone, copilot, or theme',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: context.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                'RESULTS (${_searchResults.length})',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.brandBlue,
                ),
              ),
              const Spacer(),
              Text(
                'Ranked by similarity',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
        ),
        OneovaCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < _searchResults.length; i++) ...[
                _buildSearchResultTile(context, _searchResults[i], healthReport),
                if (i < _searchResults.length - 1)
                  Divider(height: 1, thickness: 1, color: context.border, indent: 56, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultTile(BuildContext context, SettingsSearchResult result, AccountHealthReport healthReport) {
    final item = result.item;
    final matchPercent = (result.score * 100).round();
    final hasIssue = healthReport.issues.any((iss) =>
        (item.settingKey != null && iss.settingKey == item.settingKey) ||
        iss.route == item.route);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push(item.route);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: hasIssue
                    ? AppColors.brandPink.withValues(alpha: 0.12)
                    : AppColors.brandBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasIssue
                      ? AppColors.brandPink.withValues(alpha: 0.4)
                      : AppColors.brandBlue.withValues(alpha: 0.2),
                  width: 1.0,
                ),
              ),
              child: Icon(
                item.icon,
                size: 18,
                color: hasIssue ? AppColors.brandPink : AppColors.brandBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (hasIssue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5), width: 1.0),
                          ),
                          child: Text(
                            'ATTENTION',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.brandPink,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.0,
                      color: context.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Text(
                '$matchPercent%',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
          ],
        ),
      ),
    );
  }

  /// Autonomous Account Health & Diagnostics Card
  Widget _buildAccountHealthCard(BuildContext context, AccountHealthReport healthReport) {
    final hasIssues = healthReport.hasIssues;
    final score = healthReport.healthScore;

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: hasIssues
              ? AppColors.brandPink.withValues(alpha: 0.6)
              : AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasIssues
                ? AppColors.brandPink.withValues(alpha: 0.08)
                : AppColors.brandBlue.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Status Header Row
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: hasIssues ? AppColors.brandPink : const Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Oneova Autonomous Health & Diagnostics',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      hasIssues
                          ? 'Background monitor detected ${healthReport.issues.length} optimization issue${healthReport.issues.length > 1 ? 's' : ''}'
                          : 'Continuous 24/7 background audit active · Studio fully fortified',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: hasIssues ? AppColors.brandPink : context.textMuted,
                        fontWeight: hasIssues ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasIssues
                      ? AppColors.brandPink.withValues(alpha: 0.14)
                      : const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: hasIssues
                        ? AppColors.brandPink.withValues(alpha: 0.4)
                        : const Color(0xFF10B981).withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  '$score% Integrity',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: hasIssues ? AppColors.brandPink : const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),

          if (hasIssues) ...[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: context.border),
            const SizedBox(height: 10),

            // Render list of issues
            for (final issue in healthReport.issues) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: issue.severity == DiagnosticSeverity.error
                            ? AppColors.brandPink.withValues(alpha: 0.2)
                            : (issue.severity == DiagnosticSeverity.warning
                                ? AppColors.brandPink.withValues(alpha: 0.14)
                                : AppColors.brandBlue.withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        issue.severity.name.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: issue.severity == DiagnosticSeverity.info
                              ? AppColors.brandBlue
                              : AppColors.brandPink,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            issue.title,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            issue.description,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: context.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (issue.canAutoFix)
                      SizedBox(
                        height: 26,
                        child: OutlinedButton(
                          onPressed: () => _handleAutoFixSingle(issue.id, issue.title),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            backgroundColor: AppColors.brandBlue.withValues(alpha: 0.08),
                          ),
                          child: Text(
                            issue.fixLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Master 1-Tap AI Auto-Fix All Button
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _isAutoFixing ? null : _handleAutoFixAll,
                icon: _isAutoFixing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: Text(
                  _isAutoFixing ? 'Applying AI Optimizations...' : 'AI Auto-Fix All Issues',
                  style: GoogleFonts.inter(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Compact User Profile Summary Card
  Widget _buildUserProfileCard(BuildContext context, String displayName, String? email, String? photoUrl) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.brandBlue,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                    style: GoogleFonts.inter(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w800),
                  )
                : null,
          ),
          const SizedBox(width: 12),
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
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 15),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email ?? 'Oneova Studio Creator',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: context.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: () => context.push('/settings/profile'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.border, width: 1.0),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                backgroundColor: context.surfaceMid,
              ),
              child: Text(
                'Edit',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Clean group container for settings tiles
  /// Grid of small one-tap toggles. Each tap auto-saves (theme on device,
  /// the rest to `user_settings/{uid}`).
  Widget _buildQuickControls(BuildContext context, Map<String, dynamic> settings, bool isDark) {
    final notifications = settingsCategory(settings, 'notifications');
    final chat = settingsCategory(settings, 'chat');
    final accessibility = settingsCategory(settings, 'accessibility');
    final playback = settingsCategory(settings, 'playback');
    final storage = settingsCategory(settings, 'storage');
    final privacy = settingsCategory(settings, 'privacy');

    Widget toggle(IconData icon, String label, String category, Map<String, dynamic> data, String key, bool fallback) {
      final value = data[key] as bool? ?? fallback;
      return SettingsQuickToggle(
        icon: icon,
        label: label,
        active: value,
        onTap: () => settingsWrite(ref, category: category, current: data, key: key, value: !value, label: label),
      );
    }

    final tiles = <Widget>[
      SettingsQuickToggle(
        icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
        label: isDark ? 'Dark' : 'Light',
        active: isDark,
        onTap: () => ref.read(themeProvider.notifier).toggleTheme(),
      ),
      toggle(Icons.notifications_active_rounded, 'Banners', 'notifications', notifications, 'inAppEnabled', true),
      toggle(Icons.volume_up_rounded, 'Sounds', 'chat', chat, 'chatSoundEffects', true),
      toggle(Icons.public_rounded, 'Public', 'privacy', privacy, 'publicProfile', true),
      toggle(Icons.keyboard_double_arrow_down_rounded, 'Auto-scroll', 'playback', playback, 'autoScroll', false),
      toggle(Icons.repeat_rounded, 'Loop', 'playback', playback, 'loopVideos', true),
      toggle(Icons.animation_rounded, 'Less motion', 'accessibility', accessibility, 'reduceMotion', false),
      toggle(Icons.wifi_rounded, 'Wi-Fi media', 'storage', storage, 'autoDownloadWifi', true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'QUICK CONTROLS',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
          children: tiles,
        ),
      ],
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildSettingsGroup(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
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
            children: children,
          ),
        ),
      ],
    );
  }

  /// Compact settings tile (38-42px scale) with error & warning highlights
  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    required String categoryKey,
    required bool showDivider,
    required AccountHealthReport healthReport,
  }) {
    // Check if this tile has an active diagnostic issue
    final activeIssue = healthReport.issues.where((i) => i.category == categoryKey || i.route == route).firstOrNull;
    final hasWarning = activeIssue != null;

    return Column(
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            context.push(route);
          },
          child: Container(
            decoration: BoxDecoration(
              color: hasWarning ? AppColors.brandPink.withValues(alpha: 0.04) : Colors.transparent,
              border: hasWarning
                  ? Border(left: BorderSide(color: AppColors.brandPink, width: 2.5))
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                SettingsIconChip(
                  icon: icon,
                  color: hasWarning ? AppColors.brandPink : AppColors.brandBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasWarning) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
                              ),
                              child: Text(
                                'ATTENTION',
                                style: GoogleFonts.inter(
                                  fontSize: 8.0,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.brandPink,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        hasWarning ? activeIssue.title : subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: hasWarning ? AppColors.brandPink : context.textMuted,
                          fontWeight: hasWarning ? FontWeight.w500 : FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (hasWarning && activeIssue.canAutoFix)
                  GestureDetector(
                    onTap: () => _handleAutoFixSingle(activeIssue.id, activeIssue.title),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'AI Fix',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: context.border,
            indent: 50,
            endIndent: 12,
          ),
      ],
    );
  }

  /// Sign Out Tile with Required Confirmation Dialog Safeguard
  Widget _buildSignOutTile(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: InkWell(
        onTap: () => _confirmSignOut(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded, color: AppColors.brandPink, size: 17),
              const SizedBox(width: 8),
              Text(
                'Sign Out of Oneova',
                style: GoogleFonts.inter(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPink,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
