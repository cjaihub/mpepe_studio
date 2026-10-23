sed -i '' '43i\
    // ─── Missing Social Collections ──────────────────────────────────────────\
    match /content_likes/{likeId} {\
      allow read, write: if isSignedIn();\
    }\
    match /content_saves/{saveId} {\
      allow read, write: if isSignedIn();\
    }\
    match /content_reposts/{repostId} {\
      allow read, write: if isSignedIn();\
    }\
    match /reactions/{reactionId} {\
      allow read, write: if isSignedIn();\
    }\
    match /social_events/{eventId} {\
      allow read, write: if isSignedIn();\
    }\
' firestore.rules
