with open('lib/shared/router.dart', 'r') as f:
    content = f.read()

import re

# Remove the notification badge (Positioned with right: -4, top: -4 ... '3')
# and also the small dot (Positioned right: 0, top: 0 ... 8x8)
# We can just replace the whole icon: Stack( ... ) with icon: Icon(LucideIcons.messageSquare)
# But wait, there are multiple ones. Let's just do a regex.

# We will replace all occurrences of this Stack pattern with just the Icon
pattern_msg = r'''icon:\s*Stack\(\s*clipBehavior:\s*Clip\.none,\s*children:\s*\[\s*Icon\(LucideIcons\.messageSquare\),\s*Positioned\([\s\S]*?\]\s*\),'''
content = re.sub(pattern_msg, "icon: Icon(LucideIcons.messageSquare),", content)

pattern_user = r'''icon:\s*Stack\(\s*clipBehavior:\s*Clip\.none,\s*children:\s*\[\s*Icon\(LucideIcons\.user\),\s*Positioned\([\s\S]*?\]\s*\),'''
content = re.sub(pattern_user, "icon: Icon(LucideIcons.user),", content)

with open('lib/shared/router.dart', 'w') as f:
    f.write(content)
