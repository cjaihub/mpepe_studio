rules = """rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // ─── Helper functions ────────────────────────────────────────────────────
    function isSignedIn() {
      return request.auth != null;
    }

    function isOwner(uid) {
      return isSignedIn() && request.auth.uid == uid;
    }

    function isActiveUser() {
      return isSignedIn() &&
             get(/databases/$(database)/documents/users/$(request.auth.uid)).data.status == 'active';
    }

    function isAdmin() {
      return isSignedIn() &&
             get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    // ─── Users ───────────────────────────────────────────────────────────────
    match /users/{uid} {
      allow read: if isSignedIn();
      allow write: if isOwner(uid) || isAdmin();
      
      match /{document=**} {
        allow read, write: if isOwner(uid) || isAdmin();
      }
    }

    // ─── Telemetry Events ────────────────────────────────────────────────────────
    match /telemetry_events/{eventId} {
      allow read, write: if isSignedIn();
    }

    // ─── Missing Social Collections ──────────────────────────────────────────
    match /content_likes/{likeId} {
      allow read, write: if isSignedIn();
    }
    match /content_saves/{saveId} {
      allow read, write: if isSignedIn();
    }
    match /content_reposts/{repostId} {
      allow read, write: if isSignedIn();
    }
    match /reactions/{reactionId} {
      allow read, write: if isSignedIn();
    }
    match /social_events/{eventId} {
      allow read, write: if isSignedIn();
    }

    // ─── Notifications ───────────────────────────────────────────────────────
    match /notifications/{notificationId} {
      // Users can only read their own notifications
      allow read: if isSignedIn() && resource.data.userId == request.auth.uid;
      // Notifications can be created by any active user (server functions or the user themselves)
      allow create: if isActiveUser();
      // Users can update (mark as read) their own notifications
      allow update: if isSignedIn() && resource.data.userId == request.auth.uid;
      // Users can delete their own notifications; admins can delete any
      allow delete: if isSignedIn() && (resource.data.userId == request.auth.uid || isAdmin());
    }

    // ─── Posts ───────────────────────────────────────────────────────────────
    match /posts/{postId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() && request.resource.data.authorId == request.auth.uid;
      allow update, delete: if isSignedIn() && resource.data.authorId == request.auth.uid;
      
      match /comments/{commentId} {
        allow read: if isSignedIn();
        allow create: if isSignedIn() && request.resource.data.authorId == request.auth.uid;
        allow update, delete: if isSignedIn() && resource.data.authorId == request.auth.uid;
      }
    }

    // ─── Biz Products ────────────────────────────────────────────────────────
    match /biz_products/{productId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() && request.resource.data.ownerId == request.auth.uid;
      allow update, delete: if isSignedIn() && resource.data.ownerId == request.auth.uid;
    }

    // ─── Comments ────────────────────────────────────────────────────────────
    match /comments/{commentId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() && request.resource.data.authorId == request.auth.uid;
      allow update, delete: if isSignedIn() && resource.data.authorId == request.auth.uid;
    }

    // ─── Interactions ────────────────────────────────────────────────────────
    match /interactions/{interactionId} {
      allow read, write: if isSignedIn();
    }

    // ─── Relationships ───────────────────────────────────────────────────────
    match /relationships/{relationshipId} {
      allow read, write: if isSignedIn();
    }

    // ─── User Stories ────────────────────────────────────────────────────────
    match /user_stories/{storyId} {
      allow read, write: if isSignedIn();
    }

    // ─── Content Views ───────────────────────────────────────────────────────
    match /content_views/{viewId} {
      allow read, write: if isSignedIn();
    }

    // ─── Content ─────────────────────────────────────────────────────────────
    match /content/{contentId} {
      allow read, write: if isSignedIn();
    }

    // ─── Chats ───────────────────────────────────────────────────────────────
    match /chats/{chatId} {
      allow read, write: if isSignedIn();
      
      match /{document=**} {
        allow read, write: if isSignedIn();
      }
    }

    // ─── Deny everything else ────────────────────────────────────────────────
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
"""
with open("firestore.rules", "w") as f:
    f.write(rules)
