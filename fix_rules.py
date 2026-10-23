import os
import re

path = 'firestore.rules'
with open(path, 'r') as f:
    content = f.read()

new_rules = """
    // ─── Stories ─────────────────────────────────────────────────────────────
    match /stories/{storyId} {
      allow read, write: if isSignedIn();
    }

    // ─── E-commerce / Biz Products ───────────────────────────────────────────
    match /biz_products/{productId} {
      allow read, write: if true;
    }

    // ─── FCM Tokens (Sharded) ────────────────────────────────────────────────
    match /fcm_tokens_shard_{shardId}/{tokenId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }

    // ─── User Notifications (Sharded) ────────────────────────────────────────
    match /user_notifications_shard_{shardId}/{notificationId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }
"""

if "match /stories/" not in content:
    content = content.replace(
        "// ─── Deny everything else", 
        new_rules + "\n    // ─── Deny everything else"
    )
    with open(path, 'w') as f:
        f.write(content)
    print("Added new rules.")
else:
    print("Rules already exist.")
