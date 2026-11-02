# Oneova: Project Changelog

## [2026-11-02] - v1.0.0+9 (Play Store Build 9)
### Added & Updated
- **Fail-Safe Resilient Live Streaming**: Upgraded `LiveSetupWizardScreen` with automatic instant fallback to direct Firestore & WebRTC live streaming (`LiveService.startStream` + `LiveStageMediaController`). Creators are never locked out of going live due to Cloud Function billing or connection errors.
- **Classic Host View & Live Room Gate**: Connected `LiveRoomGate` to `LiveClassicHostView` for hosts, enabling full front/back camera switching, mic mute toggles, live comment feeds, animated hearts, and quick access to Live Advanced Settings & Looks (`LiveAdvancedSettingsSheet`).
- **Cloud Functions Memory Hardening**: Upgraded `lsStart` and `lsToken` Cloud Functions to 512 MiB to eliminate 256 MiB memory exhaustion crashes during LiveKit room orchestration.
- **WebRTC Call Drop & Native Crash Hardening**: Fixed C++ SIGSEGV crash during peer disposal order, capped ICE restarts to 3 with exponential backoff, and protected audio recorder sessions with try-catch listeners.
- **Live User Presence & Realtime Action Notifications**: Added `LiveUserPresenceDot` with glowing pulse ring for online/in-call/in-live statuses and real-time interactive notifications for comments and likes with inline reply and like-back actions.
- **Reels Feed Spacing & Corner Polish**: Eliminated bottom black void, stabilized navigation docking, updated corner radius to 18px with subtle hairline border, and upgraded video placeholders to dark shimmer gradients.

## [2026-11-02] - v1.0.0+7 (Play Store Build 7)
### Added & Updated
- **Ova Main Interface & Overlay Voice Mode**: Transformed `/hub/ai` into the dedicated Ova Main Workspace (`Home`, `AI Agents`, `Live Voice`, `Explore`, `Library`, `History`, `Personal`/`Work projects`/`Research` workspaces) separate from the compact `OvaAssistantSheet` overlay, sharing unified real-time history & library (`OvaSharedHistoryService`) and adding live voice mode (`OvaFluidVoiceOrb`) to both surfaces.
- **Multilingual Auto-Detection & Translation**: Added `OneovaLanguageService`, `OneovaLanguageActionSheet`, and `chatAssist` (`translate` & `translateVoice` with synthesized voice matching) across chats, voice notes, comments, captions, and profiles.
- **Universal Voice Typing**: Added `OneovaVoiceTypingButton` across app text fields backed by the `voiceTidy` Vertex AI callable function.
- **Live Studio 3D Pool & Watch Party**: Added real-time multiplayer 8-ball pool (`lsPool` + physics simulation) with live camera stage integration, plus synchronized Watch Together (`lsWatch`, `lsYouTubeSearch`) and GIF comments (`lsGifSearch`).
- **Business Location Auto-Detector & Profile Suite**: Added `OneovaLocationDetector` for profiles and Business verification, searchable categories, AI bio suggestions (`OneovaAiBioSheet`), account-completion reminders, and Share to Status (`shareToAudience`).
- **Reels & Chat Polish**: Enforced automatic Reels audio muting when leaving the active feed screen, removed auto-popping chat banners, and added auto-hiding bottom navigation.
- **Security & Backend**: Bound encrypted Gmail OAuth refresh tokens to `users/{uid}/secure_tokens/gmail` (AES-256-GCM with `uid` AAD) and deployed updated Firestore rules, indexes, Storage rules, and Cloud Functions.

## [2026-09-30] - Platform Hardening & Intelligence
### Added
- **Notification Engine**: Added Quiet Hours and AI Security Suppression blocks.
- **Daily Brief**: Implemented AI insights mapped via Fact, Calculation, and Recommendation boundaries.
- **Mobile Resilience**: Added version-vector locking to prevent stale offline overwrites during Sync operations.
- **Performance Engine**: Added empirical trace evaluators for non-speculative optimization mapping.
- **Instrumentation**: Added global Privacy Scrubber blocking passwords, tokens, and locations from telemetry logs.
- **Authoritative Counters**: Unified counter states utilizing UI deltas and network rollback execution.
- **Connector Health**: Added live HTTP ping evaluations parsing 429 and 403 provider responses.
