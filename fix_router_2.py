import re

path = 'lib/shared/router.dart'
with open(path, 'r') as f:
    content = f.read()

# 1. Remove dead imports and routes
content = re.sub(r'import.*privacy_security_screen.dart.*\n', '', content)
content = re.sub(r'import.*unified_inbox_screen.dart.*\n', '', content)
content = re.sub(r'import.*desktop_remote_screen.dart.*\n', '', content)
content = re.sub(r'import.*hub_home_screen.dart.*\n', 'import "package:mpepe_studio/feed/main_feed_screen.dart";\n', content)
content = content.replace('AppTheme.h1Style', 'Theme.of(context).textTheme.displayLarge')
content = re.sub(r'GoRoute\([^)]*PrivacySecurityScreen\(\)[^)]*\),?', '', content, flags=re.DOTALL)
content = re.sub(r'GoRoute\([^)]*UnifiedInboxScreen\(\)[^)]*\),?', '', content, flags=re.DOTALL)
content = re.sub(r'GoRoute\([^)]*DesktopRemoteScreen\([^)]*\)[^)]*\),?', '', content, flags=re.DOTALL)

# 2. Modify HubShell to use TikTok items
hub_shell_items = """class HubShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const HubShell({super.key, required this.navigationShell});

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Discover'),
    BottomNavigationBarItem(icon: Icon(Icons.add_box_rounded), label: 'STUDIO'),
    BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Messages'),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SharedBottomNavBar(
        navigationShell: navigationShell,
        items: _items,
        isTikTokStyle: true,
        isTransparent: navigationShell.currentIndex == 0,
      ),
    );
  }
}"""

content = re.sub(r'class HubShell extends StatelessWidget \{.*?Widget build\(BuildContext context\) \{.*?\}\n\}', hub_shell_items, content, flags=re.DOTALL)

# 3. Replace the branches in HubShell
branches_code = """        branches: [
          StatefulShellBranch(routes: [GoRoute(
            path: '/hub/home', 
            redirect: _requireAuth,
            builder: (context, state) => const ShortVideoFeedScreen()
          )]),
          StatefulShellBranch(routes: [GoRoute(
            path: '/hub/discover', 
            redirect: _requireAuth,
            builder: (context, state) => const GlobalSearchScreen()
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
            path: '/hub/profile', 
            redirect: _requireAuth,
            builder: (context, state) => const PublicProfileScreen(userId: 'current')
          )]),
        ],"""

# Find the specific HubShell section and replace its branches
content = re.sub(r'        branches: \[\n          StatefulShellBranch\(routes: \[GoRoute\(\n            path: \'/hub/home\'.*?\n          \}\]\),\n        \],', branches_code, content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(content)

