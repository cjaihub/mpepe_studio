import re

with open('lib/feed/main_feed_screen.dart', 'r') as f:
    text = f.read()

# I will replace all `'Reposted',` that are on their own lines back to `// 0`
text = re.sub(r"^\s*'Reposted',\s*$", "// 0", text, flags=re.MULTILINE)

# And specifically fix the Text( style: ... )
text = text.replace("Text(\n// 0", "Text(\n'Reposted',")

with open('lib/feed/main_feed_screen.dart', 'w') as f:
    f.write(text)
