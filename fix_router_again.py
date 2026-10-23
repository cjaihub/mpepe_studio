import re

with open('lib/shared/router.dart', 'r') as f:
    content = f.read()

# Fix imports
content = content.replace("import '../settings/screens/privacy_security_screen.dart';", "import '../settings/screens/privacy_settings_screen.dart';")
content = content.replace("import '../social_hub/unified_inbox_screen.dart';", "// import '../social_hub/unified_inbox_screen.dart';")

# Fix missing PrivacySecurityScreen
content = content.replace("return const PrivacySecurityScreen();", "return const PrivacySettingsScreen();")

# Fix missing UnifiedInboxScreen
content = content.replace("return const UnifiedInboxScreen();", "return const Scaffold(body: Center(child: Text('Inbox')));")

# Remove notification bubbles safely
# We match the specific stack for messageSquare
pattern1 = r'''icon:\s*Stack\(\s*clipBehavior:\s*Clip\.none,\s*children:\s*\[\s*Icon\(LucideIcons\.messageSquare\),\s*Positioned\([\s\S]*?right:\s*-4,[\s\S]*?\]\s*\),'''
content = re.sub(pattern1, "icon: Icon(LucideIcons.messageSquare),", content)

pattern2 = r'''icon:\s*Stack\(\s*clipBehavior:\s*Clip\.none,\s*children:\s*\[\s*Icon\(LucideIcons\.user\),\s*Positioned\([\s\S]*?right:\s*0,[\s\S]*?\]\s*\),'''
content = re.sub(pattern2, "icon: Icon(LucideIcons.user),", content)


with open('lib/shared/router.dart', 'w') as f:
    f.write(content)
