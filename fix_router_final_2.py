import re

path = 'lib/shared/router.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix the profile parameter
content = content.replace("PublicProfileScreen(userId: 'current')", "PublicProfileScreen(targetUserId: 'current')")

# Manually delete the GoRoute blocks for the deleted screens by string replacement or carefully crafted regex
content = re.sub(r'\s*GoRoute\(\s*path: \'/settings/privacy\',.*?builder: \(context, state\) => const PrivacySecurityScreen\(\),\s*\),?', '', content, flags=re.DOTALL)

content = re.sub(r'\s*GoRoute\(\s*path: \'/hub/inbox\',.*?builder: \(context, state\) => const UnifiedInboxScreen\(\),\s*\),?', '', content, flags=re.DOTALL)

content = re.sub(r'\s*GoRoute\(\s*path: \'/remote_control\',.*?builder: \(context, state\) => const DesktopRemoteScreen\([^)]*\),\s*\),?', '', content, flags=re.DOTALL)
# It might not have (navigationShell: navigationShell), let's just wipe it based on 'DesktopRemoteScreen'
content = re.sub(r'\s*GoRoute\(\s*path: \'/remote_control\',.*?builder: \(context, state\) => const DesktopRemoteScreen\(\),\s*\),?', '', content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(content)
