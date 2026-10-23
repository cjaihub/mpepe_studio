import re

path = 'lib/shared/router.dart'
with open(path, 'r') as f:
    content = f.read()

# Replace imports
if 'main_feed_screen.dart' not in content:
    content = 'import "package:mpepe_studio/feed/main_feed_screen.dart";\n' + content
if 'global_search_screen.dart' not in content:
    content = 'import "package:mpepe_studio/shared/search/global_search_screen.dart";\n' + content
if 'public_profile_screen.dart' not in content:
    content = 'import "package:mpepe_studio/social_hub/profile/public_profile_screen.dart";\n' + content

# Fix syntax errors from dead screens
content = re.sub(r'import.*privacy_security_screen.dart.*\n', '', content)
content = re.sub(r'import.*unified_inbox_screen.dart.*\n', '', content)
content = re.sub(r'import.*desktop_remote_screen.dart.*\n', '', content)
content = content.replace('AppTheme.h1Style', 'Theme.of(context).textTheme.displayLarge')
content = re.sub(r'GoRoute\([^)]*PrivacySecurityScreen\(\)[^)]*\),?', '', content, flags=re.DOTALL)
content = re.sub(r'GoRoute\([^)]*UnifiedInboxScreen\(\)[^)]*\),?', '', content, flags=re.DOTALL)
content = re.sub(r'GoRoute\([^)]*DesktopRemoteScreen\([^)]*\)[^)]*\),?', '', content, flags=re.DOTALL)

# Modify HubShell class and its items
hub_shell_items_old = """  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_rounded), label: 'Upload'),
    BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Messages'),
    BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'AI'),
    BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Team'),
  ];"""

hub_shell_items_new = """  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Discover'),
    BottomNavigationBarItem(icon: Icon(Icons.add_box_rounded), label: 'STUDIO'),
    BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Messages'),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
  ];"""

content = content.replace(hub_shell_items_old, hub_shell_items_new)

# Modify the SharedBottomNavBar call inside HubShell
old_navbar = """          : SharedBottomNavBar(
              navigationShell: navigationShell,
              items: _items,
            ),"""
new_navbar = """          : SharedBottomNavBar(
              navigationShell: navigationShell,
              items: _items,
              isTikTokStyle: true,
              isTransparent: navigationShell.currentIndex == 0,
            ),"""
content = content.replace(old_navbar, new_navbar)

# Modify the branches explicitly one by one
content = content.replace('const HubHomeScreen()', 'const ShortVideoFeedScreen()')
content = content.replace("path: '/upload/global'", "path: '/hub/discover'")
content = content.replace('const PremiumPostScreen()', 'const GlobalSearchScreen()')

# Change HubAiScreen to PublicProfileScreen
content = content.replace("path: '/hub/ai'", "path: '/hub/profile'")
content = content.replace('const HubAiScreen()', "const PublicProfileScreen(userId: 'current')")

# The last branch '/hub/team' is still there, but it will never be routed to by the Nav Bar.
# We can just leave it there so we don't break brackets!

with open(path, 'w') as f:
    f.write(content)
