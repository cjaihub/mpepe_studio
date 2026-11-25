import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../backend/user_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/shared_bottom_nav_bar.dart';
import 'package:go_router/go_router.dart';
import '../hub/hub_home_screen.dart';

import '../hub/hub_team_screen.dart';
import '../hub/messaging/chat_detail_screen.dart';
import '../hub/calendar/studio_calendar_screen.dart';
import '../hub/hub_ai_screen.dart';
import '../youtube_manager/yt_dashboard_screen.dart';
import '../youtube_manager/yt_channels_screen.dart';
import '../youtube_manager/yt_upload_screen.dart';

import '../youtube_manager/yt_settings_screen.dart';
import '../hub/unified_hub_screen.dart';
import '../hub/messaging/in_app_messaging_screen.dart';
import '../auth/main_login_screen.dart';
import '../auth/screens/workspace_locked_screen.dart';
import '../desktop_agent/desktop_agent_screen.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../auth/signup_wizard_screen.dart';
import '../auth/pending_approval_screen.dart';
import '../auth/linked_devices/linked_devices_screen.dart';
import '../settings/main_settings_screen.dart';
import '../settings/screens/profile_settings_screen.dart';
import '../settings/screens/app_settings_screen.dart';
import '../settings/screens/notification_settings_screen.dart';
import '../settings/screens/ai_settings_screen.dart';
import '../settings/screens/privacy_security_screen.dart';
import '../social_hub/social_integration_dashboard.dart';
import '../social_hub/tiktok_connect_wizard.dart';
import '../social_hub/meta_connect_wizard.dart';
import '../social_hub/meta_platform_picker_screen.dart';
import '../social_hub/wizard/meta_app_wizard.dart';
import '../upload/screens/premium_post_screen.dart';
import '../upload/ai_voice_manager_screen.dart';
import '../social_hub/unified_inbox_screen.dart';
import '../social_hub/analytics_command_center.dart';
import '../social_hub/tiktok_ai_assistant_screen.dart';
import '../social_hub/feed/short_video_feed_screen.dart';
import '../social_hub/feed/post_reel_screen.dart';
import '../social_hub/feed/feed_controls_screen.dart';
import '../projects/unified_projects_screen.dart';
import '../video_production/video_dashboard_screen.dart';
import '../video_production/video_equipment_screen.dart';
import '../video_production/video_team_screen.dart';
import '../audio_production/audio_dashboard_screen.dart';
import '../audio_production/audio_library_screen.dart';
import '../audio_production/audio_artists_screen.dart';
import '../hub/connect_screen.dart';
import '../hub/qr_scanner_screen.dart';
import '../hub/remote_chat_screen.dart';
import '../hub/remote_monitor_screen.dart';
import '../hub/desktop_remote_screen.dart';

// StatefulShellRoute shells
class HubShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const HubShell({super.key, required this.navigationShell});

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_rounded), label: 'Upload'),
    BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Messages'),
    BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'AI'),
    BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Team'),
  ];

  @override
  Widget build(BuildContext context) {
    final isAiScreen = navigationShell.currentIndex == 3;
    
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: isAiScreen 
          ? null 
          : SharedBottomNavBar(
              navigationShell: navigationShell,
              items: _items,
            ),
    );
  }
}

class YtShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const YtShell({super.key, required this.navigationShell});

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Dashboard'),
    BottomNavigationBarItem(icon: Icon(Icons.subscriptions_outlined), label: 'Channels'),
    BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_outlined), label: 'Upload'),
    BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SharedBottomNavBar(
        navigationShell: navigationShell,
        items: _items,
      ),
    );
  }
}

class VideoShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const VideoShell({super.key, required this.navigationShell});

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.videocam_outlined), label: 'Dashboard'),
    BottomNavigationBarItem(icon: Icon(Icons.movie_creation_outlined), label: 'Projects'),
    BottomNavigationBarItem(icon: Icon(Icons.build_outlined), label: 'Equipment'),
    BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Crew'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SharedBottomNavBar(
        navigationShell: navigationShell,
        items: _items,
      ),
    );
  }
}

class AudioShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AudioShell({super.key, required this.navigationShell});

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.music_note_rounded), label: 'Dashboard'),
    BottomNavigationBarItem(icon: Icon(Icons.equalizer_rounded), label: 'Productions'),
    BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: 'Library'),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Artists'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SharedBottomNavBar(
        navigationShell: navigationShell,
        items: _items,
      ),
    );
  }
}

class SessionRouteObserver extends NavigatorObserver {
  final Ref ref;
  SessionRouteObserver(this.ref);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateSession(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _updateSession(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _updateSession(previousRoute);
  }

  void _updateSession(Route<dynamic> route) {
    if (route.settings.name != null && !route.settings.name!.startsWith('/auth')) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Debounce or just fire and forget
        ref.read(userProvider.notifier).updateLastActiveRoute(user.uid, route.settings.name!);
      }
    }
  }
}

// Auth guard helper: redirects to login if not authenticated
String? _requireAuth(BuildContext context, GoRouterState state) {
  if (kDebugMode && (Platform.isMacOS || Platform.isWindows)) {
    return null; // Bypass for Desktop debugging
  }
  if (FirebaseAuth.instance.currentUser == null) {
    return '/auth/main_login';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final isDesktopDebug = kDebugMode && (Platform.isMacOS || Platform.isWindows);
  return GoRouter(
    initialLocation: isDesktopDebug ? '/desktop_agent' : '/auth/main_login',
    observers: [SessionRouteObserver(ref)],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.mpepeMaroon),
            const SizedBox(height: 24),
            Text('Page Not Found', style: AppTheme.h1Style),
            const SizedBox(height: 16),
            Text(
              'The screen you are looking for does not exist.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () => context.go('/auth/main_login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mpepeMaroon,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Go Home', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isAuthRoute = state.uri.path.startsWith('/auth');
      
      final isDesktopDebug = kDebugMode && (Platform.isMacOS || Platform.isWindows);

      if (user == null && !isAuthRoute && !isDesktopDebug) {
        return '/auth/main_login';
      }
      
      if (isDesktopDebug && state.uri.path == '/auth/main_login') {
        return '/desktop_agent';
      }

      // If user is logged in on macOS/Windows, force them to the Desktop Agent screen
      // instead of the mobile Hub home, since the desktop app acts as the agent.
      if (user != null && !kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
        if (state.uri.path == '/' || state.uri.path == '/hub/home') {
          return '/desktop_agent';
        }
      }

      return null;
    },
    routes: [
      // ──────────────────────────────────────────────────────────────────
      // ROOT & AUTH ROUTES (no guard — anyone can access these)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        redirect: (context, state) => '/auth/main_login',
      ),
      GoRoute(
        path: '/auth/locked',
        builder: (context, state) => const WorkspaceLockedScreen(),
      ),
      GoRoute(
        path: '/auth/main_login',
        name: '/auth/main_login',
        builder: (context, state) => const MainLoginScreen(),
      ),
      GoRoute(
        path: '/auth/signup_wizard',
        builder: (context, state) => const SignupWizardScreen(),
      ),
      GoRoute(
        path: '/auth/pending',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/qr_scanner',
        builder: (context, state) => const QRScannerScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // LEGACY: /auth/youtube was the YouTube OAuth connector — NOT app auth.
      // Redirect existing links to the social hub (connected accounts).
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth/youtube',
        redirect: (context, state) {
          if (FirebaseAuth.instance.currentUser == null) return '/auth/main_login';
          return '/social_hub';
        },
      ),

      // ──────────────────────────────────────────────────────────────────
      // SOCIAL HUB — Platform Connection Routes (GUARDED)
      // These are for connecting YouTube/Instagram/TikTok to the user profile
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/social_hub',
        redirect: _requireAuth,
        builder: (context, state) => const SocialIntegrationDashboard(),
      ),
      // Reels: our own short-video feed (not tied to connected platforms).
      GoRoute(
        path: '/social_hub/reels',
        redirect: _requireAuth,
        builder: (context, state) => const ShortVideoFeedScreen(),
      ),
      GoRoute(
        path: '/social_hub/reels/post',
        redirect: _requireAuth,
        builder: (context, state) => const PostReelScreen(),
      ),
      GoRoute(
        path: '/social_hub/reels/controls',
        redirect: _requireAuth,
        builder: (context, state) => const FeedControlsScreen(),
      ),
      GoRoute(
        path: '/social_hub/connect_wizard',
        redirect: _requireAuth,
        builder: (context, state) => MetaConnectWizard(platform: state.extra as String? ?? 'Platform'),
      ),
      GoRoute(
        path: '/social_hub/meta_picker',
        redirect: _requireAuth,
        builder: (context, state) => const MetaPlatformPickerScreen(),
      ),
      GoRoute(
        path: '/social_hub/meta_wizard/:app',
        redirect: _requireAuth,
        builder: (context, state) {
          final app = state.pathParameters['app'] ?? 'instagram';
          return MetaAppWizard(appName: app);
        },
      ),
      GoRoute(
        path: '/social_hub/tiktok_wizard',
        redirect: _requireAuth,
        builder: (context, state) => const TikTokConnectWizard(),
      ),
      GoRoute(
        path: '/social_hub/unified_inbox',
        redirect: _requireAuth,
        builder: (context, state) => const UnifiedInboxScreen(),
      ),
      GoRoute(
        path: '/social_hub/analytics',
        redirect: _requireAuth,
        builder: (context, state) => const AnalyticsCommandCenter(),
      ),
      GoRoute(
        path: '/social_hub/tiktok_assistant',
        redirect: _requireAuth,
        builder: (context, state) => const TikTokAiAssistantScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // UPLOAD ROUTES (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/upload/ai_voice_manager',
        redirect: _requireAuth,
        builder: (context, state) => const AiVoiceManagerScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // CONNECT & REMOTE (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/connect',
        redirect: _requireAuth,
        builder: (context, state) => const ConnectScreen(),
      ),
      GoRoute(
        path: '/remote_chat',
        redirect: _requireAuth,
        builder: (context, state) => const RemoteChatScreen(),
      ),
      GoRoute(
        path: '/remote_monitor',
        redirect: _requireAuth,
        builder: (context, state) => const RemoteMonitorScreen(),
      ),
      GoRoute(
        path: '/remote_control',
        redirect: _requireAuth,
        builder: (context, state) => const DesktopRemoteScreen(),
      ),
      GoRoute(
        path: '/desktop_agent',
        redirect: _requireAuth,
        builder: (context, state) => const DesktopAgentScreen(),
      ),
      GoRoute(
        path: '/auth/linked_devices',
        redirect: _requireAuth,
        builder: (context, state) => const LinkedDevicesScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // SETTINGS (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/settings/main',
        redirect: _requireAuth,
        builder: (context, state) => const MainSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/profile',
        redirect: _requireAuth,
        builder: (context, state) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/app',
        redirect: _requireAuth,
        builder: (context, state) => const AppSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/notifications',
        redirect: _requireAuth,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/ai',
        redirect: _requireAuth,
        builder: (context, state) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        redirect: _requireAuth,
        builder: (context, state) => const PrivacySecurityScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // HUB (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HubShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(
            path: '/hub/home', 
            redirect: _requireAuth,
            builder: (context, state) => const HubHomeScreen()
          )]),
          StatefulShellBranch(routes: [GoRoute(
            path: '/upload/global', 
            redirect: _requireAuth,
            builder: (context, state) => const PremiumPostScreen()
          )]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/hub/messages', 
              redirect: _requireAuth,
              builder: (context, state) => const InAppMessagingScreen(),
              routes: [
                GoRoute(path: ':id', builder: (context, state) => ChatDetailScreen(chatId: state.pathParameters['id']!)),
              ],
            )
          ]),
          StatefulShellBranch(routes: [GoRoute(
            path: '/hub/ai', 
            redirect: _requireAuth,
            builder: (context, state) => const HubAiScreen()
          )]),
          StatefulShellBranch(routes: [GoRoute(
            path: '/hub/team', 
            redirect: _requireAuth,
            builder: (context, state) => const HubTeamScreen()
          )]),
        ],
      ),

      // ──────────────────────────────────────────────────────────────────
      // YOUTUBE MANAGER (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => YtShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/yt/dashboard', redirect: _requireAuth, builder: (context, state) => const YtDashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/channels', redirect: _requireAuth, builder: (context, state) => const YtChannelsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/upload', redirect: _requireAuth, builder: (context, state) => const YtUploadScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/settings', redirect: _requireAuth, builder: (context, state) => const YtSettingsScreen())]),
        ],
      ),

      // ──────────────────────────────────────────────────────────────────
      // VIDEO PRODUCTION (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => VideoShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/video/dashboard', redirect: _requireAuth, builder: (context, state) => const VideoDashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/video/projects', redirect: _requireAuth, builder: (context, state) => const UnifiedProjectsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/video/equipment', redirect: _requireAuth, builder: (context, state) => const VideoEquipmentScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/video/team', redirect: _requireAuth, builder: (context, state) => const VideoTeamScreen())]),
        ],
      ),

      // ──────────────────────────────────────────────────────────────────
      // AUDIO PRODUCTION (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AudioShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/audio/dashboard', redirect: _requireAuth, builder: (context, state) => const AudioDashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/audio/productions', redirect: _requireAuth, builder: (context, state) => const UnifiedProjectsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/audio/library', redirect: _requireAuth, builder: (context, state) => const AudioLibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/audio/artists', redirect: _requireAuth, builder: (context, state) => const AudioArtistsScreen())]),
        ],
      ),
    ],
  );
});
