with open('lib/shared/router.dart', 'r') as f:
    content = f.read()

# Add import
if "import '../create/gif_creator_screen.dart';" not in content:
    content = "import '../create/gif_creator_screen.dart';\n" + content

# Add route
route_to_add = """      GoRoute(
        path: '/create/gif',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return GifCreatorScreen(
            onGifCreated: extra?['onGifCreated'] as void Function(String)?,
          );
        },
      ),"""

if "'/create/gif'" not in content:
    idx = content.find("GoRoute(")
    if idx != -1:
        content = content[:idx] + route_to_add + "\n" + content[idx:]

with open('lib/shared/router.dart', 'w') as f:
    f.write(content)
