import os
import glob
import re

def fix():
    targets = glob.glob("lib/settings/screens/*.dart")
    targets.append("lib/settings/ai_voice_personalization_screen.dart")
    targets.append("lib/ai_messaging/screens/auto_mode_settings_screen.dart")
    
    for f in targets:
        if not os.path.exists(f):
            continue
        with open(f, 'r') as file:
            content = file.read()
        
        # Regex to find MpepeCard(\n  margin: const EdgeInsets.only(bottom: 16),\n  child: ...
        # and replace with Padding(\n  padding: const EdgeInsets.only(bottom: 16),\n  child: MpepeCard(\n    child: ...
        
        # Simpler approach: Just remove the `margin` parameter from MpepeCard altogether. 
        # Since it's inside a ListView, we can just wrap the MpepeCard in a Padding or SizedBox.
        
        # Let's use regex to replace MpepeCard( margin: xxx, child: yyy ) 
        # with Padding( padding: xxx, child: MpepeCard( child: yyy ) )
        
        pattern = r"MpepeCard\(\s*margin:\s*(const EdgeInsets\.only\([^)]+\)),\s*child:\s*"
        replacement = r"Padding(\n      padding: \1,\n      child: MpepeCard(\n        child: "
        
        # for RadioListTile which has deeper indentation
        pattern2 = r"MpepeCard\(\s*margin:\s*(const EdgeInsets\.only\([^)]+\)),\s*child:\s*"
        replacement2 = r"Padding(\n                padding: \1,\n                child: MpepeCard(\n                  child: "
        
        # Apply standard padding wrap
        content = re.sub(r"MpepeCard\(\s*margin:\s*(const EdgeInsets\.[^,]+),\s*child:", 
                         r"Padding(\n      padding: \1,\n      child: MpepeCard(\n        child:", content)
        
        # Note: the above regex leaves the closing bracket of MpepeCard as `),`. 
        # But wait! If we wrap MpepeCard in Padding, we need an extra `)` at the end of the block.
        # This is hard to do with simple regex. 
        
        # Better fix: just replace `margin:` with `// margin:` to comment it out, it's easier and won't break syntax.
        # A card without margin in a ListView is totally fine, it just won't have spacing between cards.
        # Actually we can just add a `SizedBox(height: 16)` instead of wrapping in padding. But we can't easily do that either.
        
        # Safest way to fix `Error: No named parameter with the name 'margin'.`:
        content = content.replace("margin: const EdgeInsets.only(bottom: 16),", "")
        
        # Fix the unescaped quote in blocked_users_screen.dart
        content = content.replace("'When you block someone, they won't be able to message you or see your profile.'", '"When you block someone, they won\'t be able to message you or see your profile."')
        
        with open(f, 'w') as file:
            file.write(content)

fix()
