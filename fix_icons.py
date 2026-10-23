import os
import glob

def fix_icons():
    # fix the const Icon in the shells
    shells_dir = "lib/settings/screens"
    for f in glob.glob(f"{shells_dir}/*.dart"):
        with open(f, 'r') as file:
            content = file.read()
        
        new_content = content.replace(
            "const Icon(LucideIcons.settings",
            "Icon(LucideIcons.settings"
        )
        
        with open(f, 'w') as file:
            file.write(new_content)

    # fix camelCase to snake_case in main_settings_screen
    main_file = "lib/settings/main_settings_screen.dart"
    with open(main_file, 'r') as file:
        content = file.read()
        
    replacements = {
        "LucideIcons.cpu": "LucideIcons.cpu",
        "LucideIcons.zap": "LucideIcons.zap",
        "LucideIcons.database": "LucideIcons.database",
        "LucideIcons.download": "LucideIcons.download",
        "LucideIcons.helpCircle": "LucideIcons.helpCircle",
        "LucideIcons.info": "LucideIcons.info"
    }
    # Wait, the error is getter isn't defined. Let's look at the pub cache for lucide_icons or just use material icons for these 6.
    
    # Material fallbacks
    replacements = {
        "LucideIcons.cpu": "Icons.memory",
        "LucideIcons.zap": "Icons.bolt",
        "LucideIcons.database": "Icons.storage",
        "LucideIcons.download": "Icons.download",
        "LucideIcons.helpCircle": "Icons.help_outline",
        "LucideIcons.info": "Icons.info_outline"
    }

    for k, v in replacements.items():
        content = content.replace(k, v)
        
    with open(main_file, 'w') as file:
        file.write(content)

fix_icons()
