import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../backend/notifications/providers/notification_service.dart';
import '../backend/notifications/models/app_notification.dart';
import '../backend/remote_connect_service.dart';
import '../backend/webrtc_desktop_service.dart';
import 'package:popover/popover.dart';
import '../backend/project_repository.dart';
import '../auth/auth_repository.dart';
import '../auth/services/secure_logout_service.dart';
import '../backend/system/system_status_service.dart';
import '../backend/system/system_status_models.dart';
import '../backend/automations/workflow_engine.dart';
import '../backend/teams/team_service.dart';
import '../backend/social_inbox_repository.dart';
import '../shared/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'internal_browser_screen.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

// ─────────────────────────────────────────────────────────────
// Data models for the Quick Actions grid — must be declared
// before the widget/state classes that reference them as types.
// ─────────────────────────────────────────────────────────────

// Removed legacy QuickAction classes for the new Accordion navigation

class CreatorDashboardDrawer extends ConsumerStatefulWidget {
  const CreatorDashboardDrawer({super.key});

  @override
  ConsumerState<CreatorDashboardDrawer> createState() => _CreatorDashboardDrawerState();
}

class _CreatorDashboardDrawerState extends ConsumerState<CreatorDashboardDrawer> {
  // ignore: unused_field
  final bool _showAllActions = false;

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
    return Drawer(
      child: SafeArea(
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
              const SizedBox(height: 24),
              _buildAccordionMenu(
                context,
              ).animate().fadeIn(delay: 150.ms, duration: 350.ms),
              const SizedBox(height: 28),
              _buildProjectsSection(context, ref).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 28),
              _buildUpdatesSection(context, ref).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 16),
              _buildLiveUsersSection(
                context,
                ref,
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 16),
              _buildSystemStatsSection(
                context,
                ref,
              ).animate().fadeIn(delay: 420.ms),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 16),
              _buildConnectedStudio(
                context,
                ref,
              ).animate().fadeIn(delay: 450.ms),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.brandBlue, width: 2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => context.push('/auth/profile'),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
              child: const CircleAvatar(
                radius: 20,
                backgroundImage: AssetImage('assets/images/oneova_logo.jpg'),
              ),
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
                      final unreadCountAsync = ref.watch(unreadNotificationCountProvider);
                      final unreadCount = unreadCountAsync.value ?? 0;
                      if (unreadCount == 0) return const SizedBox.shrink();

                      return Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.brandPink,
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
                    color: AppColors.brandBlue,
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
                                  backgroundColor: AppColors.brandBlue,
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
                                  : const AssetImage('assets/images/oneova_logo.jpg'),
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
                          : const AssetImage('assets/images/oneova_logo.jpg'),
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
        // ignore: unused_local_variable
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
    final systemStatus = ref.watch(systemStatusProvider);
    final workflowEngine = ref.watch(workflowEngineProvider);
    final authState = ref.watch(authStateProvider);
    final connectedChannelsCount = ref.watch(connectedChannelsCountProvider(authState.value?.uid ?? '')).value ?? 0;

    // ignore: unused_local_variable
    final isHealthy = systemStatus.globalStateDisplay == 'ONLINE';
    
    final realtimeComp = systemStatus.components[SystemComponent.realtime];
    final aiComp = systemStatus.components[SystemComponent.ai];
    final storageComp = systemStatus.components[SystemComponent.storage];
    final syncComp = systemStatus.components[SystemComponent.database];

    final activeTasksCount = workflowEngine.activeTasks.length;

    final stats = [
      _SystemStat('System Health', systemStatus.globalStateDisplay, systemStatus.globalDescription, Icons.monitor_heart_rounded, Color(systemStatus.globalColorHex)),
      _SystemStat('Realtime', realtimeComp?.statusDisplay ?? 'Unknown', 'WebSockets / RPC', Icons.desktop_mac_rounded, Color(realtimeComp?.colorHex ?? 0xFF9CA3AF)),
      _SystemStat('Connected Channels', '$connectedChannelsCount', 'Active platforms', Icons.link_rounded, connectedChannelsCount > 0 ? AppColors.brandPink : AppColors.brandBlue),
      _SystemStat('Active Tasks', '$activeTasksCount', 'Processing in background', Icons.task_alt_rounded, activeTasksCount > 0 ? AppColors.brandPink : AppColors.brandBlue),
      _SystemStat('AI Status', aiComp?.statusDisplay ?? 'Unknown', 'Agent copilot', Icons.auto_awesome_rounded, Color(aiComp?.colorHex ?? 0xFF9CA3AF)),
      _SystemStat('Storage', storageComp?.statusDisplay ?? 'Unknown', 'Cloud sync', Icons.cloud_done_rounded, Color(storageComp?.colorHex ?? 0xFF9CA3AF)),
      _SystemStat('Sync Status', syncComp?.statusDisplay ?? 'Unknown', 'Database replication', Icons.sync_rounded, Color(syncComp?.colorHex ?? 0xFF9CA3AF)),
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

  Widget _buildAccordionMenu(BuildContext context) {
    return Column(
      children: [
        ExpansionTile(
          title: const Text(
            'Production Tools',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          iconColor: AppColors.brandBlue,
          collapsedIconColor: AppColors.brandBlue,
          children: [
            ListTile(
              leading: Icon(Icons.mic_rounded, color: AppColors.brandBlue),
              title: const Text('Audio (Mix & Master)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => context.push('/audio/dashboard'),
            ),
            ListTile(
              leading: Icon(Icons.video_library, color: AppColors.brandBlue),
              title: const Text('Video (Edit & Render)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => context.push('/video/dashboard'),
            ),
          ],
        ),
        ExpansionTile(
          title: const Text(
            'Distribution & Social',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          iconColor: AppColors.brandBlue,
          collapsedIconColor: AppColors.brandBlue,
          children: [
            ListTile(
              leading: Icon(Icons.smart_display_rounded, color: AppColors.brandBlue),
              title: const Text('YouTube (Manage channel)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const InternalBrowserScreen(
                      url: 'https://studio.youtube.com',
                      title: 'YouTube Studio',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.hub_rounded, color: AppColors.brandBlue),
              title: const Text('Social (Cross-post)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const InternalBrowserScreen(
                      url: 'https://onerova.studio/social',
                      title: 'Social Hub',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        ExpansionTile(
          title: const Text(
            'Workspace',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          iconColor: AppColors.brandBlue,
          collapsedIconColor: AppColors.brandBlue,
          children: [
            ListTile(
              leading: Icon(Icons.qr_code_scanner_rounded, color: AppColors.brandBlue),
              title: const Text('Connect (Link Devices)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => context.push('/auth/linked_devices'),
            ),
            ListTile(
              leading: Icon(Icons.folder_rounded, color: AppColors.brandBlue),
              title: const Text('Projects (All assets)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => context.push('/video/projects'),
            ),
            ListTile(
              leading: Icon(Icons.chat_bubble_rounded, color: AppColors.brandBlue),
              title: const Text('Messages (Team chat)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => context.push('/hub/messages'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveUsersSection(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(liveWorkspaceMembersProvider);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(Icons.group_rounded, color: AppColors.brandBlue),
          title: const Text(
            'Live Hub Users',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
          trailing: membersAsync.when(
            data: (members) {
              final activeUsers = members.length;
              return Row(
                mainAxisSize: MainAxisSize.min,
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
                    '$activeUsers Online',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),
        membersAsync.when(
          data: (members) {
            if (members.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 48,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                scrollDirection: Axis.horizontal,
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final user = members[index];
                  final isOnline = user.isOnline;
                  final initials = user.roleId.isNotEmpty 
                    ? user.roleId[0].toUpperCase()
                    : '?';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Tooltip(
                      message: '${user.uid} (${user.roleId})',
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.primaries[index % Colors.primaries.length].withValues(alpha: 0.2),
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: Colors.primaries[index % Colors.primaries.length],
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
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
          loading: () => const Center(child: AnimatedLoadingIndicator()),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error loading users: $e', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ),
      ],
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
            color: AppColors.brandBlue.withValues(alpha: 0.3),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: 0.05),
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
                ?trailing,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(Icons.computer_rounded, color: AppColors.brandBlue),
          title: const Text(
            'Connected Computers',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
          trailing: IconButton(
            icon: Icon(
              Icons.add_circle,
              color: AppColors.brandBlue,
            ),
            onPressed: () => _showConnectWizard(context, ref),
          ),
        ),
        if (remoteState.linkedComputers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'No computers linked yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        if (remoteState.linkedComputers.isNotEmpty)
          SizedBox(
            height: 90,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              scrollDirection: Axis.horizontal,
              itemCount: remoteState.linkedComputers.length,
              itemBuilder: (context, index) {
                final computer = remoteState.linkedComputers[index];
                final connection = webrtcState.connections[computer.id];
                final isConnected = connection?.status == WebRTCStatus.connected;
                
                // Auto-connect if it's online but not connected
                if (computer.isOnline && connection == null) {
                  Future.microtask(() {
                    ref.read(webrtcDesktopProvider.notifier).connect(computer.id);
                  });
                }

                return GestureDetector(
                  onTap: () {
                    ref.read(remoteConnectProvider.notifier).setActiveComputer(computer.id);
                    context.push('/remote_control');
                  },
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12.0),
                    decoration: BoxDecoration(
                      color: Colors.transparent, // flat list aesthetic
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isConnected ? AppColors.brandBlue : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isConnected && connection?.renderer != null)
                            RTCVideoView(
                              connection!.renderer!,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          else
                            Container(
                              color: Colors.white.withValues(alpha: 0.05),
                              child: Icon(
                                Icons.computer,
                                size: 36,
                                color: computer.isOnline ? Colors.white : Colors.white38,
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              color: Colors.black87,
                              child: Text(
                                computer.name,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isConnected 
                                    ? Colors.greenAccent 
                                    : (computer.isOnline ? Colors.orange : Colors.red),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: AppColors.darkSurface,
                                      title: Text('Disconnect ${computer.name}?', style: const TextStyle(color: Colors.white)),
                                      content: const Text('This will unlink the device and terminate any active connections.', style: TextStyle(color: Colors.white70)),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            ref.read(webrtcDesktopProvider.notifier).disconnect(computer.id);
                                            ref.read(remoteConnectProvider.notifier).unlinkComputer(computer.id);
                                          },
                                          child: const Text('Disconnect', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.link_off, size: 14, color: Colors.white70),
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
            ),
          ),
      ],
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
          color: AppColors.brandBlue,
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
        loading: () => const Center(child: AnimatedLoadingIndicator()),
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
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
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
          border: Border.all(color: AppColors.brandBlue, width: 2),
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
      trailing: Icon(Icons.sort, color: AppColors.brandBlue, size: 20),
      child: _buildUpdatesFeedList(context, ref),
    );
  }

  Widget _buildUpdatesFeedList(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);

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
            if (notif.category == AppNotificationCategory.system) icon = Icons.admin_panel_settings;
            if (notif.category == AppNotificationCategory.system) icon = Icons.task_alt; // reusing for task
            if (notif.category == AppNotificationCategory.newMessage) icon = Icons.share; // reusing for social

            return _buildFeedItem(
              context,
              notif.category.name.toUpperCase(),
              notif.body,
              _formatTime(notif.createdAt),
              icon,
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
          },
        );
      },
      loading: () => const Center(child: AnimatedLoadingIndicator()),
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


  Future<void> _showQuickCreateMenu(BuildContext context) async {
    final teamService = ref.read(teamServiceProvider);
    final member = await teamService.getCurrentMemberProfile();
    if (!context.mounted) return;
    
    String roleName = member?.roleId ?? '';
    if (member != null) {
      final roleData = await teamService.getRole(member.workspaceId, member.roleId);
      if (roleData != null) {
        roleName = roleData.name;
      }
    }

    final role = roleName.toLowerCase();

    // Permission checks based on role mapping
    final isAdmin = role == 'admin' || role == 'owner' || role == 'founder';
    final isManager = isAdmin || role == 'manager' || role == 'creator';
    final isStaff = isManager || role == 'staff' || role == 'editor' || role.contains('editor') || role.contains('director');

    if (!context.mounted) return;
    showPopover(
      context: context,
      bodyBuilder: (context) {
        return Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.5),
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
                  _buildQuickCreateItem(context, Icons.message_rounded, 'New Message', 'Direct chat'),
                  _buildQuickCreateItem(context, Icons.group_add_rounded, 'New Group', 'Team channel'),
                  
                  if (isStaff)
                    _buildQuickCreateItem(context, Icons.task_alt_rounded, 'New Task', 'Assign work'),
                  
                  if (isManager)
                    _buildQuickCreateItem(context, Icons.post_add_rounded, 'New Post', 'Social media'),
                  
                  _buildQuickCreateItem(context, Icons.call_rounded, 'Start Call', 'Audio meeting'),
                  _buildQuickCreateItem(context, Icons.video_call_rounded, 'Start Video', 'Video meeting'),
                  
                  if (isStaff)
                    _buildQuickCreateItem(context, Icons.cloud_upload_rounded, 'Upload', 'Media files'),
                  
                  // Everyone has AI Session but features are gated inside
                  _buildQuickCreateItem(context, Icons.auto_awesome_rounded, 'AI Session', 'Copilot mode'),
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
        switch (title) {
          case 'New Message':
            context.push('/hub/messages');
            break;
          case 'New Group':
            context.push('/communication/contacts');
            break;
          case 'New Task':
            context.push('/crm/dashboard');
            break;
          case 'New Post':
            context.push('/social_hub/feed');
            break;
          case 'Start Call':
            context.push('/remote/voice');
            break;
          case 'Start Video':
            context.push('/remote/chat');
            break;
          case 'Upload':
            context.push('/upload/global');
            break;
          case 'AI Session':
            context.push('/settings/main'); // AI configs
            break;
          default:
            if (title == 'Connect App') {
              _showConnectWizard(context, ref);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting: $title...')));
            }
        }
      },
      child: Container(
        width: 135,
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
                color: AppColors.brandBlue,
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
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Connect a Studio Application',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pair your device with OneOva Studio Engine & Pro Creative Tools.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      
                      // Option 1: Cloud Sync (Recommended)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          alignment: Alignment.centerLeft,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: isCloudLoading 
                            ? const SizedBox(width: 24, height: 24, child: AnimatedLoadingIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 28),
                        label: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Link via ONEOVA Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                      const SizedBox(height: 8),
                      
                      // Option 2: Scan QR
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          alignment: Alignment.centerLeft,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
                        label: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white30)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('OR MANUAL CODE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                            Expanded(child: Divider(color: Colors.white30)),
                          ],
                        ),
                      ),
                      
                      const Text(
                        'One-Time Session Code',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        style: const TextStyle(color: Colors.white, letterSpacing: 2.0, fontWeight: FontWeight.bold),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'e.g. ONEOVA-9X42',
                          hintStyle: const TextStyle(color: Colors.white54, letterSpacing: 0, fontWeight: FontWeight.normal),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.password_rounded, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.brandBlue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
          color: AppColors.brandBlue.withValues(alpha: 0.3),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.05),
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

