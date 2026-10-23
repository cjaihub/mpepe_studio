import re
import os

path = 'lib/shared/router.dart'
with open(path, 'r') as f:
    content = f.read()

# Replace HubShell class
hub_shell_code = """class HubShell extends StatelessWidget {
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

content = re.sub(r'class HubShell extends StatelessWidget \{.*?\n\}\n', hub_shell_code + '\n', content, flags=re.DOTALL)

# Now fix the branches for HubShell to match: Home, Discover, Messages, Profile (4 branches, 1 is STUDIO modal)
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

# Find the HubShell StatefulShellRoute and replace its branches
content = re.sub(r'StatefulShellRoute\.indexedStack\(\s*builder: \(context, state, navigationShell\) => HubShell\(navigationShell: navigationShell\),\s*branches: \[.*?(?=\n      \),)', branches_code, content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(content)

print("Re-structured HubShell branches and TikTok navbar")
