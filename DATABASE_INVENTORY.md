# Database Inventory

## Data Store
- **Provider**: Google Cloud Firestore (NoSQL)
- **Persistence**: Explicitly disabled on startup to prevent disk I/O bottlenecks.

## Core Collections & Models

### 1. `messages` & `conversations`
- **`Conversation`**: Contains `participants`, metadata.
- **`Message`**: Tied to `conversationId`, stores `senderId`, `content`, `status`, `attachments`.

### 2. `posts` (Social)
- **`Post`**: `authorId`, `content`, `type` (text, image, carousel, reel, short, live), `attachments`, `mentions`, counts (reaction, comment, share, view), `algorithmicScore`, `createdAt`.

### 3. `users` & Identity
- **`User`**: Stored under `/users/{uid}`.
- Subcollections: `ai_audit_logs` (for auditing privileged AI operations).

### 4. `relationships` (Social Graph)
- **`Relationship`**: Follower mapping (`followerId`, `followingId`, `status`).

### 5. AI Security Logs
- Stored as a subcollection under user documents (`ai_audit_logs`).

## Data Access Pattern
- Models typically implement `.fromFirestore(DocumentSnapshot)` factory methods and `.toMap()` serialization methods.
- Real-time data is served to UI via Riverpod `StreamProvider` configurations in repositories.
