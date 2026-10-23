sed -i '' '/match \/posts\/{postId} {/,/}/c\
    match /posts/{postId} {\
      allow read: if isSignedIn();\
      allow create: if isSignedIn() && request.resource.data.authorId == request.auth.uid;\
      allow update, delete: if isSignedIn() && resource.data.authorId == request.auth.uid;\
      \
      match /comments/{commentId} {\
        allow read: if isSignedIn();\
        allow create: if isSignedIn() && request.resource.data.authorId == request.auth.uid;\
        allow update, delete: if isSignedIn() && resource.data.authorId == request.auth.uid;\
      }\
    }\
' firestore.rules
