with open('lib/feed/main_feed_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("class PostCard extends StatefulWidget", "import 'package:flutter_riverpod/flutter_riverpod.dart';\n\nclass PostCard extends ConsumerStatefulWidget")
content = content.replace("State<PostCard> createState() => _PostCardState();", "ConsumerState<PostCard> createState() => _PostCardState();")
content = content.replace("class _PostCardState extends State<PostCard>", "class _PostCardState extends ConsumerState<PostCard>")

with open('lib/feed/main_feed_screen.dart', 'w') as f:
    f.write(content)
