with open('lib/social_hub/feed/short_video_feed_screen.dart', 'r') as f:
    content = f.read()

import re

seed_code = """
      if (_feed.isEmpty) {
        // Seed database if empty
        final firestore = FirebaseFirestore.instance;
        final mockPosts = [
          {
            'id': 'post_1',
            'authorId': 'user_a',
            'content': 'Exploring the new studio features! #mpepe #studio',
            'attachments': ['https://picsum.photos/800/1200?random=1'],
            'type': 'short_video',
            'createdAt': FieldValue.serverTimestamp(),
            'viewCount': 100,
            'algorithmicScore': 9.5
          },
          {
            'id': 'post_2',
            'authorId': 'user_b',
            'content': 'Deep work mode activated. 🚀',
            'attachments': ['https://picsum.photos/800/1200?random=2'],
            'type': 'short_video',
            'createdAt': FieldValue.serverTimestamp(),
            'viewCount': 200,
            'algorithmicScore': 8.5
          },
          {
            'id': 'post_3',
            'authorId': 'user_c',
            'content': 'Just dropped a new tutorial on advanced analytics.',
            'attachments': ['https://picsum.photos/800/1200?random=3'],
            'type': 'short_video',
            'createdAt': FieldValue.serverTimestamp(),
            'viewCount': 300,
            'algorithmicScore': 7.5
          }
        ];
        for (var p in mockPosts) {
          firestore.collection('content').doc(p['id'] as String).set(p);
        }
        // retry load
        Future.delayed(const Duration(seconds: 2), _loadFeed);
      } else {
        ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, 0);
      }
"""

content = content.replace("if (_feed.isNotEmpty) {\n        ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, 0);\n      }", seed_code)

if "import 'package:cloud_firestore/cloud_firestore.dart';" not in content:
    content = "import 'package:cloud_firestore/cloud_firestore.dart';\n" + content

with open('lib/social_hub/feed/short_video_feed_screen.dart', 'w') as f:
    f.write(content)
