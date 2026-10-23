import os

path = 'lib/feed/main_feed_screen.dart'
with open(path, 'r') as f:
    content = f.read()

# Replace context.push with Navigator.push
content = content.replace(
    "context.push('/social/profile/${widget.content.authorId}');", 
    "Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUserId: widget.content.authorId)));"
)

# Make sure PublicProfileScreen is imported
if "import '../social_hub/profile/public_profile_screen.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../social_hub/profile/public_profile_screen.dart';")

with open(path, 'w') as f:
    f.write(content)

print("Fixed routing to profile")
