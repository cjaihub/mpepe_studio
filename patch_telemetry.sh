sed -i '' '40i\
    // ─── Telemetry Events ────────────────────────────────────────────────────────\
    match /telemetry_events/{eventId} {\
      allow read, write: if isSignedIn();\
    }\
' firestore.rules
