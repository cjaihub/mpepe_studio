import os

path = 'firestore.rules'
with open(path, 'r') as f:
    content = f.read()

# Remove the broken shard rules
content = content.replace("""    // ─── FCM Tokens (Sharded) ────────────────────────────────────────────────
    match /fcm_tokens_shard_{shardId}/{tokenId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }

    // ─── User Notifications (Sharded) ────────────────────────────────────────
    match /user_notifications_shard_{shardId}/{notificationId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }""", "")

# Add dynamic rules for the sharded collections inside the catch-all or at the top level
new_sharded = """
    // ─── Sharded Collections ─────────────────────────────────────────────────
    match /{collectionId}/{docId} {
      allow read, write: if isSignedIn() && (
        collectionId.matches('fcm_tokens_shard_.*') ||
        collectionId.matches('user_notifications_shard_.*')
      );
    }
"""

content = content.replace(
    "// ─── Deny everything else", 
    new_sharded + "\n    // ─── Deny everything else"
)

with open(path, 'w') as f:
    f.write(content)
print("Fixed rules")
