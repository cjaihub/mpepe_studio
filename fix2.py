import re
import urllib.request
import json

# I'll just write a script to fix the syntax I introduced in `lib/feed/widgets/comment_bottom_sheet.dart`.
with open('lib/feed/widgets/comment_bottom_sheet.dart', 'r') as f:
    text = f.read()

# Fix creturn issue
text = text.replace("child: creturn ClipRRect(", "return ClipRRect(")
text = text.replace("child: creturn", "return")

with open('lib/feed/widgets/comment_bottom_sheet.dart', 'w') as f:
    f.write(text)
