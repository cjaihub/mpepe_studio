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
        
        # Regex to find Padding(\n      padding: const EdgeInsets.only(bottom: 16),\n      child: MpepeCard(\n        child: 
        # and replace it with MpepeCard( child:
        content = re.sub(r"Padding\(\s*padding:\s*const EdgeInsets\.only\(bottom: 16\),\s*child:\s*MpepeCard\(\s*child:", 
                         r"MpepeCard(\n      child:", content)
                         
        # Same for the RadioListTile indentation
        # Actually the first regex might catch it all, but let's do a more general one
        content = re.sub(r"Padding\(\s*padding:[^,]+,\s*child:\s*MpepeCard\(\s*child:", 
                         r"MpepeCard(\n      child:", content)
        
        with open(f, 'w') as file:
            file.write(content)

fix()
