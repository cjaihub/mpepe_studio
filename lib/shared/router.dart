import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../hub/hub_home_screen.dart';
import '../hub/hub_activity_screen.dart';
import '../hub/hub_ai_screen.dart';
import '../hub/hub_team_screen.dart';
import '../hub/coming_soon_screen.dart';
import '../youtube_manager/yt_dashboard_screen.dart';
import '../youtube_manager/yt_channels_screen.dart';
import '../youtube_manager/yt_upload_screen.dart';
import '../youtube_manager/yt_ai_screen.dart';
import '../youtube_manager/yt_settings_screen.dart';
import '../auth/main_login_screen.dart';
import '../auth/social_login_screen.dart';
import '../social_hub/social_hub_screen.dart';
import '../video_production/video_dashboard_screen.dart';
import '../video_production/video_projects_screen.dart';
import '../video_production/video_equipment_screen.dart';
import '../video_production/video_team_screen.dart';
import '../audio_production/audio_dashboard_screen.dart';
import '../audio_production/audio_productions_screen.dart';
import '../audio_production/audio_library_screen.dart';
import '../audio_production/audio_artists_screen.dart';

// StatefulShellRoute shells
class HubShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const HubShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        selectedItemColor: Colors.orange, // Hub active color
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'AI'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Team'),
        ],
      ),
    );
  }
}

class YtShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const YtShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        selectedItemColor: Colors.red, // YouTube active color
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Channels'),
          BottomNavigationBarItem(icon: Icon(Icons.upload), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'AI'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class VideoShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const VideoShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        selectedItemColor: const Color(0xFF8E2DE2), // Violet active color
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.movie), label: 'Projects'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Equipment'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Crew'),
        ],
      ),
    );
  }
}

class AudioShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AudioShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        selectedItemColor: const Color(0xFF11998E), // Teal active color
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.graphic_eq), label: 'Productions'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Artists'),
        ],
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/auth/main_login',
    routes: [
      GoRoute(
        path: '/auth/main_login',
        builder: (context, state) => const MainLoginScreen(),
      ),
      GoRoute(
        path: '/auth/youtube',
        builder: (context, state) => const SocialLoginScreen(),
      ),
      GoRoute(
        path: '/social_hub',
        builder: (context, state) => const SocialHubScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HubShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/hub/home', builder: (context, state) => const HubHomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/hub/activity', builder: (context, state) => const HubActivityScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/hub/ai', builder: (context, state) => const HubAiScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/hub/team', builder: (context, state) => const HubTeamScreen())]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => YtShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/yt/dashboard', builder: (context, state) => const YtDashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/channels', builder: (context, state) => const YtChannelsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/upload', builder: (context, state) => const YtUploadScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/ai', builder: (context, state) => const YtAiScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/yt/settings', builder: (context, state) => const YtSettingsScreen())]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => VideoShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/video/dashboard', builder: (context, state) => const VideoDashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/video/projects', builder: (context, state) => const VideoProjectsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/video/equipment', builder: (context, state) => const VideoEquipmentScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/video/team', builder: (context, state) => const VideoTeamScreen())]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AudioShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/audio/dashboard', builder: (context, state) => const AudioDashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/audio/productions', builder: (context, state) => const AudioProductionsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/audio/library', builder: (context, state) => const AudioLibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/audio/artists', builder: (context, state) => const AudioArtistsScreen())]),
        ],
      ),
    ],
  );
});
