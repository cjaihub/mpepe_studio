with open('lib/feed/main_feed_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("import 'package:flutter_riverpod/flutter_riverpod.dart';\n\nclass PostCard extends ConsumerStatefulWidget", "class PostCard extends ConsumerStatefulWidget")
content = "import 'package:flutter_riverpod/flutter_riverpod.dart';\n" + content

with open('lib/feed/main_feed_screen.dart', 'w') as f:
    f.write(content)
