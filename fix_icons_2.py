import os
import glob

def fix_icons():
    # fix the Icon in the shells
    shells_dir = "lib/settings/screens"
    for f in glob.glob(f"{shells_dir}/*.dart"):
        with open(f, 'r') as file:
            content = file.read()
        
        new_content = content.replace(
            "Icon(LucideIcons.settings",
            "Icon(Icons.settings"
        )
        
        with open(f, 'w') as file:
            file.write(new_content)

fix_icons()
