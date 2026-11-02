# Oneova Changelog

## [2026-11-02] v1.0.0+9 — Play Store Build 9: Feed-First Launch, Permanent Single Sign-On & Stability Architecture
- **Added**: Instant Feed-First Onboarding. The app unconditionally launches into the Reel/Feed screen (`/hub/home`), allowing new installs and guest users to immediately watch, discover, and enjoy content without forced login walls.
- **Enhanced**: Single Permanent Sign-In. Eliminated 5-minute background session timeouts in `main.dart` and arbitrary session locks in `AppLifecycleObserver` and `LoginSecurity`. Users log in once and remain permanently authenticated.
- **Fixed**: App Stability Overview & Crash Resolution. Resolved the startup login crash and 2FA factor loop on `MainLoginScreen` (`/auth/main_login`). Added a prominent "Watch Reels" button to immediately return to the feed.
- **Enhanced**: Reels Feed Bottom Layout Polish. Eliminated the empty space below the comment bar by stabilizing the bottom navigation dock on Home and seating the overlay contents flush with the bottom dock.
- **Enhanced**: Super Premium Reel Geometry. Elevated reel corner curvature ($\text{radius} = 22.0 + 12.0 \times t$) with anti-aliasing for a luxury executive mobile feel.
- **Enhanced**: Workstation Decluttering. Bottom navigation is cleanly concealed in secondary tabs (Studio, Messages, AI Lab, Me, Settings, and Editors) with universal stack-safe back navigation.
- **Added**: Optional Biometric App Lock (`OneovaBiometricLockService`). Defaults to disabled (zero barrier) with opt-in toggle in Privacy & Security settings.
- **Added**: Oneova Security Shield (`OneovaSecurityShield`). Protects against phishing links, URL intent tampering, and credential theft with automatic threat neutralization and emergency session isolation.
- **Added**: End-to-End Encrypted AI Vault (`OneovaAiEncryptionVault`) & Autonomous Executor (`OvaAutonomousExecutor`). AES-256 client-side payload encryption for assistant interactions, paired with confident autonomous execution ($\ge 0.80$).

## [2026-11-02] v1.0.0+8 — Play Store Build 8 & Core Studio Enhancements
- **Added**: Built-in Auto-Transcription & Realtime CC Subtitles (`OneovaTranscriptionService`, `OneovaCaptionOverlay`, `oneovaCaptionsEnabledProvider`). Features YouTube-style `CC` control on the reel dock, real-time synchronized subtitles with subtitle cross-fade, in-advance background transcription with Firestore persistence, and interactive transcript sheet (`showOneovaTranscriptSheet`) with searchable dialogue and seek-to-timestamp playback.
- **Enhanced**: Reels feed bottom overlay gap eliminated. Comment bar, quick reactions, and audio pill now sit flush against the bottom edge via reactive `bottomInset` and smooth curve animation.
- **Enhanced**: Luxury curved reel frame with dynamic corner curvature ($\text{radius} = 16.0 + 18.0 \times t$) and refined aspect scaling.
- **Enhanced**: Clean workstation layout. Bottom navigation automatically concealed when navigating outside the Reels feed (Studio, Chat, AI Lab, Team, Settings, and Editors).
- **Added**: Universal stack-safe back navigation with haptic feedback and fallback to Home across Studio, Chat, AI Lab, Team, Profile, Settings, and Production workstations.
- **Enhanced**: Zero background audio leakage & hanging clip prevention. Instant auto-mute (`0.0`) and player slot pausing when screens are inactive or obscured, with clean automatic resumption on return.
- **Added**: LiveKit Studio v2 AR Live Face Effects (Glasses, Caps & Hats, Wigs & Hair, Masks & FX) and Oneova Looks (Clean Pro, Teal & Warm, Golden Hour, Moody Noir, Velvet Pop) with compact executive controls and haptic response.
- **Enhanced**: Post screen (`MediaPreviewScreen`, `PremiumPostScreen`) and Export Center lifecycle management with background video pause and safe draft preservation.

## [2026-11-02] v1.0.0+7 — Play Store Build 7 & Full Backend Rollout
- **Added**: Dedicated Ova Main Interface (`/hub/ai`) with navigation drawer, workspaces (`Personal`, `Work projects`, `Research`), `AI Agents`, `Explore`, `Library`, `History`, and full-screen `Live Voice` orb, plus `[Chat | Voice]` mode on the separate Overlay Assistant—sharing real-time history and activities (`OvaSharedHistoryService`).
- **Added**: Automatic language detection & 1-tap translation (`OneovaLanguageService`, `OneovaLanguageActionSheet`, `chatAssist` text & voice note translation) and universal field voice dictation (`OneovaVoiceTypingButton` + `voiceTidy`).
- **Added**: Live Studio multiplayer 3D 8-Ball Pool (`lsPool`) with stage camera integration, Watch Together (`lsWatch`, `lsYouTubeSearch`), and GIF comments (`lsGifSearch`).
- **Added**: Universal location auto-detection (`OneovaLocationDetector`) for Business verification and profiles, searchable categories, AI bio generator (`OneovaAiBioSheet`), completion reminders, and Share to Status.
- **Fixed**: Reels auto-mute whenever inactive; chat screen banner cleanup and auto-hiding bottom navigation.

## [2026-09-25] Sprint Completion
- **Added**: Background AI Agent with permission gating and `PAUSE ALL AI` kill switch.
- **Added**: Command Palette (`Cmd+K`) for rapid navigation and action execution.
- **Added**: Centralized `AppModals` system to prevent destructive silent actions.
- **Added**: `WorkflowEngine` for automation with infinite loop detection and rate limiting.
- **Added**: `SystemStatusService` for exponential backoff realtime recovery.
- **Added**: `AiSecurityGateway` preventing prompt injection and enforcing backend IAM on AI tools.
- **Added**: `ApmService` for data-driven APM trace profiling.
- **Added**: OWASP Top 10 API Security compliance via `docs/API_INVENTORY.md` and `PROJECT_SECURITY_MODEL.md`.
