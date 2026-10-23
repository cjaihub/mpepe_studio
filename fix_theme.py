with open('lib/shared/theme/app_theme.dart', 'r') as f:
    text = f.read()

import re
# Keep only the first static const Color brandBlue
lines = text.split('\n')
new_lines = []
found = False
for line in lines:
    if 'static const Color brandBlue' in line:
        if not found:
            new_lines.append(line)
            found = True
        else:
            pass # skip duplicates
    else:
        new_lines.append(line)

with open('lib/shared/theme/app_theme.dart', 'w') as f:
    f.write('\n'.join(new_lines))
