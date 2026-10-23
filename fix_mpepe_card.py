import os
import glob

def fix():
    targets = glob.glob("lib/settings/screens/*.dart")
    targets.append("lib/settings/ai_voice_personalization_screen.dart")
    targets.append("lib/ai_messaging/screens/auto_mode_settings_screen.dart")
    
    for f in targets:
        if not os.path.exists(f):
            continue
        with open(f, 'r') as file:
            content = file.read()
        
        # We need to replace:
        # MpepeCard(
        #   margin: const EdgeInsets.only(bottom: 16),
        #   child: SwitchListTile(
        # with:
        # Padding(
        #   padding: const EdgeInsets.only(bottom: 16),
        #   child: MpepeCard(
        #     child: SwitchListTile(
        
        content = content.replace("MpepeCard(\n      margin: const EdgeInsets.only(bottom: 16),", "Padding(\n      padding: const EdgeInsets.only(bottom: 16),\n      child: MpepeCard(")
        
        # Also fix RadioListTile
        content = content.replace("MpepeCard(\n                margin: const EdgeInsets.only(bottom: 16),", "Padding(\n                padding: const EdgeInsets.only(bottom: 16),\n                child: MpepeCard(")
        
        with open(f, 'w') as file:
            file.write(content)

fix()
