import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../backend/notification_service.dart';
import '../shared/widgets/theme_toggle_button.dart';
import '../backend/remote_connect_service.dart';
import '../backend/webrtc_desktop_service.dart';
import 'package:popover/popover.dart';
import '../backend/project_repository.dart';
import '../auth/auth_repository.dart';
import '../auth/services/secure_logout_service.dart';
import '../backend/user_service.dart';
import '../shared/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class HubHomeScreen extends ConsumerStatefulWidget {
  const HubHomeScreen({super.key});

  @override
  ConsumerState<HubHomeScreen> createState() => _HubHomeScreenState();
}

class _HubHomeScreenState extends ConsumerState<HubHomeScreen> {
  bool _showAllActions = false;

  PopupMenuItem<String> _buildAdvancedPopupItem(String value, IconData icon, String label, {Color color = Colors.white}) {
    return PopupMenuItem(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 16),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildHeader(
                context,
                ref,
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
              const SizedBox(height: 20),
              _buildGreeting().animate().fadeIn(
                delay: 100.ms,
                duration: 400.ms,
              ),
              const SizedBox(height: 20),
              _buildSystemStatsSection(context, ref).animate().fadeIn(delay: 125.ms, duration: 350.ms),
              const SizedBox(height: 24),
              _buildQuickActionsSection(
                context,
              ).animate().fadeIn(delay: 150.ms, duration: 350.ms),
              const SizedBox(height: 20),
              _buildLiveUsersSection(
                context,
                ref,
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 20),
              _buildConnectedStudio(
                context,
                ref,
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 28),
              _buildProjectsSection(context, ref).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 28),
              _buildUpdatesSection(context, ref).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            child: const CircleAvatar(
              radius: 20,
              backgroundImage: AssetImage('assets/logos/app_logo.png'),
            ),
          ),
          Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Row(
            children: [
              Builder(
                builder: (context) {
                  return IconButton(
                    icon: Icon(
                      Icons.add,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    onPressed: () => _showQuickCreateMenu(context),
                  );
                }
              ),
              Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_none,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    onPressed: () => context.push('/notifications'),
                  ),
                  Consumer(
                    builder: (context, ref, child) {
                      final notifsState = ref.watch(notificationProvider);
                      final unreadCount =
                          notifsState.value?.where((n) => !n.isRead).length ??
                          0;
                      if (unreadCount == 0) return const SizedBox.shrink();

                      return Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Consumer(
                builder: (context, ref, child) {
                  final authState = ref.watch(authStateProvider);
                  final user = authState.value;
                  final photoUrl = user?.photoURL;
                  
                  return PopupMenuButton<String>(
                    offset: const Offset(0, 56),
                    color: AppColors.mpepeMaroon,
                    elevation: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide.none,
                    ),
                    onSelected: (value) async {
                      if (value == 'upload') context.push('/upload/global');
                      if (value == 'analytics') context.push('/social_hub/analytics');
                      if (value == 'earnings') context.push('/yt/dashboard');
                      if (value == 'profile') context.push('/auth/profile');
                      if (value == 'settings') context.push('/settings/main');
                      if (value == 'logout') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.darkSurface,
                            title: const Text('Confirm Logout', style: TextStyle(color: Colors.white)),
                            content: const Text('Are you sure you want to log out?', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.mpepeMaroon,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Logout'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(secureLogoutServiceProvider).logout();
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'header',
                        enabled: false,
                        child: Center(
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundImage: photoUrl != null 
                                  ? NetworkImage(photoUrl) as ImageProvider
                                  : const AssetImage('assets/logos/app_logo.png'),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                      _buildAdvancedPopupItem('upload', Icons.cloud_upload_rounded, 'Upload'),
                      _buildAdvancedPopupItem('analytics', Icons.bar_chart_rounded, 'Analytics'),
                      _buildAdvancedPopupItem('earnings', Icons.monetization_on_rounded, 'Earnings'),
                      _buildAdvancedPopupItem('profile', Icons.person_rounded, 'Profile'),
                      _buildAdvancedPopupItem('settings', Icons.settings_rounded, 'Settings'),
                      _buildAdvancedPopupItem('logout', Icons.logout_rounded, 'Logout', color: Colors.white),
                    ],
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2.0,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundImage: photoUrl != null 
                          ? NetworkImage(photoUrl) as ImageProvider
                          : const AssetImage('assets/logos/app_logo.png'),
                      ),
                    ),
                  );
                }
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildGreeting() {
    return Consumer(
      builder: (context, ref, child) {
        final authState = ref.watch(authStateProvider);
        final user = authState.value;
        final name = user?.displayName?.split(' ').first ?? 'Creator';

        final hour = DateTime.now().hour;
        String greeting;
        String emoji;
        if (hour < 5) {
          greeting = 'Still grinding';
          emoji = '🌙';
        } else if (hour < 12) {
          greeting = 'Good morning';
          emoji = '☀️';
        } else if (hour < 17) {
          greeting = 'Good afternoon';
          emoji = '🎵';
        } else if (hour < 20) {
          greeting = 'Good evening';
          emoji = '🎬';
        } else {
          greeting = 'Late session';
          emoji = '🔥';
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$greeting, ',
                      style: TextStyle(
                        fontSize: 24,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    TextSpan(
                      text: name,
                      style: TextStyle(
                        fontSize: 24,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'What are you working on today?',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSystemStatsSection(BuildContext context, WidgetRef ref) {
    final webrtcState = ref.watch(webrtcDesktopProvider);
    final String webrtcStatusText = 'Active'; // Hardcoded for mockup as dashboard manages multiple computers now
    final Color webrtcStatusColor = Colors.greenAccent;

    final stats = [
      _SystemStat('System Health', '99.9%', 'All services operational', Icons.monitor_heart_rounded, Colors.greenAccent),
      _SystemStat('Active Tasks', '12', 'Processing in background', Icons.task_alt_rounded, AppColors.mpepeMaroon),
      _SystemStat('Desktop Monitor', webrtcStatusText, 'Real-time WebRTC', Icons.desktop_mac_rounded, webrtcStatusColor),
      _SystemStat('Network Sync', 'Optimal', 'Low latency connection', Icons.sync_rounded, AppColors.mpepeMaroon),
      _SystemStat('AI Voice Mode', 'Standby', 'Ready for voice commands', Icons.mic_rounded, AppColors.mpepeMaroon),
      _SystemStat('Studio Storage', '45% Used', 'Cloud sync active', Icons.cloud_done_rounded, AppColors.mpepeMaroon),
      _SystemStat('Daily Uploads', '8/50', 'Omnichannel queue', Icons.rocket_launch_rounded, AppColors.mpepeMaroon),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'System Overview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            children: stats.map((stat) => _SystemStatCard(stat: stat)).toList(),
          ),
        ),
      ],
    );
  }

  /// Safaricom-style grid for Quick Actions
  Widget _buildQuickActionsSection(BuildContext context) {
    final actions = [
      _QuickAction(
        Icons.qr_code_scanner_rounded,
        'Connect',
        '/connect',
        const Color(0xFF22C55E),
        'Link Devices',
      ),
      _QuickAction(
        Icons.mic_rounded,
        'Audio',
        '/audio/dashboard',
        const Color(0xFF14B8A6),
        'Mix & Master',
      ),
      _QuickAction(
        Icons.videocam_rounded,
        'Video',
        '/video/dashboard',
        const Color(0xFF8B5CF6),
        'Edit & Render',
      ),
      _QuickAction(
        Icons.smart_display_rounded,
        'YouTube',
        '/yt/dashboard',
        const Color(0xFFEF4444),
        'Manage channel',
      ),
      _QuickAction(
        Icons.hub_rounded,
        'Social',
        '/social_hub',
        const Color(0xFF3B82F6),
        'Cross-post',
      ),
      _QuickAction(
        Icons.folder_rounded,
        'Projects',
        '/video/projects',
        const Color(0xFFD4AF37),
        'All assets',
      ),
      _QuickAction(
        Icons.chat_bubble_rounded,
        'Messages',
        '/hub/messages',
        const Color(0xFFEC4899),
        'Team chat',
      ),
      _QuickAction(
        Icons.settings_suggest_rounded,
        'Settings',
        '/settings',
        const Color(0xFF64748B),
        'Preferences',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              return _buildGridActionCard(context, actions[index])
                  .animate()
                  .fadeIn(delay: (index * 30).ms, duration: 300.ms)
                  .scaleXY(begin: 0.8, duration: 300.ms);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGridActionCard(BuildContext context, _QuickAction action) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => context.push(action.route),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.mpepeMaroon.withValues(alpha: isDark ? 0.4 : 0.25), // Increased alpha for boldness
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.mpepeMaroon.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.mpepeMaroon,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.mpepeMaroon.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(action.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (action.description != null) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  action.description!,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveUsersSection(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(userProvider);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Live Hub Users',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              usersAsync.when(
                data: (users) {
                  final activeUsers = users.where((u) => u.status == 'active').length;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.mpepeMaroon,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.mpepeMaroon.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.4, end: 1.0, duration: 800.ms),
                        const SizedBox(width: 6),
                        Text(
                          '$activeUsers / ${users.length} Online',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              )
            ],
          ),
          const SizedBox(height: 12),
          usersAsync.when(
            data: (users) {
              if (users.isEmpty) return const Text('No users found.');
              return SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final isOnline = user.status == 'active';
                    final initials = user.fullName.isNotEmpty 
                      ? user.fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() : '').take(2).join()
                      : '?';
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Tooltip(
                        message: '${user.fullName} (${user.role})',
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.primaries[index % Colors.primaries.length].withValues(alpha: 0.2),
                              child: Text(
                                initials,
                                style: TextStyle(
                                  color: Colors.primaries[index % Colors.primaries.length],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            if (isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error loading users', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required String description,
    required Widget child,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.mpepeMaroon.withValues(alpha: 0.3),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.mpepeMaroon.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedStudio(BuildContext context, WidgetRef ref) {
    final remoteState = ref.watch(remoteConnectProvider);
    final webrtcState = ref.watch(webrtcDesktopProvider);

    return _buildSectionCard(
      context: context,
      title: 'Connected Computers',
      description: 'Live monitor of your registered devices.',
      trailing: IconButton(
        icon: Icon(
          Icons.add_circle,
          color: AppColors.mpepeMaroon,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () => _showConnectWizard(context, ref),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (remoteState.linkedComputers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  'No computers linked yet.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          if (remoteState.linkedComputers.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: remoteState.linkedComputers.map((computer) {
                  final connection = webrtcState.connections[computer.id];
                  final isConnected = connection?.status == WebRTCStatus.connected;
                  
                  // Auto-connect if it's online but not connected
                  if (computer.isOnline && connection == null) {
                    Future.microtask(() => ref.read(webrtcDesktopProvider.notifier).connect(computer.id));
                  }

                  return GestureDetector(
                    onTap: () {
                      ref.read(remoteConnectProvider.notifier).setActiveComputer(computer.id);
                      context.push('/remote_chat');
                    },
                    child: Container(
                      width: 160,
                      height: 110,
                      margin: const EdgeInsets.only(right: 16.0),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isConnected ? AppColors.mpepeMaroon : Colors.white24,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (isConnected && connection?.renderer != null)
                              RTCVideoView(
                                connection!.renderer!,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                              )
                            else
                              Icon(
                                Icons.computer,
                                size: 40,
                                color: computer.isOnline ? Colors.white : Colors.white38,
                              ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                color: Colors.black54,
                                child: Text(
                                  computer.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isConnected 
                                      ? Colors.greenAccent 
                                      : (computer.isOnline ? Colors.orange : Colors.red),
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildProjectsSection(BuildContext context, WidgetRef ref) {
    return _buildSectionCard(
      context: context,
      title: 'My projects',
      description: 'Recent active assets and timelines.',
      trailing: Text(
        'View all',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.mpepeMaroon,
        ),
      ),
      child: _buildProjectsList(context, ref),
    );
  }

  Widget _buildProjectsList(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsStreamProvider);

    return SizedBox(
      height: 140,
      child: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return Center(
              child: Text(
                'No active projects',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            );
          }
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return _buildProjectCard(
                context,
                project,
              ).animate().fadeIn(delay: 100.ms).slideX(begin: 0.1);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, StudioProject project) {
    return Container(
      width: 240,
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF631D26), // Mpepe Maroon
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  project.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.more_horiz, color: Colors.white),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'High-priority task for immediate review. Requires team collaboration and media processing.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            project.category,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                project.status,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              // Simulated Assigned User Avatars
              Row(
                children: [
                  _buildUserAvatar(context, 'Alice', 'Editor', 'A'),
                  const SizedBox(width: -8),
                  _buildUserAvatar(context, 'Bob', 'Audio Engineer', 'B'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(
    BuildContext context,
    String name,
    String title,
    String letter,
  ) {
    return Tooltip(
      message: '$name\\n$title',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF631D26), width: 2),
        ),
        child: CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.2),
          child: Text(
            letter,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpdatesSection(BuildContext context, WidgetRef ref) {
    return _buildSectionCard(
      context: context,
      title: 'Updates & Feed',
      description: 'Latest notifications and hub activity.',
      trailing: Icon(Icons.sort, color: AppColors.mpepeMaroon, size: 20),
      child: _buildUpdatesFeedList(context, ref),
    );
  }

  Widget _buildUpdatesFeedList(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationProvider);

    return notificationsAsync.when(
      data: (notifications) {
        if (notifications.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'No new updates',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: notifications.take(5).length,
          itemBuilder: (context, index) {
            final notif = notifications[index];
            // Map type to icon
            IconData icon = Icons.notifications;
            if (notif.type == 'system') icon = Icons.admin_panel_settings;
            if (notif.type == 'task') icon = Icons.task_alt;
            if (notif.type == 'social') icon = Icons.share;

            return _buildFeedItem(
              context,
              notif.type.toUpperCase(),
              notif.message,
              _formatTime(notif.createdAt),
              icon,
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildFeedItem(
    BuildContext context,
    String category,
    String content,
    String time,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _showQuickCreateMenu(BuildContext context) {
    showPopover(
      context: context,
      bodyBuilder: (context) {
        return Container(
          width: 290,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.mpepeMaroon.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Create',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildQuickCreateItem(context, Icons.video_call_rounded, 'New Video', 'Premiere project'),
                  _buildQuickCreateItem(context, Icons.music_note_rounded, 'New Audio', 'Logic/FL session'),
                  _buildQuickCreateItem(context, Icons.schedule_send_rounded, 'Schedule Post', 'Social media'),
                  _buildQuickCreateItem(context, Icons.link_rounded, 'Connect App', 'Link software'),
                ],
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, duration: 300.ms, curve: Curves.easeOutQuad),
            ],
          ),
        );
      },
      direction: PopoverDirection.bottom,
      backgroundColor: Colors.transparent,
      arrowHeight: 12,
      arrowWidth: 24,
    );
  }

  Widget _buildQuickCreateItem(BuildContext context, IconData icon, String title, String subtitle) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        if (title == 'Connect App') {
          _showConnectWizard(context, ref);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting: $title...')));
        }
      },
      child: Container(
        width: 123,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.mpepeMaroon,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _showConnectWizard(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) {
        bool isCloudLoading = false;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: AppColors.mpepeMaroon,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Connect a Studio Application',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pair your device with DaVinci Resolve, Premiere Pro, Logic Pro, or FL Studio.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      
                      // Option 1: Cloud Sync (Recommended)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          alignment: Alignment.centerLeft,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: isCloudLoading 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 28),
                        label: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Link via MPEPE Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            SizedBox(height: 2),
                            Text('Auto-connect to any logged-in desktop.', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                        onPressed: isCloudLoading ? null : () async {
                          setState(() => isCloudLoading = true);
                          await Future.delayed(const Duration(seconds: 2));
                          if (context.mounted) {
                            ref.read(remoteConnectProvider.notifier).linkComputer('cloud-sync-user');
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Connected via Cloud Sync!'), backgroundColor: Colors.green),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      // Option 2: Scan QR
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          alignment: Alignment.centerLeft,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
                        label: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            SizedBox(height: 2),
                            Text('Scan the code shown in your desktop plugin.', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          context.push('/qr_scanner');
                        },
                      ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white30)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('OR MANUAL CODE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                            Expanded(child: Divider(color: Colors.white30)),
                          ],
                        ),
                      ),
                      
                      const Text(
                        'One-Time Session Code',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        style: const TextStyle(color: Colors.white, letterSpacing: 2.0, fontWeight: FontWeight.bold),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'e.g. MPEPE-9X42',
                          hintStyle: const TextStyle(color: Colors.white54, letterSpacing: 0, fontWeight: FontWeight.normal),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.password_rounded, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.mpepeMaroon,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            ref
                                .read(remoteConnectProvider.notifier)
                                .linkComputer('test-session');
                          },
                          child: const Text(
                            'Connect Session',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

}


/// Simple immutable data class for quick-action chips.
class _QuickAction {
  final IconData icon;
  final String label;
  final String route;
  final Color color;
  final String? description;
  const _QuickAction(this.icon, this.label, this.route, this.color, [this.description]);
}

class _SystemStat {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  
  const _SystemStat(this.title, this.value, this.subtitle, this.icon, this.iconColor);
}

class _SystemStatCard extends StatelessWidget {
  final _SystemStat stat;

  const _SystemStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.mpepeMaroon.withValues(alpha: 0.3),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.mpepeMaroon.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stat.icon, color: stat.iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stat.title,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            stat.value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.subtitle,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
