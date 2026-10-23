# API Inventory

## Internal Backend API (Firebase)
- **Authentication**: `FirebaseAuth.instance` calls for sign up, sign in, OAuth (Google).
- **Database**: `FirebaseFirestore.instance` queries. Operations are localized in repository classes (e.g., `MessagingRepository`, `AuthRepository`).
- **Storage**: (Assumed) `FirebaseStorage` for media attachments.
- **Functions**: Handled securely, no explicit direct API links found in core layout yet, but used for WebRTC signaling and AI generation.

## External Integrations
- **Social Connectors**: Meta (Instagram/Facebook) and TikTok wizard flows.
- **AI Providers**: Gemini Live Voice mode and LLM-powered backend processing.
- **YouTube API**: Used extensively in `lib/youtube_manager` for channel metrics, uploads, and analytics.

## Native & Desktop Integrations
- **Native Plugin Server**: A local WebSocket or HTTP server (`NativePluginServer()`) running in Desktop environments to communicate with professional applications like DaVinci Resolve and Adobe Premiere.
