path = 'lib/shared/router.dart'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
in_hub_shell = False
skip_to = False

for i, line in enumerate(lines):
    if skip_to and not line.strip() == "],":
        continue
    elif skip_to and line.strip() == "],":
        skip_to = False
        new_lines.append(line)
        continue

    if "builder: (context, state, navigationShell) => HubShell(navigationShell: navigationShell)," in line:
        in_hub_shell = True
        new_lines.append(line)
        continue
    
    if in_hub_shell and "branches: [" in line:
        new_lines.append(line)
        branches_code = """          StatefulShellBranch(routes: [GoRoute(
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
"""
        new_lines.append(branches_code)
        in_hub_shell = False
        skip_to = True
        continue
        
    new_lines.append(line)

with open(path, 'w') as f:
    f.writelines(new_lines)

# Also ensure main_feed_screen, search_screen, and public_profile are imported
with open(path, 'r') as f:
    content = f.read()
    if 'main_feed_screen.dart' not in content:
        content = 'import "package:mpepe_studio/feed/main_feed_screen.dart";\n' + content
    if 'global_search_screen.dart' not in content:
        content = 'import "package:mpepe_studio/shared/search/global_search_screen.dart";\n' + content
    if 'public_profile_screen.dart' not in content:
        content = 'import "package:mpepe_studio/social_hub/profile/public_profile_screen.dart";\n' + content
with open(path, 'w') as f:
    f.write(content)

